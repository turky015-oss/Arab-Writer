import XCTest
@testable import ArabWriterCore

final class LinterTests: XCTestCase {
    func testMarkersAreBlocking() {
        let r = ArabicLinter.check("في عالم اليوم أصبحت التقنية مهمة.")
        XCTAssertTrue(r.errors.contains { $0.kind.hasPrefix("بصمة آلية") })
    }

    func testSpellingFix() {
        let out = ArabicLinter.fix("ذهبت الى المدرسه وهذة فكره جيدة.", englishOnOwnLine: false)
        XCTAssertTrue(out.contains("إلى"))
        XCTAssertTrue(out.contains("هذه"))
        XCTAssertTrue(out.contains("فكرة"))
    }

    func testPunctuationFix() {
        let out = ArabicLinter.fix("كيف حالك?", englishOnOwnLine: false)
        XCTAssertEqual(out, "كيف حالك؟")
    }

    func testEnglishOnOwnLine() {
        let out = ArabicLinter.fix("استخدمت Claude في العمل")
        XCTAssertEqual(out, "استخدمت\nClaude\nفي العمل")
        XCTAssertTrue(ArabicLinter.check(out).isClean)
    }

    func testFabrication() {
        let r = ArabicLinter.check("زاد الدخل 40%", options: LintOptions(source: "زاد الدخل"))
        XCTAssertTrue(r.errors.contains { $0.kind == "اختلاق" })
    }

    func testCleanText() {
        let r = ArabicLinter.check("حمّلت التطبيق أمس وجربته على جهازي.")
        XCTAssertTrue(r.isClean, "\(r.errors)")
    }

    func testDiff() {
        let d = TextDiff.compare("ذهبت الى البيت", "ذهبت إلى البيت")
        XCTAssertEqual(d.changes.count, 1)
        XCTAssertEqual(d.changes.first?.op, .replace)
    }

    func testLongInputs() {
        let en = (1...4000).map { "word\($0)" }.joined(separator: " ")
        _ = ArabicLinter.check("نص عربي \(en) نهاية")
        _ = ArabicLinter.fix("نص عربي \(en) نهاية")
        let ar = Array(repeating: "كلمة", count: 3000).joined(separator: " ")
        let d = TextDiff.compare(ar, ar + " أخرى")
        XCTAssertFalse(d.changes.isEmpty)
    }

    func testOddInputs() {
        for s in ["", " ", "\n\n", "؟؟؟", "!!!", "١٢٣", "a", "ـــ"] { _ = ArabicLinter.check(s); _ = ArabicLinter.fix(s) }
    }
}
