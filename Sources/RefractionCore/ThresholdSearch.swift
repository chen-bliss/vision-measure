import Foundation

/// Bracket each directional far point with observed pass/fail blocks; never extrapolate missing endpoints.
public struct ThresholdSearch {
    public enum Phase { case nearEndpoint, farEndpoint, bisect, complete, failed }
    public private(set) var phase: Phase = .nearEndpoint
    public private(set) var targetPower: Double = 5
    public private(set) var answers: [Bool] = []
    public private(set) var failure: String?
    private var nearPass: Double = 5
    private var farFail: Double = 1.0 / 3
    private var distanceErrors: [Double] = []
    private var confirmingEndpoint = false
    public static let blockSize = 16
    public static let passesRequired = 13
    public var targetMeters: Double { 1 / targetPower }
    public var blockProgress: Int { answers.count }
    public var finished: Bool { phase == .complete || phase == .failed }
    public init(nearMeters: Double = 0.20, farMeters: Double = 3) {
        // Caller must select a near point that the physical screen can resolve.
        nearPass = 1 / max(0.20, min(nearMeters, 2))
        farFail = 1 / max(2.01, min(farMeters, 3))
        targetPower = nearPass
    }
    public mutating func submit(correct: Bool, distance: DistanceReading, now: Date = Date(), manualDistanceStillConfirmed: Bool = false) throws {
        guard !finished else { throw MeasurementError.invalid("当前方向已结束。") }
        try distance.validate(now: now, manualDistanceStillConfirmed: manualDistanceStillConfirmed)
        guard abs(1 / distance.meters - targetPower) <= 0.06 else {
            throw MeasurementError.invalid("距离尚未到达目标位置，请先调整距离。")
        }
        answers.append(correct); distanceErrors.append(distance.vergenceUncertainty)
        guard answers.count == Self.blockSize else { return }
        let passed = answers.filter { $0 }.count >= Self.passesRequired
        answers.removeAll()
        switch phase {
        case .nearEndpoint:
            if !passed && !confirmingEndpoint { confirmingEndpoint = true; return }
            guard passed else { fail("在最近距离仍无法稳定辨认；超出本方法范围，或需要重新练习、检查图案尺寸。"); return }
            confirmingEndpoint = false
            phase = .farEndpoint; targetPower = farFail
        case .farEndpoint:
            if passed && !confirmingEndpoint { confirmingEndpoint = true; return }
            guard !passed else { fail("最远距离仍可辨认，没有测到远点边界；不能据此报告零度或推算度数。"); return }
            confirmingEndpoint = false
            phase = .bisect; targetPower = (nearPass + farFail) / 2
        case .bisect:
            if passed { nearPass = targetPower } else { farFail = targetPower }
            if nearPass - farFail <= 0.125 { phase = .complete }
            else { targetPower = (nearPass + farFail) / 2 }
        default: break
        }
    }
    private mutating func fail(_ message: String) { failure = message; phase = .failed }
    public func result(meridian: Double, repeatIndex: Int) throws -> MeridianThreshold {
        guard phase == .complete else { throw MeasurementError.invalid(failure ?? "尚未找到两侧边界。") }
        let halfBracket = (nearPass - farFail) / 2
        let uncertainty = hypot(halfBracket, distanceErrors.max() ?? 0.15)
        return MeridianThreshold(meridian: meridian, repeatIndex: repeatIndex,
                                 power: -(nearPass + farFail) / 2, uncertainty: uncertainty,
                                 nearPassPower: nearPass, farFailPower: farFail)
    }
}
