import AVFoundation
import Vision
import Combine
import RefractionCore
#if os(iOS)
import ARKit
#endif

struct FaceSample {
    var scale: Double
    var roll: Double
    var yaw: Double
    var pitch: Double
    var jitter: Double
    var signature: String
    var timestamp: Date
}

final class CameraService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var status = "摄像头未开启，可以直接使用人工测距。"
    @Published var face: FaceSample?
    @Published var depth: DistanceReading?
    @Published var running = false
    private let capture = AVCaptureSession()
    private let queue = DispatchQueue(label: "visionmeasure.camera")
    private var scales: [Double] = []
    private var lastFrame = Date.distantPast
    private var signature = ""
    private var generation = 0
    private var captureGeneration = 0
    private var activeOutput: AVCaptureVideoDataOutput?
    private var captureDevice: AVCaptureDevice?
    #if os(iOS)
    private let arSession = ARSession()
    private var arStartedAt = 0.0
    #endif

    func start(preferDepth: Bool = true) {
        stop()
        let token = generation
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure(preferDepth: preferDepth, token: token)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self, self.generation == token else { return }
                    if granted { self.configure(preferDepth: preferDepth, token: token) }
                    else { self.status = "未授权摄像头，请使用人工测距。" }
                }
            }
        default: status = "摄像头不可用或未授权，请使用人工测距。"
        }
    }
    func stop() {
        generation += 1
        #if os(iOS)
        arSession.pause()
        #endif
        queue.async { [weak self] in self?.activeOutput = nil; self?.captureDevice = nil; self?.capture.stopRunning(); self?.scales.removeAll() }
        face = nil; depth = nil; running = false
    }
    private func configure(preferDepth: Bool, token: Int) {
        #if os(iOS)
        if preferDepth, ARFaceTrackingConfiguration.isSupported,
           AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) != nil {
            arSession.delegate = self
            arSession.delegateQueue = .main
            arStartedAt = ProcessInfo.processInfo.systemUptime
            arSession.run(ARFaceTrackingConfiguration(), options: [.resetTracking, .removeExistingAnchors])
            running = true; status = "正在检查深度数据；若无读数，请切换普通摄像头。"
            return
        }
        #endif
        status = "正在开启普通摄像头，需要两个实测距离校准。"
        queue.async { [weak self] in
            guard let self = self else { return }
            self.capture.beginConfiguration()
            self.capture.inputs.forEach { self.capture.removeInput($0) }
            self.capture.outputs.forEach { self.capture.removeOutput($0) }
            #if os(iOS)
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .front)
            #else
            let device = AVCaptureDevice.default(for: .video)
            #endif
            guard let device = device, let input = try? AVCaptureDeviceInput(device: device), self.capture.canAddInput(input) else {
                self.capture.commitConfiguration()
                DispatchQueue.main.async { if self.generation == token { self.status = "没有可用摄像头，请使用人工测距。" } }
                return
            }
            self.capture.sessionPreset = .high
            self.capture.addInput(input)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.setSampleBufferDelegate(self, queue: self.queue)
            guard self.capture.canAddOutput(output) else {
                self.capture.commitConfiguration()
                DispatchQueue.main.async { if self.generation == token { self.status = "无法读取画面，请使用人工测距。" } }
                return
            }
            self.capture.addOutput(output)
            self.activeOutput = output
            self.captureDevice = device
            self.captureGeneration = token
            #if os(iOS)
            if let connection = output.connection(with: .video), connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
            #endif
            self.signature = device.uniqueID + ":" + UUID().uuidString
            self.capture.commitConfiguration()
            self.capture.startRunning()
            DispatchQueue.main.async {
                guard self.generation == token else { return }
                self.running = true; self.status = "普通摄像头已开启，请正视屏幕并完成距离校准。"
            }
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard output === activeOutput else { return }
        let token = captureGeneration
        let now = Date()
        guard now.timeIntervalSince(lastFrame) > 0.09 else { return }
        if now.timeIntervalSince(lastFrame) > 0.4 { scales.removeAll() }
        lastFrame = now
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectFaceLandmarksRequest()
        do {
            try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up).perform([request])
            guard let faces = request.results, faces.count == 1, let f = faces.first,
                  f.confidence > 0.8, f.boundingBox.minX > 0.02, f.boundingBox.maxX < 0.98,
                  f.boundingBox.minY > 0.02, f.boundingBox.maxY < 0.98,
                  let yaw = f.yaw?.doubleValue, let roll = f.roll?.doubleValue,
                  let pitch = f.pitch?.doubleValue else {
                scales.removeAll()
                DispatchQueue.main.async {
                    guard self.generation == token, self.running else { return }
                    self.face = nil; self.status = "请让一张完整人脸正对摄像头，避免遮住眉毛、鼻子和嘴。"
                }
                return
            }
            let scale = sqrt(f.boundingBox.width * f.boundingBox.height)
            scales.append(scale); if scales.count > 12 { scales.removeFirst() }
            let mean = scales.reduce(0,+) / Double(scales.count)
            let jitter = sqrt(scales.map { pow($0-mean,2) }.reduce(0,+) / Double(scales.count)) / mean
            let physicalID = captureDevice?.activePrimaryConstituent?.uniqueID ?? captureDevice?.uniqueID ?? "unknown"
            #if os(iOS)
            let opticalState = String(format:"%.5f:%.3f",locale:Locale(identifier:"en_US_POSIX"),
                                      Double(captureDevice?.videoZoomFactor ?? 1), Double(captureDevice?.activeFormat.videoFieldOfView ?? 0))
            #else
            let opticalState = captureDevice.map { String(describing:ObjectIdentifier($0.activeFormat)) } ?? "unknown-format"
            #endif
            let signature = self.signature + ":\(physicalID):\(opticalState):\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))"
            let sample = FaceSample(scale: mean, roll: roll, yaw: yaw, pitch: pitch,
                                    jitter: scales.count < 10 ? 1 : jitter, signature: signature, timestamp: now)
            let stable = scales.count >= 10 && jitter < 0.015
            DispatchQueue.main.async {
                guard self.generation == token, self.running else { return }
                self.face = sample; self.status = stable ? "人脸稳定；测距仍需个人校准。" : "请保持正视并稳定约一秒。"
            }
        } catch {
            DispatchQueue.main.async {
                guard self.generation == token, self.running else { return }
                self.face = nil; self.status = "画面识别失败，可重新开启摄像头或人工测距。"
            }
        }
    }
}

#if os(iOS)
extension CameraService: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard running, frame.timestamp >= arStartedAt else { return }
        guard frame.capturedDepthData != nil, case .normal = frame.camera.trackingState,
              let face = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first, face.isTracked else {
            DispatchQueue.main.async { self.depth = nil; self.status = "深度读数不可用，请调整位置或切换普通摄像头。" }
            return
        }
        let eye = (face.leftEyeTransform.columns.3 + face.rightEyeTransform.columns.3) / 2
        let p = simd_inverse(frame.camera.transform) * face.transform * eye
        let meters = Double(abs(p.z))
        // Sensor error, camera/screen offset and geometry require device-specific validation.
        let reading = DistanceReading(meters: meters, uncertaintyMeters: max(0.008, meters * 0.02), source: .depth)
        DispatchQueue.main.async { self.depth = reading; self.status = "深度数据可用；尚未经过该机型的测量精度验证。" }
    }
    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { self.depth = nil; self.status = "深度会话中断，请切换普通摄像头或人工测距。" }
    }
    func sessionWasInterrupted(_ session: ARSession) { DispatchQueue.main.async { self.depth = nil } }
}
#endif
