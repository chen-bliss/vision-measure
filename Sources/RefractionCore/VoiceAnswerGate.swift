import Foundation

/// One answer per displayed trial, independent of transcript offsets or repeated words.
/// The audio owner starts a fresh task whenever a trial becomes answerable.
public struct VoiceAnswerGate {
    public private(set) var taskToken = 0
    private var trialID: UUID?
    private var ready = false
    private var answered = false
    private var stopped = false

    public init() {}

    /// Returns true when previously captured audio must be discarded before listening for answers.
    @discardableResult public mutating func update(trialID: UUID, ready: Bool) -> Bool {
        let changed = self.trialID != trialID
        if changed { self.trialID = trialID; answered = false }
        let freshAudio = ready && (changed || !self.ready)
        self.ready = ready
        return freshAudio
    }

    @discardableResult public mutating func beginTask() -> Int {
        taskToken += 1
        return taskToken
    }

    /// An expired distance can reject an answer after recognition. Re-arm only with fresh audio.
    public mutating func rejectAnswer() { answered = false; ready = false }

    public mutating func consume(_ text: String, taskToken: Int) -> Int? {
        guard taskToken == self.taskToken, !stopped,
              let regex = try? NSRegularExpression(pattern: "左边|右边|停止") else { return nil }
        let words = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
        // Stop remains available while distance/exposure gates are closed.
        if words.contains("停止") { stopped = true; return -1 }
        guard ready, !answered, let word = words.last else { return nil }
        answered = true
        return word == "左边" ? 0 : 1
    }
}
