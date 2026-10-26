import Foundation

/// Individual, session-specific pinhole scale calibration. Never uses average face size.
public struct CameraCalibration: Codable {
    public let referenceScale: Double
    public let referenceMeters: Double
    public let referenceUncertainty: Double
    public let referenceRoll: Double
    public let referenceYaw: Double
    public let referencePitch: Double
    public let verificationMeters: Double
    public let verificationRelativeError: Double
    public let cameraSignature: String
    public let createdAt: Date
    public init(referenceScale: Double, referenceMeters: Double, referenceUncertainty: Double,
                referenceRoll: Double, referenceYaw: Double, referencePitch: Double,
                verificationScale: Double, verificationMeters: Double, cameraSignature: String) throws {
        guard [referenceScale, referenceMeters, referenceUncertainty, referenceRoll, referenceYaw, referencePitch,
               verificationScale, verificationMeters].allSatisfy({ $0.isFinite }),
              referenceScale > 0, verificationScale > 0, referenceUncertainty > 0,
              (0.20...3).contains(referenceMeters), (0.20...3).contains(verificationMeters),
              abs(verificationMeters - referenceMeters) >= 0.15,
              abs(referenceRoll) < 0.12, abs(referenceYaw) < 0.12, abs(referencePitch) < 0.12 else {
            throw MeasurementError.invalid("请正视屏幕，在两个相差至少15厘米的已知距离完成校准。")
        }
        let error = abs(referenceMeters * referenceScale / verificationScale - verificationMeters) / verificationMeters
        guard error <= 0.03 else { throw MeasurementError.invalid("第二距离核验误差超过3%，请重新校准或改用人工测距。") }
        self.referenceScale = referenceScale; self.referenceMeters = referenceMeters
        self.referenceUncertainty = referenceUncertainty; self.referenceRoll = referenceRoll
        self.referenceYaw = referenceYaw; self.referencePitch = referencePitch
        self.verificationMeters = verificationMeters; verificationRelativeError = error
        self.cameraSignature = cameraSignature; createdAt = Date()
    }
    public func reading(scale: Double, roll: Double, yaw: Double, pitch: Double, relativeJitter: Double,
                        cameraSignature: String, now: Date = Date()) throws -> DistanceReading {
        guard cameraSignature == self.cameraSignature, now.timeIntervalSince(createdAt) < 1800,
              [scale, roll, yaw, pitch, relativeJitter].allSatisfy({ $0.isFinite }), scale > 0,
              abs(roll - referenceRoll) < 0.10, abs(yaw - referenceYaw) < 0.10,
              abs(pitch - referencePitch) < 0.10, relativeJitter >= 0, relativeJitter < 0.015 else {
            throw MeasurementError.invalid("姿态、画面或摄像头发生变化，请正视屏幕、保持稳定并重新校准。")
        }
        let meters = referenceMeters * referenceScale / scale
        guard meters >= min(referenceMeters, verificationMeters), meters <= max(referenceMeters, verificationMeters) else {
            throw MeasurementError.invalid("已超出两个校准距离之间的范围，请扩展校准或人工测距。")
        }
        // Conservative floor: two-point agreement does not establish absolute accuracy.
        let relativeError = max(0.02, referenceUncertainty / referenceMeters, verificationRelativeError, relativeJitter)
        let result = DistanceReading(meters: meters, uncertaintyMeters: meters * relativeError, source: .calibratedCamera, timestamp: now)
        try result.validate(now: now)
        return result
    }
}
