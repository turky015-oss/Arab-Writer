import Foundation

// MARK: - النتائج

public enum IssueLevel: String, Codable, Sendable {
    case error = "خطأ"
    case warning = "تنبيه"
}

public struct LintIssue: Identifiable, Codable, Sendable, Hashable {
    public var id = UUID()
    public let level: IssueLevel
    public let kind: String
    public let message: String
    public var line: Int?
    public var excerpt: String?
    public var fix: String?
}

public struct TextStats: Codable, Sendable, Equatable {
    public var words = 0
    public var sentences = 0
    public var averageSentence = 0.0
    public var lines = 0
    public init() {}
}

public struct LintReport: Sendable {
    public var issues: [LintIssue] = []
    public var stats = TextStats()
    public init() {}
    public var errors: [LintIssue] { issues.filter { $0.level == .error } }
    public var warnings: [LintIssue] { issues.filter { $0.level == .warning } }
    public var isClean: Bool { errors.isEmpty }
}

public struct LintOptions: Sendable {
    public var wordsTarget: Int?
    public var linesTarget: Int?
    public var source: String?
    public var englishOnOwnLine = true
    public init(wordsTarget: Int? = nil, linesTarget: Int? = nil, source: String? = nil, englishOnOwnLine: Bool = true) {
        self.wordsTarget = wordsTarget
        self.linesTarget = linesTarget
        self.source = source
        self.englishOnOwnLine = englishOnOwnLine
    }
}

// MARK: - أدوات الأنماط

enum RX {
    nonisolated(unsafe) static var cache: [String: NSRegularExpression] = [:]
    static let lock = NSLock()

    static func make(_ pattern: String, _ opts: NSRegularExpression.Options = []) -> NSRegularExpression {
        let key = "\(opts.rawValue)|\(pattern)"
        lock.lock(); defer { lock.unlock() }
        if let r = cache[key] { return r }
        // لو فشل نمط لأي سبب، نرجع نمطاً لا يطابق شيئاً بدل إغلاق البرنامج.
        let r = (try? NSRegularExpression(pattern: pattern, options: opts)) ?? (try! NSRegularExpression(pattern: "(?!)"))
        cache[key] = r
        return r
    }

    static func matches(_ pattern: String, in s: String, _ opts: NSRegularExpression.Options = []) -> [NSTextCheckingResult] {
        make(pattern, opts).matches(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }

    static func test(_ pattern: String, _ s: String) -> Bool {
        make(pattern).firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    static func replace(_ pattern: String, in s: String, with tpl: String, _ opts: NSRegularExpression.Options = []) -> String {
        make(pattern, opts).stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: tpl)
    }

    static func escape(_ s: String) -> String { NSRegularExpression.escapedPattern(for: s) }
}

extension String {
    func sub(_ r: NSRange) -> String { (self as NSString).substring(with: r) }
    func group(_ m: NSTextCheckingResult, _ i: Int) -> String {
        let r = m.range(at: i)
        return r.location == NSNotFound ? "" : (self as NSString).substring(with: r)
    }
}

// MARK: - الفاحص

public enum ArabicLinter {
    static let AR = Lexicon.ar
    static var B: String { "(?<![\(AR)\\w])" }
    static var E: String { "(?![\(AR)\\w])" }
    static let PRE = "[وف]?(?:بال|كال|لل|ال|[بكل])?"
    static let emoji = "[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{1F000}-\u{1F2FF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}✅❌✔✖]"
    static let dash = "[—–‒―]|--"
    static let enChunk = "[A-Za-z][A-Za-z0-9.+#'&/-]*(?:\\s+[A-Za-z0-9.+#'&/-]+)*"

    public static func stripDiacritics(_ s: String) -> String {
        RX.replace("[\u{064B}-\u{0652}\u{0670}\u{0640}]", in: s, with: "")
    }

    static func fold(_ s: String) -> String {
        s.replacingOccurrences(of: "أ", with: "ا")
            .replacingOccurrences(of: "إ", with: "ا")
            .replacingOccurrences(of: "آ", with: "ا")
    }

    public static func words(_ s: String) -> [String] {
        RX.matches("[\(AR)A-Za-z0-9\u{0660}-\u{0669}]+", in: s).map { s.sub($0.range) }
    }

    public static func sentences(_ s: String) -> [String] {
        // تقسيم عند علامة النهاية متبوعة بمسافة، أو عند السطر الجديد
        let marked = RX.replace("([.!؟?])\\s+", in: s, with: "$1\u{0001}")
        return marked.components(separatedBy: CharacterSet(charactersIn: "\u{0001}\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !words($0).isEmpty }
    }

    static func lineOf(_ text: String, _ loc: Int) -> Int {
        let ns = text as NSString
        let pre = ns.substring(to: min(loc, ns.length))
        return pre.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }

    static func excerpt(_ text: String, _ r: NSRange, pad: Int = 18) -> String {
        let ns = text as NSString
        let a = max(0, r.location - pad)
        let b = min(ns.length, r.location + r.length + pad)
        return ns.substring(with: NSRange(location: a, length: b - a))
            .replacingOccurrences(of: "\n", with: " ⏎ ")
            .trimmingCharacters(in: .whitespaces)
    }

    public static func stats(_ text: String) -> TextStats {
        var st = TextStats()
        let sents = sentences(text)
        let lens = sents.map { words($0).count }
        st.words = words(text).count
        st.sentences = sents.count
        st.averageSentence = lens.isEmpty ? 0 : (Double(lens.reduce(0, +)) / Double(lens.count) * 10).rounded() / 10
        st.lines = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        return st
    }

    // MARK: check

    public static func check(_ text: String, options: LintOptions = LintOptions()) -> LintReport {
        var issues: [LintIssue] = []
        let norm = stripDiacritics(text)
        let folded = fold(norm)

        func add(_ level: IssueLevel, _ kind: String, _ msg: String, in t: String? = nil, _ r: NSRange? = nil, fix: String? = nil) {
            var it = LintIssue(level: level, kind: kind, message: msg, fix: fix)
            if let t, let r {
                it.line = lineOf(t, r.location)
                it.excerpt = excerpt(t, r)
            }
            issues.append(it)
        }

        // 1. البصمات
        for (kind, phrases) in Lexicon.markers {
            for ph in phrases {
                let f = fold(stripDiacritics(ph))
                let p = RX.escape(f).replacingOccurrences(of: " ", with: "\\s+")
                for m in RX.matches("(?<![\(AR)\\w])(?:[وفب])?\(p)", in: folded) {
                    add(.error, "بصمة آلية: \(kind)", "«\(ph)»", in: norm, m.range,
                        fix: "احذفها أو ضع مكانها الحقيقة المحددة")
                }
            }
        }
        for adv in Lexicon.softAdverbs {
            for m in RX.matches("\(B)\(adv)\(E)", in: folded) {
                add(.warning, "ظرف حشو", "«\(adv)»", in: norm, m.range, fix: "احذفه إلا إذا حمل معنى")
            }
        }

        // 2. الإملاء
        for (wrong, right) in Lexicon.spelling {
            let w = RX.escape(stripDiacritics(wrong)).replacingOccurrences(of: " ", with: "\\s+")
            for m in RX.matches("\(B)(\(PRE))(\(w))\(E)", in: norm) {
                let pre = norm.group(m, 1)
                add(.error, "إملاء", "«\(norm.sub(m.range))» ← «\(pre)\(right)»", in: norm, m.range, fix: pre + right)
            }
        }

        // 3. النحو
        for (pat, sug, why) in Lexicon.grammar {
            for m in RX.matches(pat, in: norm) {
                add(.warning, "نحو", "«\(norm.sub(m.range))»: \(why)" + (sug.map { " ← «\($0)»" } ?? ""), in: norm, m.range)
            }
        }

        // 4. الترقيم والمسافات
        for m in RX.matches("(?<=[\(AR)])\\s*,\\s*(?=[\(AR)])", in: text) {
            add(.error, "ترقيم", "فاصلة إنجليزية بين كلمات عربية ← «،»", in: text, m.range, fix: "،")
        }
        for m in RX.matches("(?<=[\(AR)])\\s*;\\s*", in: text) {
            add(.error, "ترقيم", "فاصلة منقوطة إنجليزية ← «؛»", in: text, m.range, fix: "؛")
        }
        for m in RX.matches("(?<=[\(AR)])\\s*\\?", in: text) {
            add(.error, "ترقيم", "علامة استفهام إنجليزية ← «؟»", in: text, m.range, fix: "؟")
        }
        for m in RX.matches("[ \\t]+([،؛؟.!:,])", in: text) {
            if text.group(m, 1) == ":" {
                let before = (text as NSString).substring(to: m.range.location)
                if RX.test("\\d\\s*$", before) { continue }
            }
            add(.error, "مسافات", "مسافة قبل علامة الترقيم", in: text, m.range)
        }
        for m in RX.matches("([،؛؟])(?=[\(AR)A-Za-z0-9])", in: text) {
            add(.error, "مسافات", "لا مسافة بعد علامة الترقيم", in: text, m.range)
        }
        for m in RX.matches("\(B)و\\s+(?=[\(AR)])", in: text) {
            add(.error, "مسافات", "واو العطف منفصلة ← تلتصق بما بعدها", in: text, m.range)
        }
        for m in RX.matches("[^\\S\\n]{2,}", in: text) {
            let before = (text as NSString).substring(to: m.range.location)
            if m.range.location == 0 || before.hasSuffix("\n") { continue }
            add(.error, "مسافات", "مسافة مزدوجة", in: text, m.range)
        }
        for m in RX.matches("([!؟?])\\1+|!؟|؟!", in: text) {
            add(.warning, "ترقيم", "علامات مكررة", in: text, m.range)
        }

        // 5. التنسيق
        for m in RX.matches(emoji, in: text) { add(.error, "تنسيق", "إيموجي", in: text, m.range) }
        for m in RX.matches(dash, in: text) { add(.error, "تنسيق", "شرطة طويلة", in: text, m.range) }
        for m in RX.matches("^\\s{0,3}#{1,6}\\s", in: text, .anchorsMatchLines) {
            add(.warning, "تنسيق", "ترويسة ماركداون (مقبولة في المستندات فقط)", in: text, m.range)
        }
        for m in RX.matches("\\*\\*[^*\\n]+\\*\\*|__[^_\\n]+__", in: text) {
            add(.warning, "تنسيق", "خط عريض", in: text, m.range)
        }
        for m in RX.matches("^\\s*(إليك|اليك|هذا هو|هذه هي|فيما يلي|في ما يلي|تفضل|بالتأكيد|بكل سرور|حسنا|طبعا)[^\\n]{0,40}[:：]?\\s*$", in: norm, .anchorsMatchLines) {
            add(.error, "تنسيق", "مقدمة عن النص بدل النص نفسه", in: norm, m.range)
        }
        let bullets = RX.matches("^\\s*([-*•●▪✓✅]|\\d+[.)])\\s+", in: text, .anchorsMatchLines).count
        if bullets >= 3 && sentences(text).count <= bullets + 2 {
            add(.warning, "بنية", "\(bullets) نقاط: إن كان النص سرداً فحوّلها إلى جمل متصلة")
        }

        // 6. الإنجليزية داخل السطر العربي
        if options.englishOnOwnLine {
            for (i, ln) in text.components(separatedBy: "\n").enumerated() {
                guard RX.test("[\(AR)]", ln), RX.test("[A-Za-z]", ln) else { continue }
                let trimmed = ln.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("http") || trimmed.hasPrefix("#") { continue }
                var seen: [String] = []
                for m in RX.matches(enChunk, in: ln) {
                    let w = ln.sub(m.range)
                    if !seen.contains(w) { seen.append(w) }
                }
                if !seen.isEmpty {
                    var it = LintIssue(level: .error, kind: "اتجاه",
                                       message: "كلمة إنجليزية داخل سطر عربي ← سطر مستقل: " + seen.joined(separator: "، "))
                    it.line = i + 1
                    issues.append(it)
                }
            }
        }

        // 7. البنى
        for m in RX.matches("ليس[ت]?\\s[^.،؟\\n]{1,40}[،,]?\\s*(بل|وإنما|إنما)\\s", in: norm) {
            add(.error, "بصمة آلية: بنية", "«ليس … بل …»: قل الثاني مباشرة", in: norm, m.range)
        }
        for m in RX.matches("([\(AR)]+)،\\s*([\(AR)]+)،\\s*و([\(AR)]+)", in: norm) {
            let parts = [1, 2, 3].map { (norm.group(m, $0) as NSString).length }
            if (parts.max() ?? 0) <= 8 {
                add(.warning, "بصمة آلية: ثلاثية", "«\(norm.sub(m.range))»: اثنتان أو حقيقة واحدة أصدق", in: norm, m.range)
            }
        }
        for m in RX.matches("([\(AR)]{2,})\\s+و([\(AR)]{2,})\\s+و([\(AR)]{2,})", in: norm) {
            add(.warning, "بصمة آلية: ثلاثية", "«\(norm.sub(m.range))»", in: norm, m.range)
        }
        for m in RX.matches("^[^\\n؟]{0,60}؟\\s*\\n?\\s*(لأن|الجواب|السبب)", in: norm, .anchorsMatchLines) {
            add(.error, "بصمة آلية: بنية", "سؤال بلاغي يتبعه جوابه: احذف السؤال", in: norm, m.range)
        }

        // 8. الإيقاع
        let lens = sentences(text).map { words($0).count }
        if lens.count >= 4 {
            for i in 0..<(lens.count - 2) {
                let trio = Array(lens[i..<(i + 3)])
                if trio.max()! - trio.min()! <= 2 && trio.min()! >= 4 {
                    add(.warning, "إيقاع", "ثلاث جمل متتالية بطول متقارب (\(trio[0])، \(trio[1])، \(trio[2]) كلمة): نوّع")
                    break
                }
            }
            let short = lens.filter { $0 <= 2 }.count
            if short >= 3 { add(.warning, "إيقاع", "\(short) جمل من كلمة أو كلمتين: تقطيع درامي، أعد الجمل لطولها") }
        }

        // 9. الطول
        let st = stats(text)
        if let t = options.wordsTarget {
            let lo = Int(Double(t) * 0.9), hi = Int((Double(t) * 1.1).rounded())
            if st.words < lo || st.words > hi {
                add(.error, "طول", "\(st.words) كلمة والمطلوب \(t) (المسموح \(lo) إلى \(hi))")
            }
        }
        if let t = options.linesTarget, st.lines != t {
            add(.error, "طول", "\(st.lines) سطر والمطلوب \(t)")
        }

        // 10. الاختلاق
        if let source = options.source {
            let src = stripDiacritics(source)
            let numPat = "\\d+(?:[.,،]\\d+)?"
            let srcNums = Set(RX.matches(numPat, in: src).map { src.sub($0.range) })
            var seen = Set<String>()
            for m in RX.matches(numPat, in: norm) {
                let n = norm.sub(m.range)
                if !srcNums.contains(n), seen.insert(n).inserted {
                    add(.error, "اختلاق", "الرقم \(n) غير موجود في الأصل: احذفه أو اسأل عنه")
                }
            }
            let capPat = "\\b[A-Z][A-Za-z0-9]+\\b"
            let srcCaps = Set(RX.matches(capPat, in: src).map { src.sub($0.range) })
            let caps = Set(RX.matches(capPat, in: norm).map { norm.sub($0.range) }).subtracting(srcCaps)
            for c in caps.sorted() { add(.error, "اختلاق", "الاسم \(c) غير موجود في الأصل") }
            let srcW = words(src).count
            if st.words > max(40, Int(Double(srcW) * 1.25)) {
                add(.warning, "طول", "النص أطول من الأصل بأكثر من 25% (\(st.words) مقابل \(srcW))")
            }
        }

        var report = LintReport()
        report.issues = issues
        report.stats = st
        return report
    }

    // MARK: fix

    public static func fix(_ text: String, englishOnOwnLine: Bool = true) -> String {
        var t = text
        t = RX.replace(emoji, in: t, with: "")
        t = RX.replace("\\s*[—–‒―]\\s*|\\s+--\\s+", in: t, with: "، ")
        t = RX.replace("\\*\\*([^*\\n]+)\\*\\*|__([^_\\n]+)__", in: t, with: "$1$2")
        t = RX.replace("(?<=[\(AR)])\\s*,\\s*", in: t, with: "، ")
        t = RX.replace("(?<=[\(AR)])\\s*;\\s*", in: t, with: "؛ ")
        t = RX.replace("(?<=[\(AR)])\\s*\\?", in: t, with: "؟")
        t = RX.replace("[ \\t]+([،؛؟!.])", in: t, with: "$1")
        t = RX.replace("([،؛])(?=[\(AR)A-Za-z0-9])", in: t, with: "$1 ")
        t = RX.replace("\(B)و\\s+(?=[\(AR)])", in: t, with: "و")
        t = RX.replace("([!؟])\\1+", in: t, with: "$1")
        for (wrong, right) in Lexicon.spelling.sorted(by: { $0.key.count > $1.key.count }) {
            let w = RX.escape(wrong).replacingOccurrences(of: " ", with: "\\s+")
            let tpl = NSRegularExpression.escapedTemplate(for: right)
            t = RX.replace("\(B)(\(PRE))\(w)\(E)", in: t, with: "$1" + tpl)
        }
        if englishOnOwnLine {
            var out: [String] = []
            for ln in t.components(separatedBy: "\n") {
                let trimmed = ln.trimmingCharacters(in: .whitespaces)
                if RX.test("[\(AR)]", ln), RX.test("[A-Za-z]", ln), !trimmed.hasPrefix("http") {
                    var last = 0
                    let ns = ln as NSString
                    for m in RX.matches(enChunk, in: ln) {
                        let before = ns.substring(with: NSRange(location: last, length: m.range.location - last))
                            .trimmingCharacters(in: .whitespaces)
                        if !before.isEmpty { out.append(before) }
                        out.append(ns.substring(with: m.range))
                        last = m.range.location + m.range.length
                    }
                    let rest = ns.substring(from: last).trimmingCharacters(in: .whitespaces)
                    if !rest.isEmpty { out.append(rest) }
                } else {
                    out.append(ln)
                }
            }
            t = out.joined(separator: "\n")
        }
        t = RX.replace("[^\\S\\n]{2,}", in: t, with: " ")
        t = RX.replace("[ \\t]+\\n", in: t, with: "\n")
        t = RX.replace("\\n{3,}", in: t, with: "\n\n")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
