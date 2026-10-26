import Foundation
import RefractionCore

struct SeededGenerator {
    var state: UInt64 = 261025
    mutating func next() -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Double(state >> 11) / Double(UInt64.max >> 11)
    }
}
struct Summary: Codable {
    var label = "SYNTHETIC_MODEL_NOT_CLINICAL_EVIDENCE"
    var scenario: String
    var total: Int
    var completed: Int
    var failureReasons: [String: Int]
    var sphereMAE: Double?
    var cylinderMAE: Double?
    var mMAE: Double?
}
var rng = SeededGenerator()
let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Build/synthetic-benchmark", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
var sessions: [SessionRecord] = []
var references = ["session_id,participant_id,eye,ref_sphere,ref_cylinder,ref_axis,reference_method,examiner_masked,same_day,cohort,synthetic"]
var summaries: [Summary] = []
for scenario in ["ideal", "psychometric_noise", "systematic_accommodation_bias"] {
    var errors: [(Double,Double,Double)] = []
    var reasons: [String:Int] = [:]
    for index in 0..<40 {
        // Ground truth is specified independently of the refraction solver.
        let sphere = -0.75 - rng.next() * 2.25
        let cylinder = -0.5 - rng.next()
        let axis = rng.next() * 180
        let shift = scenario == "systematic_accommodation_bias" ? 0.65 : 0.0
        var record = SessionRecord(participantID: "SYNTHETIC_\(scenario)_\(index)", eye: .right,
            device: "SYNTHETIC_OBSERVER", screenPointsPerMillimeter: 4, gapArcMinutes: 1,
            consentAcknowledged: false, distanceCalibrationNotes: "simulated exact distances")
        record.sessionKind = "SYNTHETIC_MODEL"
        var failure: String?
        outer: for repeatIndex in 0..<2 {
            for meridian in [0.0,30,60,90,120,150] {
                var search = ThresholdSearch()
                let expectedPower = sphere + cylinder * pow(sin((meridian-axis) * .pi/180),2)
                while !search.finished {
                    let q = search.targetPower
                    let correct: Bool
                    if scenario == "ideal" { correct = q >= -expectedPower }
                    else {
                        // Explicit assumed observer, NOT fitted to human data.
                        let probability = 0.5 + 0.5 / (1 + exp(-(q + expectedPower - shift) / 0.05))
                        correct = rng.next() < probability
                    }
                    let d = DistanceReading(meters: search.targetMeters, uncertaintyMeters: 0.001, source: .manual)
                    let truth = rng.next() < 0.5 ? 0 : 1
                    let answer = correct ? truth : 1-truth
                    record.trials.append(Trial(meridian: meridian, repeatIndex: repeatIndex, targetPower: q,
                                              correctSide: truth, answer: answer, distance: d, reactionSeconds: 1))
                    try search.submit(correct: correct, distance: d)
                }
                do { record.thresholds.append(try search.result(meridian: meridian, repeatIndex: repeatIndex)) }
                catch { failure = error.localizedDescription; break outer }
            }
        }
        if failure == nil {
            do {
                let estimate = try RefractionFit.estimate(record.thresholds)
                record.estimate = estimate
                errors.append((abs(estimate.vector.sphere-sphere),abs(estimate.vector.cylinder-cylinder),
                               abs(estimate.vector.m-(sphere+cylinder/2))))
            } catch { failure = error.localizedDescription }
        }
        if let failure = failure { reasons[failure,default:0] += 1 }
        record.stopReason = failure; record.finishedAt = Date(); sessions.append(record)
        references.append("\(record.id.uuidString),\(record.participantID),R,\(sphere),\(cylinder),\(axis),subjective,1,1,validation,1")
    }
    func mean(_ index: Int) -> Double? {
        guard !errors.isEmpty else { return nil }
        return errors.map { index == 0 ? $0.0 : index == 1 ? $0.1 : $0.2 }.reduce(0,+) / Double(errors.count)
    }
    summaries.append(Summary(scenario: scenario, total: 40, completed: errors.count, failureReasons: reasons,
                             sphereMAE: mean(0), cylinderMAE: mean(1), mMAE: mean(2)))
}
let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(sessions).write(to: directory.appendingPathComponent("SYNTHETIC-sessions.json"))
try encoder.encode(summaries).write(to: directory.appendingPathComponent("summary.json"))
try references.joined(separator: "\n").write(to: directory.appendingPathComponent("SYNTHETIC-references.csv"), atomically: true, encoding: .utf8)
print(String(data: try encoder.encode(summaries), encoding: .utf8)!)
