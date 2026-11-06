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
    /// "local" = النموذج الداخلي، "claude" = Claude بالمفتاح
    var engine: String
    private(set) var hasKey: Bool

    /// فيه محرّك ذكي متاح (داخلي أو Claude).
    var aiAvailable: Bool { LocalModel.isAvailable || hasKey }
    /// الطلب القادم بيروح للنموذج الداخلي.
    var usingLocal: Bool { LocalModel.isAvailable && !(engine == "claude" && hasKey) }

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
        engine = d.string(forKey: "engine") ?? "local"
        hasKey = Keychain.read() != nil
    }

    func persist() {
        let d = UserDefaults.standard
        d.set(model, forKey: "model")
        d.set(englishOnOwnLine, forKey: "enLines")
        d.set(autoRetry, forKey: "autoRetry")
        d.set(engine, forKey: "engine")
    }

    func setKey(_ key: String) {
        Keychain.save(key)
        hasKey = Keychain.read() != nil
    }

    func removeKey() {
        Keychain.delete()
        hasKey = false
    }

    func claude() throws -> ClaudeClient {
        guard let key = Keychain.read() else { throw ClaudeError.noKey }
        return ClaudeClient(apiKey: key, model: model)
    }

    /// المحرّك المختار: الداخلي افتراضياً، وClaude إذا اختاره المستخدم وعنده مفتاح.
    func client() throws -> any TextEngine {
        if usingLocal { return LocalEngine() }
        if hasKey { return try claude() }
        #if !arch(arm64)
        throw LocalModelError.unsupported
        #else
        throw LocalModelError.missing
        #endif
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

    enum Kind { case writing, story, summary }

    /// التعليمات المناسبة للمحرّك: كاملة لـ Claude، ومختصرة للنموذج الداخلي.
    static func pick(_ kind: Kind, _ engine: any TextEngine) -> String {
        switch (kind, engine.isLocal) {
        case (.writing, true): return LocalPrompt.base
        case (.story, true): return LocalPrompt.story
        case (.summary, true): return LocalPrompt.summary
        case (.writing, false): return writing
        case (.story, false): return story
        case (.summary, false): return summary
        }
    }

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
        case .none: return "circle.slash"
        case .x: return "text.bubble.fill"
        case .instagram: return "photo.on.rectangle.angled"
        case .linkedin: return "briefcase.fill"
        case .whatsapp: return "message.fill"
        case .official: return "signature"
        case .script: return "film.fill"
        }
    }

    /// وصف قصير يظهر تحت اسم المنصة.
    var caption: String {
        switch self {
        case .none: return "نص عام"
        case .x: return "تغريدة قصيرة"
        case .instagram: return "كابشن"
        case .linkedin: return "منشور مهني"
        case .whatsapp: return "رسالة"
        case .official: return "فصحى رسمية"
        case .script: return "للتصوير"
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
        if r.platform != .none {
            parts.append("المنصة: \(r.platform.rawValue). طبّق قالبها.")
            if let t = LocalPrompt.platforms[r.platform.rawValue] { parts.append(t) }
        }
        if let w = r.words { parts.append("قفل الطول: \(w) كلمة بهامش 10%.") }
        parts.append(en ? "كل كلمة إنجليزية في سطر مستقل وحدها." : "اترك الكلمات الإنجليزية في مكانها داخل السطر.")
        return parts.joined(separator: "\n") + "\n\nالنص:\n" + r.text
    }

    static func run(_ r: WriteRequest, onPartial: ((String) -> Void)? = nil) async throws -> WriteResult {
        let settings = AppSettings.shared
        let en = settings.englishOnOwnLine
        let retry = settings.autoRetry
        let source: String? = r.mode == .write ? nil : r.text
        var opts = LintOptions(wordsTarget: r.words, source: source, englishOnOwnLine: en)

        // بدون محرّك ذكي: الإصلاح الآمن والفحص فقط
        guard settings.aiAvailable else {
            let out = ArabicLinter.fix(r.text, englishOnOwnLine: en)
            opts.source = r.text
            let d = TextDiff.compare(r.text, out)
            return WriteResult(text: out, question: nil, report: ArabicLinter.check(out, options: opts),
                               changes: d.changes, similarity: d.similarity, usedAI: false)
        }

        let client = try settings.client()
        let system = SkillPrompt.pick(.writing, client)
        let user = instruction(for: r, en: en)
        let raw: String
        if let onPartial {
            raw = try await client.stream(system: system, user: user) { onPartial(WritingEngine.splitQuestion($0).0) }
        } else {
            raw = try await client.complete(system: system, user: user)
        }
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

    static func story(title: String, length: StoryLength, register: Register,
                      onPartial: ((String) -> Void)? = nil) async throws -> WriteResult {
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
        let raw: String
        if let onPartial {
            raw = try await client.stream(system: SkillPrompt.pick(.story, client), user: ask) { onPartial($0) }
        } else {
            raw = try await client.complete(system: SkillPrompt.pick(.story, client), user: ask)
        }
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
        let raw = try await client.complete(system: SkillPrompt.pick(.summary, client), user: ask, maxTokens: 4096)
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

// MARK: - الترجمة

enum TranslateDirection: String, CaseIterable, Identifiable {
    case auto = "تلقائي"
    case toArabic = "إلى العربي"
    case toEnglish = "إلى الإنجليزي"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .auto: return "sparkle.magnifyingglass"
        case .toArabic: return "character.book.closed.ar"
        case .toEnglish: return "character.book.closed"
        }
    }

    /// يحدد الاتجاه من نسبة الحروف العربية في النص.
    func resolved(for text: String) -> TranslateDirection {
        guard self == .auto else { return self }
        let ar = text.unicodeScalars.filter { (0x0600...0x06FF).contains($0.value) }.count
        let en = text.unicodeScalars.filter { ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) }.count
        return ar >= en ? .toEnglish : .toArabic
    }
}

extension WritingEngine {
    static func translate(_ text: String, direction: TranslateDirection, register: Register,
                          onPartial: ((String) -> Void)? = nil) async throws -> WriteResult {
        let settings = AppSettings.shared
        let en = settings.englishOnOwnLine
        let client = try settings.client()
        let dir = direction.resolved(for: text)
        let ask: String
        if dir == .toArabic {
            ask = """
            المهمة: ترجم النص التالي إلى العربية كما يكتبه إنسان عربي، لا ترجمة حرفية.
            انقل المعنى والنبرة لا ترتيب الكلمات. طبّق المراحل كلها: لا بصمات آلية ولا تراكيب مترجمة (يلعب دوراً، يفتح الباب أمام).
            السجل: \(register == .fusha ? "فصحى سهلة" : (register == .saudi ? "لهجة سعودية طبيعية" : "حسب طبيعة النص"))
            لا تضف ولا تحذف معلومة. أسماء العلم والمنتجات تبقى بالإنجليزية.
            \(en ? "كل كلمة إنجليزية في سطر مستقل وحدها." : "")
            أرجع الترجمة وحدها.

            النص:
            \(text)
            """
        } else {
            ask = """
            Task: translate the following text into natural, human English, the way a native writer would put it. Not word for word.
            Carry the meaning and tone. Apply the English rules (no AI markers: delve, leverage, seamless, in today's fast-paced world, it's worth noting).
            Do not add or drop any fact, number or name. Return the translation only.

            Text:
            \(text)
            """
        }
        let raw: String
        if let onPartial {
            raw = try await client.stream(system: SkillPrompt.pick(.writing, client), user: ask) { onPartial($0) }
        } else {
            raw = try await client.complete(system: SkillPrompt.pick(.writing, client), user: ask)
        }
        let draft = splitQuestion(raw).0
        if dir == .toArabic {
            let out = ArabicLinter.fix(draft, englishOnOwnLine: en)
            let report = ArabicLinter.check(out, options: LintOptions(source: text, englishOnOwnLine: en))
            return WriteResult(text: out, question: nil, report: report, changes: [], similarity: 0, usedAI: true)
        }
        var report = LintReport()
        report.stats = ArabicLinter.stats(draft)
        return WriteResult(text: draft, question: nil, report: report, changes: [], similarity: 0, usedAI: true)
    }
}

// MARK: - الفيديو

struct VideoOptions {
    var seconds: Int
    var style: String
    var audio: String
    var hero: String
    var platform: String
}

struct VideoPlan: Decodable {
    struct Shot: Decodable, Identifiable {
        let id = UUID()
        let seconds: Double
        let action: String
        enum CodingKeys: String, CodingKey { case seconds, action }
    }
    struct Segment: Decodable, Identifiable {
        let id = UUID()
        let seconds: Double
        let prompt: String
        enum CodingKeys: String, CodingKey { case seconds, prompt }
    }
    struct ScreenLine: Decodable, Identifiable {
        let id = UUID()
        let at: String
        let text: String
        enum CodingKeys: String, CodingKey { case at, text }
    }

    var text: String = ""
    var model: String = "best_available"
    var modelReason: String = ""
    var shots: [Shot] = []
    var segments: [Segment] = []
    var hook: String = ""
    var screenLines: [ScreenLine] = []
    var caption: String = ""
    var hashtags: [String] = []

    enum CodingKeys: String, CodingKey { case text, model, modelReason, shots, segments, hook, screenLines, caption, hashtags }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        model = (try? c.decode(String.self, forKey: .model)) ?? "best_available"
        modelReason = (try? c.decode(String.self, forKey: .modelReason)) ?? ""
        shots = (try? c.decode([Shot].self, forKey: .shots)) ?? []
        segments = (try? c.decode([Segment].self, forKey: .segments)) ?? []
        hook = (try? c.decode(String.self, forKey: .hook)) ?? ""
        screenLines = (try? c.decode([ScreenLine].self, forKey: .screenLines)) ?? []
        caption = (try? c.decode(String.self, forKey: .caption)) ?? ""
        hashtags = (try? c.decode([String].self, forKey: .hashtags)) ?? []
    }

    var totalSeconds: Double { shots.reduce(0) { $0 + $1.seconds } }

    /// الحزمة كاملة كنص جاهز للنسخ.
    var packageText: String {
        var out: [String] = []
        out.append("النص\n\(text)")
        out.append("اللقطات\n" + shots.enumerated().map { "\($0.offset + 1). \(SheetService.format($0.element.seconds)) ث: \($0.element.action)" }.joined(separator: "\n"))
        out.append("النموذج\n\(model): \(modelReason)")
        out.append("البرومبتات\n" + segments.enumerated().map { "مقطع \($0.offset + 1) (\(SheetService.format($0.element.seconds)) ث)\n\($0.element.prompt)" }.joined(separator: "\n\n"))
        out.append("الكابشن\nالخطاف: \(hook)\n" + screenLines.map { "\($0.at): \($0.text)" }.joined(separator: "\n")
                   + "\n\n\(caption)\n\(hashtags.joined(separator: " "))")
        return out.joined(separator: "\n\n")
    }
}

extension WritingEngine {
    static func video(_ text: String, options o: VideoOptions, onPartial: ((String) -> Void)? = nil) async throws -> VideoPlan {
        let client = try AppSettings.shared.client()
        let ask = """
        المهمة: وضع الفيديو بأسلوب Commands Only. حوّل النص التالي إلى حزمة فيديو بقواعد المهارة كاملة.
        المدة: \(o.seconds) ثانية بالضبط. الأسلوب: \(o.style). الصوت: \(o.audio). البطل: \(o.hero). المنصة: \(o.platform)، عمودي 9:16.
        الأقفال: مجموع ثواني اللقطات يساوي \(o.seconds) بالضبط. 8 و10 ثوانٍ لا تُقسَّم. لا نص عربي داخل الإطار. لا أسماء نماذج مخترعة (اكتب best_available إن لم تتأكد).
        نظّف النص بالمرحلتين قبل التقطيع.
        البرومبتات بالإنجليزية: قائمة لقطات (كاميرا، عدسة، ضوء، فعل، صوت) بلا كلمات مثل cinematic masterpiece أو 8k.

        أرجع JSON فقط بلا أي نص قبله أو بعده، بهذه المفاتيح:
        {"text": "النص النظيف", "model": "اسم النموذج", "modelReason": "سبب في سطر",
         "shots": [{"seconds": 3, "action": "وصف اللقطة بالعربي"}],
         "segments": [{"seconds": 10, "prompt": "English prompt"}],
         "hook": "سطر الخطاف", "screenLines": [{"at": "0:00", "text": "سطر الشاشة"}],
         "caption": "كابشن النشر", "hashtags": ["#وسم"]}

        النص:
        \(text)
        """
        let raw: String
        if let onPartial {
            raw = try await client.stream(system: SkillPrompt.pick(.writing, client), user: ask, maxTokens: 6000) { onPartial($0) }
        } else {
            raw = try await client.complete(system: SkillPrompt.pick(.writing, client), user: ask, maxTokens: 6000)
        }
        guard let a = raw.firstIndex(of: "{"), let b = raw.lastIndex(of: "}"),
              let data = String(raw[a...b]).data(using: .utf8),
              let plan = try? JSONDecoder().decode(VideoPlan.self, from: data) else {
            throw ToolError.invalid("وصل رد غير مرتب. اضغط مرة ثانية.")
        }
        return plan
    }
}
