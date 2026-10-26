import Foundation
import AVFoundation
import Speech
import Combine
import RefractionCore

/// Optional local-only commands for distances at which the user cannot reach the screen.
final class VoiceControl: ObservableObject {
    @Published var running = false
    @Published var status = "可使用键盘、协助者，或开启本机语音作答。"
    var onCommand: ((Int) -> Bool)?
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasTap = false
    private var answerGate = VoiceAnswerGate()
    private var acceptingAnswers = false
    private var recoveryAttempts = 0
    private var restartPending = false
    private var generation = 0
    private var taskGeneration = 0
    // Audio callback can run concurrently with cancellation/restart.
    private let requestLock = NSLock()
    private let audioQueue = DispatchQueue(label: "visionmeasure.voice.audio")
    private var audioActive = false

    func start() {
        stop()
        guard let recognizer = recognizer, recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
            status = "当前设备没有可用的本机中文语音识别。请用键盘或请协助者点击；不会切换云端识别。"; return
        }
        let token = generation
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            guard let self = self else { return }
            guard auth == .authorized else { DispatchQueue.main.async {
                guard self.generation == token else { return }
                self.status = "语音识别未授权，请用按钮或键盘。"
            }; return }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    guard self.generation == token else { return }
                    if granted { self.configure() }
                    else { self.status = "麦克风未授权，请用按钮或键盘。" }
                }
            }
        }
    }
    private func configure() {
        let token = generation
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                #if os(iOS)
                let audio = AVAudioSession.sharedInstance()
                try audio.setCategory(.record, mode: .measurement, options: [])
                try audio.setActive(true)
                self.audioActive = true
                #endif
                let input = self.engine.inputNode
                let format = input.outputFormat(forBus: 0)
                guard format.sampleRate > 0, format.channelCount > 0 else {
                    throw NSError(domain:"VisionMeasureAudio",code:1)
                }
                input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                    guard let self = self else { return }
                    self.requestLock.lock(); self.request?.append(buffer); self.requestLock.unlock()
                }
                self.hasTap = true
                self.engine.prepare(); try self.engine.start()
                DispatchQueue.main.async {
                    guard self.generation == token else { return }
                    self.running = true; self.beginTask()
                    self.updateStatus()
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.generation == token else { return }
                    self.stop(); self.status = "语音启动失败，请用按钮、键盘或协助者。"
                }
            }
        }
    }
    func updateMeasurement(trialID: UUID, ready: Bool) {
        let needsFreshAudio = answerGate.update(trialID:trialID, ready:ready)
        acceptingAnswers = ready
        // Do not carry audio from the previous picture or its settling period into this trial.
        if running && needsFreshAudio && !restartPending { beginTask() }
        if running && !restartPending { updateStatus() }
    }
    private func updateStatus() {
        status = acceptingAnswers
            ? "本机语音正在听：请说“左边”或“右边”；说“停止”结束。"
            : "本机语音已开启，等待图案就绪。请在按钮可用后说“左边”或“右边”；随时可说“停止”。"
    }
    private func detachTask() {
        taskGeneration += 1
        requestLock.lock(); let previous = request; request = nil; requestLock.unlock()
        previous?.endAudio()
        task?.cancel(); task = nil
    }
    private func beginTask() {
        guard running, let recognizer = recognizer, recognizer.supportsOnDeviceRecognition else { return }
        detachTask()
        restartPending = false
        let token = generation, taskToken = taskGeneration
        let gateToken = answerGate.beginTask()
        let next = SFSpeechAudioBufferRecognitionRequest()
        next.requiresOnDeviceRecognition = true
        next.shouldReportPartialResults = true
        next.contextualStrings = ["左边", "右边", "停止"]
        requestLock.lock(); request = next; requestLock.unlock()
        task = recognizer.recognitionTask(with: next) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self, self.generation == token, self.taskGeneration == taskToken, self.running else { return }
                if let result = result,
                   let command = self.answerGate.consume(result.bestTranscription.formattedString, taskToken:gateToken) {
                    self.recoveryAttempts = 0
                    if self.onCommand?(command) != true && command != -1 {
                        self.answerGate.rejectAnswer()
                        self.acceptingAnswers = false
                        self.beginTask()
                        self.updateStatus()
                    }
                }
                // onCommand may have stopped listening or advanced to a fresh task.
                guard self.running, self.generation == token, self.taskGeneration == taskToken else { return }
                if result?.isFinal == true {
                    self.recoveryAttempts = 0
                    self.scheduleRestart(after:0.15)
                } else if error != nil {
                    self.recoveryAttempts += 1
                    if self.recoveryAttempts <= 3 {
                        self.status = "语音正在恢复，请稍候再说；也可用按钮作答。"
                        self.scheduleRestart(after:0.4 * Double(self.recoveryAttempts))
                    } else {
                        self.stop()
                        self.status = "本机语音暂时不可用，请重新开启或用按钮作答。"
                    }
                }
            }
        }
    }
    private func scheduleRestart(after delay: TimeInterval) {
        detachTask()
        restartPending = true
        let token = generation, taskToken = taskGeneration
        DispatchQueue.main.asyncAfter(deadline:.now() + delay) { [weak self] in
            guard let self = self, self.running, self.generation == token, self.taskGeneration == taskToken else { return }
            self.beginTask()
            self.updateStatus()
        }
    }
    func stop() {
        generation += 1; running = false
        restartPending = false; recoveryAttempts = 0; acceptingAnswers = false
        answerGate = VoiceAnswerGate()
        status = "语音已关闭，可使用按钮、键盘或协助者作答。"
        detachTask()
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            self.engine.stop()
            if self.hasTap { self.engine.inputNode.removeTap(onBus:0); self.hasTap = false }
            #if os(iOS)
            if self.audioActive {
                try? AVAudioSession.sharedInstance().setActive(false, options:.notifyOthersOnDeactivation)
                self.audioActive = false
            }
            #endif
        }
    }
}
