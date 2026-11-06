import Foundation

extension ArabicLinter {
    /// إصلاح آمن داخل ملف منسّق (وورد): الإملاء والترقيم والمسافات والإيموجي،
    /// بدون تغيير بنية الأسطر، فيبقى التنسيق كما هو.
    /// يرجع عدد الإصلاحات.
    @discardableResult
    public static func fixPreservingFormat(_ s: NSMutableAttributedString) -> Int {
        var rules: [(String, String)] = [
            (emoji, ""),
            ("(?<=[\(AR)])[ \\t]*,[ \\t]*", "، "),
            ("(?<=[\(AR)])[ \\t]*;[ \\t]*", "؛ "),
            ("(?<=[\(AR)])[ \\t]*\\?", "؟"),
            ("[ \\t]+([،؛؟!])", "$1"),
            ("([،؛])(?=[\(AR)A-Za-z0-9])", "$1 "),
            ("\(B)و[ \\t]+(?=[\(AR)])", "و"),
            ("([!؟])\\1+", "$1"),
        ]
        for (wrong, right) in Lexicon.spelling.sorted(by: { $0.key.count > $1.key.count }) {
            let w = RX.escape(wrong).replacingOccurrences(of: " ", with: "[ \\t]+")
            rules.append(("\(B)(\(PRE))\(w)\(E)", "$1" + NSRegularExpression.escapedTemplate(for: right)))
        }
        rules.append(("(?<=\\S)[ \\t]{2,}(?=\\S)", " "))

        var count = 0
        let ms = s.mutableString
        for (pat, tpl) in rules {
            count += RX.make(pat).replaceMatches(in: ms, range: NSRange(location: 0, length: ms.length), withTemplate: tpl)
        }
        return count
    }
}
