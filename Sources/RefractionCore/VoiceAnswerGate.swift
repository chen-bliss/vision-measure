import Foundation

/// Spoken answer words for one interface language.
public struct VoiceVocabulary {
    public let left: [String]
    public let right: [String]
    public let stop: [String]
    private let regex: NSRegularExpression?

    /// Scripts written with spaces match whole words only, so "right" does not fire inside "alright".
    public init(left: [String], right: [String], stop: [String], wholeWords: Bool) {
        self.left = left; self.right = right; self.stop = stop
        let terms = (left + right + stop).map(Self.fold).sorted { $0.count > $1.count }
        let alternation = terms.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let pattern = wholeWords ? "(?<![\\p{L}\\p{M}])(?:\(alternation))(?![\\p{L}\\p{M}])" : alternation
        regex = try? NSRegularExpression(pattern: pattern)
    }

    public static let chinese = VoiceVocabulary(left: ["左边"], right: ["右边"], stop: ["停止"], wholeWords: false)

    public static func forLanguage(_ language: AppLanguage) -> VoiceVocabulary {
        switch language {
        case .chinese: return .chinese
        case .english: return VoiceVocabulary(left: ["left"], right: ["right"], stop: ["stop"], wholeWords: true)
        case .french: return VoiceVocabulary(left: ["gauche"], right: ["droite"], stop: ["stop", "arrête", "arrêtez", "arrêter"], wholeWords: true)
        case .spanish: return VoiceVocabulary(left: ["izquierda"], right: ["derecha"], stop: ["alto", "parar", "detener", "stop"], wholeWords: true)
        case .russian: return VoiceVocabulary(left: ["слева", "налево", "лево", "левый", "левая"],
                                              right: ["справа", "направо", "право", "правый", "правая"],
                                              stop: ["стоп", "остановить", "хватит"], wholeWords: true)
        case .arabic: return VoiceVocabulary(left: ["يسار", "اليسار", "لليسار"], right: ["يمين", "اليمين", "لليمين"],
                                             stop: ["توقف", "قف"], wholeWords: true)
        }
    }

    /// Hints passed to the recognizer.
    public var contextualStrings: [String] { left + right + stop }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Recognized command words in spoken order: 0 left, 1 right, -1 stop.
    func commands(in text: String) -> [Int] {
        guard let regex = regex else { return [] }
        let folded = Self.fold(text)
        let leftSet = Set(left.map(Self.fold)), stopSet = Set(stop.map(Self.fold))
        return regex.matches(in: folded, range: NSRange(folded.startIndex..., in: folded)).compactMap { match in
            guard let range = Range(match.range, in: folded) else { return nil }
            let word = String(folded[range])
            return stopSet.contains(word) ? -1 : (leftSet.contains(word) ? 0 : 1)
        }
    }
}

/// One answer per displayed trial, independent of transcript offsets or repeated words.
/// The audio owner starts a fresh task whenever a trial becomes answerable.
public struct VoiceAnswerGate {
    public private(set) var taskToken = 0
    public let vocabulary: VoiceVocabulary
    private var trialID: UUID?
    private var ready = false
    private var answered = false
    private var stopped = false

    public init(vocabulary: VoiceVocabulary = .chinese) { self.vocabulary = vocabulary }

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
        guard taskToken == self.taskToken, !stopped else { return nil }
        let words = vocabulary.commands(in: text)
        // Stop remains available while distance/exposure gates are closed.
        if words.contains(-1) { stopped = true; return -1 }
        guard ready, !answered, let word = words.last else { return nil }
        answered = true
        return word
    }
}
