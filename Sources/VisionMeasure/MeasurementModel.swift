import Foundation
import SwiftUI
import RefractionCore
import Darwin
#if os(iOS)
import UIKit
#endif

@MainActor final class MeasurementModel: ObservableObject {
    @Published var page = 0
    @Published var participantID = ""
    @Published var eye: Eye = .right
    @Published var acknowledged = false
    @Published var adultSuitable = false
    @Published var screenMeasuredCM = ""
    @Published var pointsPerMM = 0.0
    @Published var screenConfirmed = false
    @Published var distanceMode = 0
    @Published var manualCM = ""
    @Published var manualErrorMM = "5"
    @Published var referenceCM = "40"
    @Published var verificationCM = "100"
    @Published var calibration: CameraCalibration?
    @Published var reading: DistanceReading?
    @Published var message = ""
    @Published var record: SessionRecord?
    @Published var search = ThresholdSearch()
    @Published var meridians: [Double] = []
    @Published var directionIndex = 0
    @Published var correctSide = Int.random(in: 0...1)
    @Published private(set) var stimulusID = UUID()
    @Published var testing = false
    @Published var training = false
    @Published var trainingCount = 0
    @Published var trainingCorrect = 0
    @Published var history: [SessionRecord] = []
    @Published var activeEstimate: ResearchEstimate?
    @Published var exportRecord: SessionRecord?
    @Published var showExport = false
    @Published var renderScale = 2.0
    @Published var nearestMeters = 0.2
    @Published var dataError = ""
    @Published var distanceIssue = L("尚无有效距离")
    @Published var maxPatchPoints = 120.0
    @Published var displayContext: DisplayContext?
    private var referenceFace: FaceSample?
    private var manualReading: DistanceReading?
    private var manualDistanceIssue = L("人工距离尚未确认。请填写实测距离，再点击“确认已实测，并保持不动”。")
    private var readySince: Date?
    private var stableReadings: [(Date, Double)] = []
    private var presentedAt = Date()
    private var visibleSince: Date?
    private var corruptHistory = false
    private var displayTracker = DisplayCalibrationTracker()
    private var displayActivity: NSObjectProtocol?
    var gapArcMinutes: Double { 1.0 }
    var displayedGapArcMinutes: Double { training ? 6.0 : gapArcMinutes }
    var displayedDiameterDegrees: Double { training ? 1.0 : 0.28 }
    var meridian: Double { meridians.isEmpty ? 0 : meridians[directionIndex % 6] }
    var repeatIndex: Int { directionIndex / 6 }
    var targetMeters: Double { training ? nearestMeters : search.targetMeters }
    var stripeWidth: Double {
        Optics.stripeWidthPoints(distance: reading?.meters ?? targetMeters, gapArcMinutes: displayedGapArcMinutes, pointsPerMillimeter: pointsPerMM)
    }
    var patchDiameter: Double {
        2 * tan(displayedDiameterDegrees / 2 * .pi / 180) * (reading?.meters ?? targetMeters) * 1000 * pointsPerMM
    }
    var stimulusBlockMessage: String? {
        guard testing else { return L("请先开始练习与测量。") }
        guard let reading = reading else { return distanceIssue }
        guard abs(1 / reading.meters - 1 / targetMeters) <= 0.06 else {
            let lower = max(20, 100 / (1 / targetMeters + 0.06))
            let upper = 100 / max(1 / targetMeters - 0.06, 1 / 3.0)
            return L("当前距离 %1$.1f 厘米，尚未到达目标。请到 %2$.1f–%3$.1f 厘米范围内；人工模式需重新实测并确认。", reading.meters * 100, lower, upper)
        }
        guard stripeWidth * renderScale >= 1.5 else {
            return L("当前距离下条纹像素不足。请检查蓝线实测长度并重新校准屏幕，不能通过猜填距离继续。")
        }
        guard patchDiameter <= maxPatchPoints - 8 else {
            return L("当前测试区域放不下完整图案。请保持设备姿态，停止本轮并重新校准显示区域。")
        }
        guard let readySince = readySince, Date().timeIntervalSince(readySince) >= 0.8 else {
            return L("距离已到位，正在等待读数稳定；请保持不动。")
        }
        return nil
    }
    var stimulusVisible: Bool { testing && stimulusBlockMessage == nil }
    var canAnswer: Bool { stimulusVisible && visibleSince.map { Date().timeIntervalSince($0) >= 0.8 } == true }
    var stimulusStatus: String {
        stimulusBlockMessage ?? (canAnswer ? L("哪一侧有条纹？不确定时请猜测。") : L("图案已显示，请观察片刻，按钮即将启用。"))
    }
    init() { loadHistory() }

    func calibrateScreen() {
        guard let cm = NumberInput.parse(screenMeasuredCM), cm.isFinite, (1...30).contains(cm) else {
            message = L("请用尺子测量蓝色线段的实际长度并输入厘米数。"); return
        }
        pointsPerMM = 200 / (cm * 10)
        screenConfirmed = true
        nearestMeters = max(0.20, 1.6 / (renderScale * pointsPerMM * 1000 * tan(.pi / (180 * 60))))
        nearestMeters = ceil(nearestMeters * 100) / 100
        message = nearestMeters < 2 ? L("屏幕已校准。最近测试距离为%ld厘米，由屏幕实际分辨能力决定。", Int(nearestMeters * 100)) : L("屏幕分辨能力不足以完成当前测试。")
    }
    var displayCalibrationSignature: String {
        guard let value=displayTracker.accepted else { return "unavailable" }
        return value.signature+":axis=\(value.interfaceAxis.map(String.init) ?? "unknown")"
    }
    @discardableResult func updateDisplayContext(_ context: DisplayContext?) -> Bool {
        let change=displayTracker.update(context)
        guard let accepted=displayTracker.accepted else { return false }
        displayContext=accepted; renderScale=accepted.scale
        if change == .geometry {
            screenConfirmed = false; pointsPerMM = 0
            resetDistance()
            if testing { stop(reason: L("显示区域或屏幕发生变化，本轮已停止，请重新校准后测试。")) }
            message = L("显示区域或屏幕发生变化，请重新测量蓝线，并重新确认距离或摄像头校准。")
        } else if change == .interfaceAxis {
            resetDistance()
            if testing { stop(reason:L("界面显示方向已改变，本轮已停止。屏幕尺寸校准保留，请重新确认观看距离后再开始。")) }
            message=L("界面显示方向已改变，屏幕尺寸校准保留；请重新确认观看距离。")
        }
        return change == .geometry || change == .interfaceAxis
    }
    func setManualDistance() {
        do {
            guard let cm = NumberInput.parse(manualCM), let mm = NumberInput.parse(manualErrorMM), cm.isFinite, mm.isFinite else {
                throw MeasurementError.invalid(L("请输入实际测量的距离和误差。"))
            }
            let value = DistanceReading(meters: cm / 100, uncertaintyMeters: mm / 1000, source: .manual)
            try value.validate()
            manualReading = value; reading = value; readySince = nil; visibleSince = nil; stableReadings = []
            manualDistanceIssue = ""
            message = L("人工距离已确认，不再按30秒重置。保持位置不动；每次移动、目标距离变化或中断后，需重新实测并确认。")
        } catch {
            message = error.localizedDescription; distanceIssue = message; manualDistanceIssue = message
            reading = nil; manualReading = nil
        }
    }
    func captureReference(_ face: FaceSample?) {
        guard let face = face, Date().timeIntervalSince(face.timestamp) < 0.5,
              face.jitter < 0.015, abs(face.roll) < 0.12, abs(face.yaw) < 0.12, abs(face.pitch) < 0.12 else {
            message = L("请正视屏幕并保持稳定，再记录校准点。"); return
        }
        referenceFace = face; calibration = nil
        message = L("第一个位置已记录。移动到第二个实测位置后点击核验。")
    }
    func verifyCamera(_ face: FaceSample?) {
        do {
            guard let first = referenceFace, let second = face, first.signature == second.signature,
                  Date().timeIntervalSince(first.timestamp) < 300, Date().timeIntervalSince(second.timestamp) < 0.5,
                  abs(first.roll - second.roll) < 0.08, abs(first.yaw - second.yaw) < 0.08,
                  abs(first.pitch - second.pitch) < 0.08, second.jitter < 0.015,
                  let cm1 = NumberInput.parse(referenceCM), let cm2 = NumberInput.parse(verificationCM), let mm = NumberInput.parse(manualErrorMM) else {
                throw MeasurementError.invalid(L("请保持相同姿态、相同摄像头，在两个实测距离完成校准。"))
            }
            calibration = try CameraCalibration(referenceScale: first.scale, referenceMeters: cm1 / 100,
                referenceUncertainty: mm / 1000, referenceRoll: first.roll, referenceYaw: first.yaw,
                referencePitch: first.pitch, verificationScale: second.scale, verificationMeters: cm2 / 100,
                cameraSignature: first.signature)
            message = L("两点校准通过，仅可在这两个距离之间估距。摄像头重启后需要重新校准。")
        } catch { message = error.localizedDescription; calibration = nil }
    }
    func resetDistance() {
        reading = nil; manualReading = nil; calibration = nil; referenceFace = nil
        manualDistanceIssue = L("人工距离尚未确认。请填写实测距离，再点击“确认已实测，并保持不动”。")
        readySince = nil; stableReadings = []
    }
    func refresh(camera: CameraService) {
        let now = Date()
        var next: DistanceReading?
        if distanceMode == 0 { next = manualReading; distanceIssue = manualDistanceIssue }
        else if let depth = camera.depth, now.timeIntervalSince(depth.timestamp) < 0.4 { next = depth }
        else if let face = camera.face, now.timeIntervalSince(face.timestamp) < 0.4, let calibration = calibration {
            do { next = try calibration.reading(scale: face.scale, roll: face.roll, yaw: face.yaw, pitch: face.pitch,
                                               relativeJitter: face.jitter, cameraSignature: face.signature) }
            catch { distanceIssue = error.localizedDescription }
        } else { distanceIssue = L("摄像头尚无可靠距离，请完成校准或切换人工测距") }
        if let value = next {
            do {
                try value.validate(now: now, maxAge: 0.4, manualDistanceStillConfirmed: distanceMode == 0 && manualReading != nil)
                reading = value
            } catch {
                reading = nil
                distanceIssue = error.localizedDescription
            }
        } else { reading = nil }
        guard testing, let value = reading, abs(1 / value.meters - 1 / targetMeters) <= 0.06 else {
            readySince = nil; visibleSince = nil; stableReadings = []; return
        }
        stableReadings.append((now, 1/value.meters))
        stableReadings.removeAll { now.timeIntervalSince($0.0) > 1 }
        let powers = stableReadings.map { $0.1 }
        if (powers.max() ?? 0) - (powers.min() ?? 0) > 0.04 { readySince = nil; visibleSince = nil; return }
        if readySince == nil { readySince = now }
        if stimulusVisible && visibleSince == nil { visibleSince = now }
    }
    func start() {
        guard !testing, screenConfirmed, pointsPerMM > 0, nearestMeters < 2,
              acknowledged, adultSuitable, !participantID.trimmingCharacters(in: .whitespaces).isEmpty else {
            message = L("请完成屏幕校准、匿名编号和适用条件确认。"); return
        }
        let notes = distanceMode == 0 ? "manual; uncertainty_mm=\(manualErrorMM); confirmation_policy=until_target_change_or_interruption; timestamp=original_confirmation" :
            "camera; reference_cm=\(referenceCM); verification_cm=\(verificationCM); verified=\(calibration != nil)"
        record = SessionRecord(participantID: participantID.trimmingCharacters(in: .whitespaces), eye: eye,
                               device: Self.deviceModel + "; " + ProcessInfo.processInfo.operatingSystemVersionString + "; scale=\(renderScale)",
                               screenPointsPerMillimeter: pointsPerMM, gapArcMinutes: gapArcMinutes,
                               consentAcknowledged: acknowledged, distanceCalibrationNotes: notes)
        record?.cameraCalibration = calibration
        record?.screenScale = renderScale
        record?.displayContext = displayContext
        record?.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? AppInfo.version
        record?.interfaceLanguage = AppLanguage.current.rawValue
        record?.sessionKind = ProcessInfo.processInfo.arguments.contains("--ui-test") ? "SYNTHETIC_UI_TEST" : "HUMAN_RESEARCH"
        meridians = [0,30,60,90,120,150].shuffled(); directionIndex = 0
        search = ThresholdSearch(nearMeters: nearestMeters)
        training = true; trainingCount = 0; trainingCorrect = 0
        testing = true; activeEstimate = nil; page = 2; newStimulus()
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = true
        #else
        displayActivity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled], reason: L("视觉测试期间保持屏幕显示"))
        #endif
        message = L("先完成8次练习：找出有条纹的一侧。若看不清，请猜测，勿眯眼。")
    }
    private func newStimulus() { stimulusID = UUID(); correctSide = Int.random(in: 0...1); presentedAt = Date(); visibleSince = nil; readySince = nil; stableReadings = [] }
    func answer(_ side: Int) {
        guard canAnswer, let distance = reading else { return }
        let manualStillConfirmed = distanceMode == 0 && manualReading != nil
        do { try distance.validate(maxAge: 0.4, manualDistanceStillConfirmed: manualStillConfirmed) }
        catch { message = error.localizedDescription; reading = nil; return }
        let previousTarget = targetMeters
        let trial = Trial(meridian: meridian, repeatIndex: training ? -1 : repeatIndex, targetPower: 1 / targetMeters,
                          correctSide: correctSide, answer: side, distance: distance,
                          reactionSeconds: Date().timeIntervalSince(presentedAt),
                          stimulusGapArcMinutes: displayedGapArcMinutes, stimulusDiameterDegrees: displayedDiameterDegrees)
        record?.trials.append(trial)
        if training {
            trainingCount += 1; if trial.correct { trainingCorrect += 1 }
            if trainingCount == 8 {
                guard trainingCorrect >= 7 else { stop(reason: L("练习未达到7/8正确，暂不能进行远点测量。请检查屏幕尺寸或重新练习。")); return }
                training = false; message = L("开始正式测试。移动到目标距离，位置稳定后选择有条纹的一侧。")
            }
        } else {
            do {
                try search.submit(correct: trial.correct, distance: distance, manualDistanceStillConfirmed: manualStillConfirmed)
                if search.phase == .failed { stop(reason: search.failure ?? L("当前测试超出范围。")); return }
                if search.phase == .complete {
                    record?.thresholds.append(try search.result(meridian: meridian, repeatIndex: repeatIndex))
                    directionIndex += 1
                    if directionIndex == 12 { finish(); return }
                    search = ThresholdSearch(nearMeters: nearestMeters)
                    message = L("当前方向完成。下一方向需要重新寻找边界，可随时停止并保留记录。")
                }
            } catch { message = error.localizedDescription }
        }
        if distanceMode == 0 && abs(targetMeters - previousTarget) > 1e-9 {
            resetDistance()
            manualDistanceIssue = L("目标距离已改变。请到新位置重新实测，再点击“确认已实测，并保持不动”。")
            distanceIssue = manualDistanceIssue
        }
        newStimulus()
        persistDraft()
    }
    func finish() {
        do {
            guard let thresholds = record?.thresholds else { return }
            let estimate = try RefractionFit.estimate(thresholds)
            record?.estimate = estimate; activeEstimate = estimate
            stop(reason: nil)
        } catch { stop(reason: error.localizedDescription) }
    }
    func stop(reason: String?) {
        testing = false; training = false; readySince = nil
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #else
        if let activity = displayActivity { ProcessInfo.processInfo.endActivity(activity); displayActivity = nil }
        #endif
        record?.finishedAt = Date(); record?.stopReason = reason
        message = reason ?? L("测试已完成。结果是未经临床验证的研究估计。")
        if let record = record { history.insert(record, at: 0); saveHistory() }
        page = 3
    }
    private var storageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(ProcessInfo.processInfo.arguments.contains("--ui-test") ? "VisionMeasure-UITests" : "VisionMeasure", isDirectory: true)
    }
    private func saveHistory() {
        do {
            try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            let filename = corruptHistory ? "recovered-sessions.json" : "sessions.json"
            try encoder.encode(history).write(to: storageURL.appendingPathComponent(filename), options: .atomic)
            try? FileManager.default.removeItem(at: storageURL.appendingPathComponent("draft.json"))
        } catch { dataError = L("记录保存失败：%@。请立即导出。", error.localizedDescription) }
    }
    private func persistDraft() {
        guard let record = record else { return }
        do {
            try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(record).write(to: storageURL.appendingPathComponent("draft.json"), options: .atomic)
        } catch { dataError = L("临时记录保存失败，请导出当前记录。") }
    }
    private func loadHistory() {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let url = storageURL.appendingPathComponent("sessions.json")
        if FileManager.default.fileExists(atPath: url.path) {
            do { history = try decoder.decode([SessionRecord].self, from: Data(contentsOf: url)) }
            catch { corruptHistory = true; dataError = L("历史记录无法读取，原文件已保留；新记录另存为 recovered-sessions.json，请导出备份。") }
        }
        let recoveredURL = storageURL.appendingPathComponent("recovered-sessions.json")
        if corruptHistory, let data = try? Data(contentsOf: recoveredURL), let recovered = try? decoder.decode([SessionRecord].self, from: data) {
            let known = Set(history.map(\.id))
            history.append(contentsOf: recovered.filter { !known.contains($0.id) })
            history.sort { $0.startedAt > $1.startedAt }
        }
        if let data = try? Data(contentsOf: storageURL.appendingPathComponent("draft.json")),
           var draft = try? decoder.decode(SessionRecord.self, from: data), !history.contains(where: { $0.id == draft.id }) {
            draft.stopReason = L("上次测试中断，仅恢复原始记录，未继续输出度数。")
            draft.finishedAt = Date(); history.insert(draft, at: 0)
        }
    }
    func deleteRecord(_ id: UUID) { history.removeAll { $0.id == id }; saveHistory() }
    func prepareExport(_ item: SessionRecord) { exportRecord = item; showExport = true }
    private static var deviceModel: String {
        #if os(macOS)
        let key = "hw.model"
        #else
        let key = "hw.machine"
        #endif
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0 else { return "unknown-model" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &bytes, &size, nil, 0) == 0 else { return "unknown-model" }
        return String(cString: bytes)
    }
}
