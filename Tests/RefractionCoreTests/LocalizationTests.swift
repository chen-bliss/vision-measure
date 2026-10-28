import XCTest
@testable import RefractionCore

final class LocalizationTests: XCTestCase {
    func testResolvesSystemPreferencesToUNLanguages() {
        XCTAssertEqual(AppLanguage.resolve(["zh-Hant-TW"]), .chinese)
        XCTAssertEqual(AppLanguage.resolve(["zh_CN"]), .chinese)
        XCTAssertEqual(AppLanguage.resolve(["fr-CA", "en-US"]), .french)
        XCTAssertEqual(AppLanguage.resolve(["es-419"]), .spanish)
        XCTAssertEqual(AppLanguage.resolve(["ru-RU"]), .russian)
        XCTAssertEqual(AppLanguage.resolve(["ar-EG"]), .arabic)
        XCTAssertEqual(AppLanguage.resolve(["de-DE", "ru"]), .russian)
        XCTAssertEqual(AppLanguage.resolve(["de-DE", "ja-JP"]), .english)
        XCTAssertEqual(AppLanguage.resolve([]), .english)
    }
    func testOnlyArabicIsRightToLeft() {
        XCTAssertEqual(AppLanguage.allCases.filter(\.isRightToLeft), [.arabic])
        XCTAssertEqual(AppLanguage.allCases.count, 6)
    }
    func testMissingTranslationFallsBackToSourceAndFormats() {
        XCTAssertEqual(Localizer.string("没有这个键"), "没有这个键")
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.preferenceKey)
        defer { UserDefaults.standard.removeObject(forKey: AppLanguage.preferenceKey) }
        XCTAssertEqual(AppLanguage.current, .english)
        XCTAssertEqual(L("练习 %ld/8", 3), "练习 3/8")
    }
    func testNumberInputAcceptsLocalizedKeyboards() {
        XCTAssertEqual(NumberInput.parse("6.5"), 6.5)
        XCTAssertEqual(NumberInput.parse(" 6,5 "), 6.5)
        XCTAssertEqual(NumberInput.parse("٦٫٥"), 6.5)
        XCTAssertEqual(NumberInput.parse("۱۲"), 12)
        XCTAssertEqual(NumberInput.parse("１２０"), 120)
        XCTAssertEqual(NumberInput.parse("−3"), -3)
        XCTAssertNil(NumberInput.parse("abc"))
        XCTAssertNil(NumberInput.parse(""))
        XCTAssertNil(NumberInput.parse("inf"))
    }
    func testVoiceCommandsForEveryLanguage() {
        let samples: [(AppLanguage, String, String, String)] = [
            (.chinese, "我觉得是左边", "右边", "停止"),
            (.english, "Left", "it is on the right", "stop please"),
            (.french, "à gauche", "Droite", "arrête"),
            (.spanish, "izquierda", "a la derecha", "alto"),
            (.russian, "слева", "Направо", "стоп"),
            (.arabic, "على اليسار", "يمين", "توقف"),
        ]
        for (language, left, right, stop) in samples {
            let vocabulary = VoiceVocabulary.forLanguage(language)
            XCTAssertEqual(vocabulary.commands(in: left), [0], "\(language) left")
            XCTAssertEqual(vocabulary.commands(in: right), [1], "\(language) right")
            XCTAssertEqual(vocabulary.commands(in: stop), [-1], "\(language) stop")
        }
    }
    func testWholeWordLanguagesIgnoreEmbeddedWords() {
        let english = VoiceVocabulary.forLanguage(.english)
        XCTAssertEqual(english.commands(in: "alright, bright, leftover"), [])
        XCTAssertEqual(english.commands(in: "left no right"), [0, 1])
        XCTAssertEqual(VoiceVocabulary.forLanguage(.arabic).commands(in: "موقف"), [])
    }
    func testGateUsesLanguageVocabulary() {
        var gate = VoiceAnswerGate(vocabulary: .forLanguage(.french))
        gate.update(trialID: UUID(), ready: true)
        let token = gate.beginTask()
        XCTAssertNil(gate.consume("左边", taskToken: token))
        XCTAssertEqual(gate.consume("gauche", taskToken: token), 0)
        XCTAssertEqual(gate.consume("stop", taskToken: token), -1)
    }
    func testEyeRawValuesStayStableForExportedRecords() throws {
        XCTAssertEqual(Eye.right.rawValue, "右眼")
        XCTAssertEqual(Eye.left.rawValue, "左眼")
        let data = try JSONEncoder().encode([Eye.left])
        XCTAssertEqual(String(data: data, encoding: .utf8), "[\"左眼\"]")
    }
}
