import XCTest
@testable import RefractionCore

final class RefractionCoreTests: XCTestCase {
    func testConfirmedManualDistanceKeepsOriginalTimestampBeyondThirtySeconds() throws {
        let confirmedAt=Date(timeIntervalSince1970:1_000_000)
        let value=DistanceReading(meters:0.5,uncertaintyMeters:0.001,source:.manual,timestamp:confirmedAt)
        XCTAssertThrowsError(try value.validate(now:confirmedAt.addingTimeInterval(3600)))
        try value.validate(now:confirmedAt.addingTimeInterval(3600),manualDistanceStillConfirmed:true)
        XCTAssertEqual(value.timestamp,confirmedAt)
        XCTAssertThrowsError(try value.validate(now:confirmedAt.addingTimeInterval(-2),manualDistanceStillConfirmed:true))
    }
    func testManualConfirmationNeverExtendsCameraFreshness() {
        let t=Date(timeIntervalSince1970:1_000_000)
        for source in [DistanceSource.depth,.calibratedCamera] {
            let value=DistanceReading(meters:0.5,uncertaintyMeters:0.001,source:source,timestamp:t)
            XCTAssertThrowsError(try value.validate(now:t.addingTimeInterval(1),maxAge:0.4,manualDistanceStillConfirmed:true))
        }
    }
    func testThresholdAcceptsLongConfirmedManualReadingButStillRejectsWrongTarget() throws {
        let t=Date(timeIntervalSince1970:1_000_000),now=Date(timeIntervalSince1970:1_000_100)
        let value=DistanceReading(meters:0.5,uncertaintyMeters:0.001,source:.manual,timestamp:t)
        var search=ThresholdSearch(nearMeters:0.5)
        XCTAssertThrowsError(try search.submit(correct:true,distance:value,now:now))
        for _ in 0..<ThresholdSearch.blockSize {
            try search.submit(correct:true,distance:value,now:now,manualDistanceStillConfirmed:true)
        }
        XCTAssertEqual(search.targetMeters,3,accuracy:0.0001)
        XCTAssertThrowsError(try search.submit(correct:true,distance:value,now:now,manualDistanceStillConfirmed:true))
    }
    func testTrialPreservesTrainingPatternParameters() throws {
        let trial=Trial(meridian:0,repeatIndex:-1,targetPower:2,correctSide:0,answer:0,
            distance:DistanceReading(meters:0.5,uncertaintyMeters:0.001,source:.manual),reactionSeconds:2,
            stimulusGapArcMinutes:6,stimulusDiameterDegrees:1)
        let restored=try JSONDecoder().decode(Trial.self,from:JSONEncoder().encode(trial))
        XCTAssertEqual(restored.stimulusGapArcMinutes,6)
        XCTAssertEqual(restored.stimulusDiameterDegrees,1)
    }
    func testDisplayFingerprintDetectsPanelWindowAndScaleChanges() {
        let outer = DisplayContext(displayID:"panel-A",widthPoints:400,heightPoints:700,scale:3,nativeWidthPixels:1200,nativeHeightPixels:2100)
        let inner = DisplayContext(displayID:"panel-B",widthPoints:700,heightPoints:600,scale:3,nativeWidthPixels:2100,nativeHeightPixels:1800)
        let rotation = DisplayContext(displayID:"panel-A",widthPoints:700,heightPoints:400,scale:3,nativeWidthPixels:1200,nativeHeightPixels:2100)
        let scale = DisplayContext(displayID:"panel-A",widthPoints:400,heightPoints:700,scale:2,nativeWidthPixels:1200,nativeHeightPixels:2100)
        XCTAssertNotEqual(outer.signature,inner.signature)
        XCTAssertNotEqual(outer.signature,rotation.signature)
        XCTAssertNotEqual(outer.signature,scale.signature)
        XCTAssertEqual(outer.signature,outer.signature)
    }
    func testDisplayAuditKeyIgnoresEphemeralIdentityButRetainsPanelGeometry() throws {
        let a = DisplayContext(displayID:"object1",widthPoints:400,heightPoints:700,scale:3,nativeWidthPixels:1200,nativeHeightPixels:2100)
        let b = DisplayContext(displayID:"object2",widthPoints:400,heightPoints:700,scale:3,nativeWidthPixels:1200,nativeHeightPixels:2100)
        XCTAssertEqual(a.auditKey,b.auditKey)
        XCTAssertNotEqual(a.signature,b.signature)
        let decoded = try JSONDecoder().decode(DisplayContext.self,from:JSONEncoder().encode(a))
        XCTAssertEqual(decoded,a)
    }
    func testIncompleteDisplayGeometryIsNotUsable() {
        XCTAssertFalse(DisplayContext(displayID:"a",widthPoints:0,heightPoints:700,scale:3,nativeWidthPixels:1200,nativeHeightPixels:2100).isUsable)
        XCTAssertFalse(DisplayContext(displayID:"a",widthPoints:.nan,heightPoints:700,scale:3,nativeWidthPixels:1200,nativeHeightPixels:2100).isUsable)
    }
    func testPhysicalPostureAloneDoesNotChangeCalibrationSignature() {
        let a=DisplayContext(displayID:"same",widthPoints:400,heightPoints:700,scale:3,nativeWidthPixels:1200,nativeHeightPixels:2100,physicalOrientation:1)
        let b=DisplayContext(displayID:"same",widthPoints:400,heightPoints:700,scale:3,nativeWidthPixels:1200,nativeHeightPixels:2100,physicalOrientation:3)
        XCTAssertEqual(a.signature,b.signature)
    }
    private func thresholds(_ vector: PowerVector, noise: Double = 0) -> [MeridianThreshold] {
        (0..<2).flatMap { repeatIndex in
            [0.0,30,60,90,120,150].map { angle in
                let power = vector.power(at: angle) + (repeatIndex == 0 ? noise : -noise)
                return MeridianThreshold(meridian: angle, repeatIndex: repeatIndex, power: power,
                                         uncertainty: 0.10, nearPassPower: -power + 0.04, farFailPower: -power - 0.04)
            }
        }
    }
    func testKnownPrescriptionRecoveredAcrossAxisWrap() throws {
        for axis in [0.0, 1, 45, 90, 135, 179] {
            let expected = PowerVector(sphere: -2, cylinder: -1.25, axis: axis)
            let estimate = try RefractionFit.estimate(thresholds(expected))
            XCTAssertEqual(estimate.vector.sphere, -2, accuracy: 1e-8)
            XCTAssertEqual(estimate.vector.cylinder, -1.25, accuracy: 1e-8)
            XCTAssertLessThan(Optics.axialDifference(estimate.vector.axis, axis), 1e-7)
            XCTAssertEqual(estimate.clinicalValidation, "UNVALIDATED_RESEARCH_ONLY")
        }
    }
    func testPositiveCylinderTranspositionHasSameVector() {
        let negative = PowerVector(sphere: -2, cylinder: -1, axis: 20)
        let positive = PowerVector(sphere: -3, cylinder: 1, axis: 110)
        XCTAssertEqual(negative.m, positive.m, accuracy: 1e-8)
        XCTAssertEqual(negative.j0, positive.j0, accuracy: 1e-8)
        XCTAssertEqual(negative.j45, positive.j45, accuracy: 1e-8)
    }
    func testSmallCylinderDoesNotReportUnstableAxis() throws {
        let fit = try RefractionFit.estimate(thresholds(PowerVector(sphere: -2, cylinder: -0.1, axis: 90)))
        XCTAssertFalse(fit.axisReportable)
    }
    func testNoiseAndCommonCalibrationErrorNotDividedBySampleCount() throws {
        let fit = try RefractionFit.estimate(thresholds(PowerVector(sphere: -2, cylinder: -1, axis: 45), noise: 0.1))
        XCTAssertGreaterThanOrEqual(fit.instrumentStandardError, 0.10)
    }
    func testMissingRepeatRejected() {
        let data = Array(thresholds(PowerVector(sphere: -2, cylinder: -1, axis: 45)).prefix(6))
        XCTAssertThrowsError(try RefractionFit.estimate(data))
    }
    func testBadRepeatabilityRejected() {
        let data = thresholds(PowerVector(sphere: -2, cylinder: -1, axis: 45), noise: 0.35)
        XCTAssertThrowsError(try RefractionFit.estimate(data))
    }
    func testIrregularMeridionalDataRejected() {
        let data = (0..<2).flatMap { repetition in
            [0.0,30,60,90,120,150].enumerated().map { index, angle in
                let power = index.isMultiple(of: 2) ? -1.5 : -3.5
                return MeridianThreshold(meridian: angle, repeatIndex: repetition, power: power,
                                         uncertainty: 0.1, nearPassPower: -power+0.04, farFailPower: -power-0.04)
            }
        }
        XCTAssertThrowsError(try RefractionFit.estimate(data))
    }
    func testRangeCensoredResultRejected() {
        XCTAssertThrowsError(try RefractionFit.estimate(thresholds(PowerVector(sphere: 0.1, cylinder: -2, axis: 90))))
    }
    func testThresholdSearchFindsSimulatedBoundaryWithoutUsingPrescription() throws {
        var search = ThresholdSearch()
        while !search.finished {
            let distance = DistanceReading(meters: search.targetMeters, uncertaintyMeters: 0.001, source: .manual)
            // Ideal test observer: passes on the near side of a -2D far point.
            try search.submit(correct: search.targetPower >= 2, distance: distance)
        }
        let result = try search.result(meridian: 0, repeatIndex: 0)
        XCTAssertEqual(result.power, -2, accuracy: 0.063)
        XCTAssertGreaterThan(result.nearPassPower, 2)
        XCTAssertLessThan(result.farFailPower, 2)
    }
    func testAlwaysSeeingDoesNotBecomeZeroDioptres() throws {
        var search = ThresholdSearch()
        while !search.finished {
            try search.submit(correct: true, distance: DistanceReading(meters: search.targetMeters, uncertaintyMeters: 0.001, source: .manual))
        }
        XCTAssertEqual(search.phase, .failed)
        XCTAssertThrowsError(try search.result(meridian: 0, repeatIndex: 0))
    }
    func testAlwaysFailingDoesNotBecomeHighMyopia() throws {
        var search = ThresholdSearch()
        for _ in 0..<(2 * ThresholdSearch.blockSize) { try search.submit(correct: false, distance: DistanceReading(meters: 0.2, uncertaintyMeters: 0.001, source: .manual)) }
        XCTAssertEqual(search.phase, .failed)
    }
    func testLuckyFarEndpointRequiresConfirmation() throws {
        var search = ThresholdSearch()
        for _ in 0..<ThresholdSearch.blockSize {
            try search.submit(correct: true, distance: DistanceReading(meters: search.targetMeters, uncertaintyMeters: 0.001, source: .manual))
        }
        for _ in 0..<ThresholdSearch.blockSize {
            try search.submit(correct: true, distance: DistanceReading(meters: search.targetMeters, uncertaintyMeters: 0.001, source: .manual))
        }
        XCTAssertEqual(search.phase, .farEndpoint)
        for _ in 0..<ThresholdSearch.blockSize {
            try search.submit(correct: false, distance: DistanceReading(meters: search.targetMeters, uncertaintyMeters: 0.001, source: .manual))
        }
        XCTAssertEqual(search.phase, .bisect)
    }
    func testWrongDistanceAndExpiredReadingRejected() {
        var search = ThresholdSearch()
        XCTAssertThrowsError(try search.submit(correct: true, distance: DistanceReading(meters: 0.5, uncertaintyMeters: 0.001, source: .manual)))
        XCTAssertThrowsError(try DistanceReading(meters: 0.5, uncertaintyMeters: 0.005, source: .manual, timestamp: Date().addingTimeInterval(-31)).validate())
        XCTAssertThrowsError(try DistanceReading(meters: .nan, uncertaintyMeters: 0.005, source: .manual).validate())
        XCTAssertThrowsError(try DistanceReading(meters: 0.2, uncertaintyMeters: 0.01, source: .manual).validate())
    }
    func testCameraNeedsSecondDistanceAndRejectsWrongScale() {
        XCTAssertThrowsError(try CameraCalibration(referenceScale: 0.4, referenceMeters: 0.4, referenceUncertainty: 0.002,
            referenceRoll: 0, referenceYaw: 0, referencePitch: 0, verificationScale: 0.4, verificationMeters: 1, cameraSignature: "a"))
    }
    func testCalibratedCameraPoseFreshnessRangeAndDeviceChecks() throws {
        let calibration = try CameraCalibration(referenceScale: 0.4, referenceMeters: 0.4, referenceUncertainty: 0.002,
            referenceRoll: 0, referenceYaw: 0, referencePitch: 0, verificationScale: 0.16, verificationMeters: 1, cameraSignature: "a")
        let good = try calibration.reading(scale: 0.2, roll: 0, yaw: 0, pitch: 0, relativeJitter: 0.001, cameraSignature: "a")
        XCTAssertEqual(good.meters, 0.8, accuracy: 1e-8)
        XCTAssertThrowsError(try calibration.reading(scale: 0.2, roll: 0, yaw: 0.3, pitch: 0, relativeJitter: 0, cameraSignature: "a"))
        XCTAssertThrowsError(try calibration.reading(scale: 0.2, roll: 0, yaw: 0, pitch: 0, relativeJitter: 0, cameraSignature: "b"))
        XCTAssertThrowsError(try calibration.reading(scale: 0.1, roll: 0, yaw: 0, pitch: 0, relativeJitter: 0, cameraSignature: "a"))
        XCTAssertThrowsError(try calibration.reading(scale: 0.2, roll: 0, yaw: 0, pitch: 0, relativeJitter: 0, cameraSignature: "a", now: Date().addingTimeInterval(1801)))
    }
    func testAngularScalingAndStripeMeridianMapping() {
        let a = Optics.stripeWidthPoints(distance: 0.5, gapArcMinutes: 1, pointsPerMillimeter: 4)
        let b = Optics.stripeWidthPoints(distance: 1, gapArcMinutes: 1, pointsPerMillimeter: 4)
        XCTAssertEqual(b, 2*a, accuracy: 1e-10)
        XCTAssertEqual(Optics.stripeAngle(forMeridian: 0), 90)
        XCTAssertEqual(Optics.stripeAngle(forMeridian: 90), 0)
        XCTAssertEqual(Optics.axialDifference(179, 1), 2)
    }
    func testJSONRoundTripRetainsRawSourceAndUnits() throws {
        var session = SessionRecord(participantID: "P001", eye: .right, device: "test", screenPointsPerMillimeter: 4,
                                    gapArcMinutes: 1, consentAcknowledged: true, distanceCalibrationNotes: "manual")
        session.trials.append(Trial(meridian: 0, repeatIndex: 0, targetPower: 2, correctSide: 1, answer: 0,
            distance: DistanceReading(meters: 0.5, uncertaintyMeters: 0.005, source: .manual), reactionSeconds: 1))
        let restored = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored.trials.count, 1)
        XCTAssertFalse(restored.trials[0].correct)
        XCTAssertEqual(restored.trials[0].distance.source, .manual)
        XCTAssertNil(restored.estimate)
    }
}
