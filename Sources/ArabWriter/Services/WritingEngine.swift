import Foundation
import Observation
import ArabWriterCore

// MARK: - الإعدادات

@MainActor @Observable
final class AppSettings {
    static let shared = AppSettings()

    var model: String
    var englishOnOwnLine: Bool
    var autoRetry: Bool
    private(set) var hasKey: Bool

    static let models: [(id: String, name: String)] = [
        ("claude-sonnet-5-5", "Sonnet 5.5 · متوازن"),
        ("claude-opus-5-5", "Opus 5.5 · الأدق"),
        ("claude-haiku-5-5", "Haiku 5.5 · الأسرع"),
    ]

    private init() {
        let d = UserDefaults.standard
        model = d.string(forKey: "model") ?? "claude-sonnet-5-5"
        englishOnOwnLine = d.object(forKey: "enLines") as? Bool ?? true
        autoRetry = d.object(forKey: "autoRetry") as? Bool ?? true
        hasKey = Keychain.read() != nil
    }

    func persist() {
        let d = UserDefaults.standard
        d.set(model, forKey: "model")
        d.set(englishOnOwnLine, forKey: "enLines")
        d.set(autoRetry, forKey: "autoRetry")
    }

    func setKey(_ key: String) {
        Keychain.save(key)
        hasKey = Keychain.read() != nil
    }

    func removeKey() {
        Keychain.delete()
        hasKey = false
    }

    func client() throws -> ClaudeClient {
        guard let key = Keychain.read() else { throw ClaudeError.noKey }
        return ClaudeClient(apiKey: key, model: model)
    }
}

// MARK: - تعليمات المهارة

enum SkillPrompt {
    static func load(_ name: String) -> String {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "Skill"),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Resources/Skill/\(name).md"),
        ]
        for case let url? in candidates {
            if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        }
        return ""
    }

    static let appRules = """
    أنت محرّك تطبيق Arab Writer على الماك. تعمل بالقواعد المرفقة كاملة.
    لا تملك أدوات ولا سكربتات: الفحص الآلي يجري داخل التطبيق بعد ردك، فلا تذكره.
    أرجع النص النهائي وحده. لا مقدمة، لا شرح، لا عناوين عن النص، لا علامات اقتباس حوله، لا كتل كود.
    إن احتجت سؤالاً عن تفصيلة ناقصة (حسب قاعدة لا اختلاق)، ضعه بعد النص في سطر أخير يبدأ بـ «سؤال:».
    """

    static var writing: String {
        [appRules,
         load("SKILL"), load("ai-markers-arabic"), load("structures"), load("voice"),
         load("arabic-proofreading"), load("arabic-dictionary"), load("platforms"), load("english-markers")]
            .filter { !$0.isEmpty }.joined(separator: "\n\n---\n\n")
    }

    static var story: String {
        [appRules, load("storytelling"), load("ai-markers-arabic"), load("structures"), load("voice"), load("arabic-proofreading")]
            .filter { !$0.isEmpty }.joined(separator: "\n\n---\n\n")
    }

    static var summary: String {
        [appRules, load("pdf-workflow"), load("ai-markers-arabic"), load("arabic-proofreading")]
            .filter { !$0.isEmpty }.joined(separator: "\n\n---\n\n")
    }
}

// MARK: - خيارات الكتابة

enum WriteMode: String, CaseIterable, Identifiable {
    case rewrite = "صياغة"
    case proofread = "تدقيق"
    case write = "كتابة"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .rewrite: return "wand.and.stars"
        case .proofread: return "checkmark.seal"
        case .write: return "pencil.line"
        }
    }
    var hint: String {
        switch self {
        case .rewrite: return "يمسح بصمات الذكاء الاصطناعي ويعيد الصياغة بصوت بشري"
        case .proofread: return "يصحح الإملاء والنحو والترقيم ويبقي كلامك كما هو"
        case .write: return "اكتب فكرة خام ويطلع لك نص جاهز للنشر"
        }
    }
}

enum Register: String, CaseIterable, Identifiable {
    case keep = "كما هو"
    case saudi = "سعودي"
    case fusha = "فصحى"
    var id: String { rawValue }
}

enum Platform: String, CaseIterable, Identifiable {
    case none = "بدون"
    case x = "إكس"
    case instagram = "إنستقرام"
    case linkedin = "لينكدإن"
    case whatsapp = "واتساب"
    case official = "خطاب رسمي"
    case script = "سكربت فيديو"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .none: return "circle.dashed"
        case .x: return "at"
        case .instagram: return "camera"
        case .linkedin: return "briefcase"
        case .whatsapp: return "message"
        case .official: return "doc.text"
        case .script: return "video"
        }
    }
}

struct WriteRequest {
    var text: String
    var mode: WriteMode
    var register: Register
    var platform: Platform
    var words: Int?
}

struct WriteResult {
    var text: String
    var question: String?
    var report: LintReport
    var changes: [DiffChange]
    var similarity: Int
    var usedAI: Bool
}

// MARK: - المحرّك

@MainActor
enum WritingEngine {
    /// يفصل سطر «سؤال:» الأخير عن النص.
    static func splitQuestion(_ s: String) -> (String, String?) {
        var lines = s.components(separatedBy: "\n")
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        if let last = lines.last?.trimmingCharacters(in: .whitespaces), last.hasPrefix("سؤال:") {
            lines.removeLast()
            return (lines.joined(separator: "\n"), String(last.dropFirst(5)).trimmingCharacters(in: .whitespaces))
        }
        return (s, nil)
    }

    static func instruction(for r: WriteRequest, en: Bool) -> String {
        var parts: [String] = []
        switch r.mode {
        case .rewrite: parts.append("المهمة: أعد صياغة النص التالي بالمراحل الثلاث (امسح، دقّق). لا تضف معلومة غير موجودة.")
        case .proofread: parts.append("المهمة: دقّق النص التالي إملائياً ونحوياً وترقيمياً فقط. لا تغيّر الصياغة ولا الأسلوب ولا الترتيب.")
        case .write: parts.append("المهمة: اكتب نصاً جاهزاً للنشر من الفكرة التالية. لا تخترع أرقاماً ولا إحصاءات ولا أسماء.")
        }
        switch r.register {
        case .keep: parts.append("السجل: كما جاء في النص.")
        case .saudi: parts.append("السجل: لهجة سعودية طبيعية.")
        case .fusha: parts.append("السجل: فصحى سهلة.")
        }
        if r.platform != .none { parts.append("المنصة: \(r.platform.rawValue). طبّق قالبها.") }
        if let w = r.words { parts.append("قفل الطول: \(w) كلمة بهامش 10%.") }
        parts.append(en ? "كل كلمة إنجليزية في سطر مستقل وحدها." : "اترك الكلمات الإنجليزية في مكانها داخل السطر.")
        return parts.joined(separator: "\n") + "\n\nالنص:\n" + r.text
    }

    static func run(_ r: WriteRequest) async throws -> WriteResult {
        let settings = AppSettings.shared
        let en = settings.englishOnOwnLine
        let retry = settings.autoRetry
        let source: String? = r.mode == .write ? nil : r.text
        var opts = LintOptions(wordsTarget: r.words, source: source, englishOnOwnLine: en)

        // بدون مفتاح: الإصلاح الآمن والفحص فقط
        guard settings.hasKey else {
            let out = ArabicLinter.fix(r.text, englishOnOwnLine: en)
            opts.source = r.text
            let d = TextDiff.compare(r.text, out)
            return WriteResult(text: out, question: nil, report: ArabicLinter.check(out, options: opts),
                               changes: d.changes, similarity: d.similarity, usedAI: false)
        }

        let client = try settings.client()
        let system = SkillPrompt.writing
        let raw = try await client.complete(system: system, user: instruction(for: r, en: en))
        var (draft, question) = splitQuestion(raw)
        draft = ArabicLinter.fix(draft, englishOnOwnLine: en)
        var report = ArabicLinter.check(draft, options: opts)

        // جولة تصحيح واحدة إن بقيت أخطاء مانعة لا يصلحها الإصلاح الآلي
        if retry && !report.isClean {
            let list = report.errors.prefix(20).map { "- [\($0.kind)] \($0.message)" }.joined(separator: "\n")
            let ask = """
            هذا نصك بعد الفحص الآلي، وفيه أخطاء مانعة. أصلحها كلها وأرجع النص النهائي وحده.
            الأخطاء:
            \(list)

            النص:
            \(draft)
            """
            let raw2 = try await client.complete(system: system, user: ask)
            let (d2, q2) = splitQuestion(raw2)
            let fixed = ArabicLinter.fix(d2, englishOnOwnLine: en)
            let r2 = ArabicLinter.check(fixed, options: opts)
            if r2.errors.count <= report.errors.count {
                draft = fixed; report = r2
                question = q2 ?? question
            }
        }
        let d = TextDiff.compare(r.text, draft)
        return WriteResult(text: draft, question: question, report: report,
                           changes: d.changes, similarity: d.similarity, usedAI: true)
    }

    static func story(title: String, length: StoryLength, register: Register) async throws -> WriteResult {
        let settings = AppSettings.shared
        let en = settings.englishOnOwnLine
        let client = try settings.client()
        let ask = """
        المهمة: اكتب قصة قصيرة من هذا العنوان بوضع السرد.
        الطول: \(length.range) كلمة.
        السجل: \(register == .keep ? "حسب العنوان" : register.rawValue).
        ابدأ بسطر العنوان ثم سطر فارغ ثم القصة.

        العنوان: \(title)
        """
        let raw = try await client.complete(system: SkillPrompt.story, user: ask)
        let (draft, q) = splitQuestion(raw)
        let out = ArabicLinter.fix(draft, englishOnOwnLine: en)
        return WriteResult(text: out, question: q,
                           report: ArabicLinter.check(out, options: LintOptions(englishOnOwnLine: en)),
                           changes: [], similarity: 0, usedAI: true)
    }

    static func summarize(_ text: String, words: Int) async throws -> String {
        let settings = AppSettings.shared
        let en = settings.englishOnOwnLine
        let client = try settings.client()
        let clipped = String(text.prefix(120_000))
        let ask = """
        المهمة: لخّص المستند التالي بالعربية في حدود \(words) كلمة.
        ابدأ بسطر عنوان قصير، ثم فقرات متصلة. يجوز استعمال قائمة للأرقام والبنود فقط.
        كل رقم واسم في الملخص يجب أن يكون في المستند.

        المستند:
        \(clipped)
        """
        let raw = try await client.complete(system: SkillPrompt.summary, user: ask, maxTokens: 4096)
        return ArabicLinter.fix(splitQuestion(raw).0, englishOnOwnLine: en)
    }
}

enum StoryLength: String, CaseIterable, Identifiable {
    case flash = "ومضة"
    case short = "قصة قصيرة"
    case script = "لسكربت فيديو"
    var id: String { rawValue }
    var range: String {
        switch self {
        case .flash: return "80 إلى 120"
        case .short: return "250 إلى 400"
        case .script: return "120 إلى 180"
        }
    }
}
