import Foundation

public enum MeasurementError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

public enum AppInfo {
    public static let version = "0.4.0"
    public static let build = "8"
}

/// Raw values are stored in exported records and read by `Tools/validate_study.py`; never translate them.
public enum Eye: String, Codable, CaseIterable {
    case right = "右眼", left = "左眼"
    public var localizedName: String { self == .right ? L("右眼") : L("左眼") }
}
public enum DistanceSource: String, Codable { case manual, calibratedCamera, depth }

public struct DistanceReading: Codable, Equatable {
    public var meters: Double
    /// Estimated measurement uncertainty, not clinical accuracy.
    public var uncertaintyMeters: Double
    public var source: DistanceSource
    public var timestamp: Date
    public init(meters: Double, uncertaintyMeters: Double, source: DistanceSource, timestamp: Date = Date()) {
        self.meters = meters; self.uncertaintyMeters = uncertaintyMeters
        self.source = source; self.timestamp = timestamp
    }
    public var vergenceUncertainty: Double { uncertaintyMeters / (meters * meters) }
    public func validate(now: Date = Date(), maxAge: Double = 30, manualDistanceStillConfirmed: Bool = false) throws {
        // A manual confirmation may remain valid at a fixed position. Preserve its original
        // timestamp; callers must revoke the confirmation on movement or interruption.
        let ageLimit = source == .manual && manualDistanceStillConfirmed ? Double.infinity : maxAge
        guard meters.isFinite, uncertaintyMeters.isFinite, (0.20...3.0).contains(meters),
              uncertaintyMeters > 0, uncertaintyMeters < meters,
              now.timeIntervalSince(timestamp) >= -1, now.timeIntervalSince(timestamp) <= ageLimit else {
            throw MeasurementError.invalid(L("距离无效或已过期，请重新测量；目前研究范围为20厘米至3米。"))
        }
        guard vergenceUncertainty <= 0.15 else {
            throw MeasurementError.invalid(L("距离误差过大。请提高测距精度或换用人工测距。"))
        }
    }
}

public struct Trial: Codable, Identifiable {
    public let id: UUID
    public let meridian: Double
    public let repeatIndex: Int
    public let targetPower: Double
    public let correctSide: Int
    public let answer: Int
    public let distance: DistanceReading
    public let timestamp: Date
    public let reactionSeconds: Double
    public let stimulusGapArcMinutes: Double?
    public let stimulusDiameterDegrees: Double?
    public var correct: Bool { answer == correctSide }
    public init(meridian: Double, repeatIndex: Int, targetPower: Double, correctSide: Int,
                answer: Int, distance: DistanceReading, reactionSeconds: Double, timestamp: Date = Date(),
                stimulusGapArcMinutes: Double? = nil, stimulusDiameterDegrees: Double? = nil) {
        id = UUID(); self.meridian = meridian; self.repeatIndex = repeatIndex
        self.targetPower = targetPower; self.correctSide = correctSide; self.answer = answer
        self.distance = distance; self.timestamp = timestamp; self.reactionSeconds = reactionSeconds
        self.stimulusGapArcMinutes = stimulusGapArcMinutes; self.stimulusDiameterDegrees = stimulusDiameterDegrees
    }
}

public struct MeridianThreshold: Codable, Identifiable {
    public let id: UUID
    public let meridian: Double
    public let repeatIndex: Int
    public let power: Double
    public let uncertainty: Double
    public let nearPassPower: Double
    public let farFailPower: Double
    public init(meridian: Double, repeatIndex: Int, power: Double, uncertainty: Double,
                nearPassPower: Double, farFailPower: Double) {
        id = UUID(); self.meridian = meridian; self.repeatIndex = repeatIndex
        self.power = power; self.uncertainty = uncertainty
        self.nearPassPower = nearPassPower; self.farFailPower = farFailPower
    }
}

public struct PowerVector: Codable, Equatable {
    public var m: Double
    public var j0: Double
    public var j45: Double
    public init(m: Double, j0: Double, j45: Double) { self.m = m; self.j0 = j0; self.j45 = j45 }
    public init(sphere: Double, cylinder: Double, axis: Double) {
        m = sphere + cylinder / 2
        j0 = -cylinder / 2 * cos(2 * axis * .pi / 180)
        j45 = -cylinder / 2 * sin(2 * axis * .pi / 180)
    }
    public var sphere: Double { m + hypot(j0, j45) }
    public var cylinder: Double { -2 * hypot(j0, j45) }
    public var axis: Double {
        let value = atan2(j45, j0) * 90 / .pi
        return (value + 180).truncatingRemainder(dividingBy: 180)
    }
    public func power(at meridian: Double) -> Double {
        m + j0 * cos(2 * meridian * .pi / 180) + j45 * sin(2 * meridian * .pi / 180)
    }
}

public struct ResearchEstimate: Codable {
    public var vector: PowerVector
    public var residualRMSE: Double
    public var maximumRepeatDifference: Double
    public var instrumentStandardError: Double
    public var axisReportable: Bool
    public var clinicalValidation: String = "UNVALIDATED_RESEARCH_ONLY"
}

public struct SessionRecord: Codable, Identifiable {
    public var id = UUID()
    public var schemaVersion = 1
    public var algorithmVersion = "farpoint-grating-0.1.1"
    public var participantID: String
    public var eye: Eye
    public var startedAt = Date()
    public var finishedAt: Date?
    public var device: String
    public var screenPointsPerMillimeter: Double
    public var gapArcMinutes: Double
    public var consentAcknowledged: Bool
    public var distanceCalibrationNotes: String
    public var cameraCalibration: CameraCalibration?
    public var screenScale: Double?
    public var sessionKind: String?
    public var displayContext: DisplayContext?
    public var appVersion: String?
    /// Interface language during the session; instructions in another language may change comprehension.
    public var interfaceLanguage: String?
    public var trials: [Trial] = []
    public var thresholds: [MeridianThreshold] = []
    public var estimate: ResearchEstimate?
    public var stopReason: String?
    public init(participantID: String, eye: Eye, device: String, screenPointsPerMillimeter: Double,
                gapArcMinutes: Double, consentAcknowledged: Bool, distanceCalibrationNotes: String) {
        self.participantID = participantID; self.eye = eye; self.device = device
        self.screenPointsPerMillimeter = screenPointsPerMillimeter; self.gapArcMinutes = gapArcMinutes
        self.consentAcknowledged = consentAcknowledged; self.distanceCalibrationNotes = distanceCalibrationNotes
    }
}

public enum Optics {
    /// Line orientation is perpendicular to the optical meridian it probes.
    public static func stripeAngle(forMeridian degrees: Double) -> Double { (degrees + 90).truncatingRemainder(dividingBy: 180) }
    public static func stripeWidthPoints(distance: Double, gapArcMinutes: Double, pointsPerMillimeter: Double) -> Double {
        tan(gapArcMinutes * .pi / (180 * 60)) * distance * 1000 * pointsPerMillimeter
    }
    public static func axialDifference(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 180)
        return min(d, 180 - d)
    }
}
