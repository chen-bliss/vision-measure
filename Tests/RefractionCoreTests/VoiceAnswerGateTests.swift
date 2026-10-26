import XCTest
@testable import RefractionCore

final class VoiceAnswerGateTests: XCTestCase {
    func testIdenticalAnswersAcrossEightTrials() {
        var gate = VoiceAnswerGate()
        for _ in 0..<8 {
            let id = UUID()
            XCTAssertFalse(gate.update(trialID:id, ready:false))
            XCTAssertTrue(gate.update(trialID:id, ready:true))
            let token = gate.beginTask()
            // Each fresh recognizer can report exactly the same text at offset zero.
            XCTAssertEqual(gate.consume("左边", taskToken:token), 0)
            XCTAssertNil(gate.consume("左边", taskToken:token))
        }
    }
    func testAlternatingAnswersAcrossEightTrials() {
        var gate = VoiceAnswerGate()
        for index in 0..<8 {
            XCTAssertTrue(gate.update(trialID:UUID(), ready:true))
            let token = gate.beginTask()
            XCTAssertEqual(gate.consume(index % 2 == 0 ? "左边" : "右边", taskToken:token), index % 2)
        }
    }
    func testPartialAndFinalCannotAnswerNextTrial() {
        var gate = VoiceAnswerGate()
        gate.update(trialID:UUID(), ready:true)
        let old = gate.beginTask()
        XCTAssertEqual(gate.consume("右边", taskToken:old), 1)
        let next = UUID()
        gate.update(trialID:next, ready:false)
        XCTAssertNil(gate.consume("右边", taskToken:old))
        XCTAssertTrue(gate.update(trialID:next, ready:true))
        let current = gate.beginTask()
        XCTAssertNil(gate.consume("右边", taskToken:old))
        XCTAssertEqual(gate.consume("右边", taskToken:current), 1)
    }
    func testAnswerDuringSettlingIsNotReplayed() {
        var gate = VoiceAnswerGate()
        let id = UUID()
        gate.update(trialID:id, ready:false)
        let settling = gate.beginTask()
        XCTAssertNil(gate.consume("左边", taskToken:settling))
        XCTAssertTrue(gate.update(trialID:id, ready:true))
        let listening = gate.beginTask()
        XCTAssertNil(gate.consume("左边", taskToken:settling))
        XCTAssertEqual(gate.consume("右边", taskToken:listening), 1)
    }
    func testFinalOrErrorRestartDoesNotUnlockAnsweredTrial() {
        var gate = VoiceAnswerGate()
        gate.update(trialID:UUID(), ready:true)
        let initial = gate.beginTask()
        XCTAssertEqual(gate.consume("左边", taskToken:initial), 0)
        let recovered = gate.beginTask()
        XCTAssertNil(gate.consume("左边右边", taskToken:recovered))
    }
    func testRecoveryBeforeAnswerAllowsFreshCommand() {
        var gate = VoiceAnswerGate()
        gate.update(trialID:UUID(), ready:true)
        let failed = gate.beginTask()
        let recovered = gate.beginTask()
        XCTAssertNil(gate.consume("左边", taskToken:failed))
        XCTAssertEqual(gate.consume("右边", taskToken:recovered), 1)
    }
    func testStopAvailableWhileWaitingAndAfterAnswer() {
        for ready in [false, true] {
            var gate = VoiceAnswerGate()
            gate.update(trialID:UUID(), ready:ready)
            let token = gate.beginTask()
            _ = gate.consume("左边", taskToken:token)
            XCTAssertEqual(gate.consume("停止", taskToken:token), -1)
            XCTAssertNil(gate.consume("停止", taskToken:token))
        }
    }
    func testRejectedAnswerCanBeRetriedAfterDistanceRestored() {
        var gate = VoiceAnswerGate()
        let id = UUID()
        gate.update(trialID:id, ready:true)
        let first = gate.beginTask()
        XCTAssertEqual(gate.consume("左边", taskToken:first), 0)
        gate.rejectAnswer()
        XCTAssertTrue(gate.update(trialID:id, ready:true))
        let retry = gate.beginTask()
        XCTAssertNil(gate.consume("左边", taskToken:first))
        XCTAssertEqual(gate.consume("左边", taskToken:retry), 0)
    }
    func testUnrelatedSpeechAndStableReadinessDoNotResetTrial() {
        var gate = VoiceAnswerGate()
        let id = UUID()
        XCTAssertTrue(gate.update(trialID:id, ready:true))
        let token = gate.beginTask()
        XCTAssertNil(gate.consume("我在看图案", taskToken:token))
        XCTAssertFalse(gate.update(trialID:id, ready:true))
        XCTAssertEqual(gate.consume("我觉得是右边", taskToken:token), 1)
        XCTAssertFalse(gate.update(trialID:id, ready:true))
        XCTAssertNil(gate.consume("左边", taskToken:token))
    }
}
