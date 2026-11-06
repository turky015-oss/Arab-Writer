import Foundation
import MLXLLM
import MLXLMCommon

/// نموذج لغوي يعمل داخل الجهاز بالكامل (Qwen2.5-3B بدقة 4 بت عبر MLX)، بلا إنترنت.
actor LocalModel {
    static let shared = LocalModel()

    /// مكان النموذج داخل التطبيق، أو في مجلد المشروع أثناء التطوير.
    nonisolated static var directory: URL? {
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("Model"),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Model"),
        ]
        return candidates.compactMap { $0 }.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("config.json").path)
        }
    }

    nonisolated static var isAvailable: Bool {
        #if arch(arm64)
        return directory != nil
        #else
        return false
        #endif
    }

    private var container: ModelContainer?
    private var loading: Task<ModelContainer, Error>?

    private func load() async throws -> ModelContainer {
        if let c = container { return c }
        if let t = loading { return try await t.value }
        guard let dir = Self.directory else { throw LocalModelError.missing }
        let t = Task { try await LLMModelFactory.shared.loadContainer(configuration: ModelConfiguration(directory: dir)) }
        loading = t
        do {
            let c = try await t.value
            container = c
            loading = nil
            return c
        } catch {
            loading = nil
            throw LocalModelError.failed(error.localizedDescription)
        }
    }

    /// يحمّل النموذج في الذاكرة مسبقاً حتى يكون أول طلب أسرع.
    func warmUp() async { _ = try? await load() }

    func generate(system: String, user: String, maxTokens: Int,
                  onText: (@Sendable (String) -> Void)? = nil) async throws -> String {
        let c = try await load()
        var params = GenerateParameters(temperature: 0.45)
        params.topP = 0.9
        params.repetitionPenalty = 1.08
        let limit = maxTokens
        let messages: [[String: String]] = [["role": "system", "content": system], ["role": "user", "content": user]]
        let result = try await c.perform { context in
            let input = try await context.processor.prepare(input: UserInput(messages: messages))
            var last = Date.distantPast
            return try MLXLMCommon.generate(input: input, parameters: params, context: context) { tokens in
                if let onText, Date().timeIntervalSince(last) > 0.08 {
                    last = Date()
                    onText(context.tokenizer.decode(tokens: tokens))
                }
                return tokens.count >= limit || Task.isCancelled ? .stop : .more
            }
        }
        let out = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        onText?(out)
        guard !out.isEmpty else { throw LocalModelError.empty }
        return out
    }
}

enum LocalModelError: LocalizedError {
    case missing, empty, unsupported
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .missing: return "النموذج الداخلي غير موجود في هذه النسخة."
        case .empty: return "النموذج الداخلي رجّع رداً فارغاً. جرّب مرة ثانية."
        case .unsupported: return "النموذج الداخلي يحتاج ماك بمعالج أبل."
        case .failed(let m): return "تعذّر تشغيل النموذج الداخلي: \(m)"
        }
    }
}

// MARK: - محرّك موحّد

/// واجهة واحدة للكتابة: داخلي على الجهاز، أو Claude بمفتاح المستخدم.
protocol TextEngine: Sendable {
    var isLocal: Bool { get }
    func complete(system: String, user: String, maxTokens: Int) async throws -> String
    func stream(system: String, user: String, maxTokens: Int, onText: @escaping @MainActor (String) -> Void) async throws -> String
}

extension TextEngine {
    func complete(system: String, user: String) async throws -> String {
        try await complete(system: system, user: user, maxTokens: 4096)
    }
    func stream(system: String, user: String, onText: @escaping @MainActor (String) -> Void) async throws -> String {
        try await stream(system: system, user: user, maxTokens: 4096, onText: onText)
    }
}

extension ClaudeClient: TextEngine {
    var isLocal: Bool { false }
}

struct LocalEngine: TextEngine {
    var isLocal: Bool { true }
    /// الحد الأعلى لطول الإدخال حتى يبقى سريعاً وفي حدود ذاكرة النموذج.
    static let inputLimit = 14_000

    func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        try await LocalModel.shared.generate(system: system, user: String(user.prefix(Self.inputLimit)), maxTokens: min(maxTokens, 2048))
    }

    func stream(system: String, user: String, maxTokens: Int, onText: @escaping @MainActor (String) -> Void) async throws -> String {
        try await LocalModel.shared.generate(system: system, user: String(user.prefix(Self.inputLimit)), maxTokens: min(maxTokens, 2048)) { t in
            Task { @MainActor in onText(t) }
        }
    }
}

// MARK: - تعليمات مختصرة للنموذج الداخلي

/// النموذج الداخلي صغير، فيأخذ زبدة قواعد المهارة بدل ملفاتها كاملة.
enum LocalPrompt {
    static let base = """
    أنت محرر عربي محترف داخل تطبيق Arab Writer. اكتب كما يكتب إنسان عربي متمكن، لا كما يكتب الذكاء الاصطناعي.
    قواعد صارمة:
    - أرجع النص النهائي وحده، بلا مقدمة ولا شرح ولا عنوان عن النص ولا علامات اقتباس حوله.
    - لا تضف أي معلومة أو رقم أو اسم أو إحصائية غير موجودة في النص الأصلي.
    - احذف العبارات الآلية مثل: في عالم اليوم، في ظل التطور، لا شك أن، من المعروف أن، تجدر الإشارة، الجدير بالذكر، يلعب دوراً، يفتح آفاقاً، نقلة نوعية، يغير قواعد اللعبة، بشكل كبير، بشكل فعال، في الختام، ختاماً، لا تتردد في.
    - لا تبنِ الجمل على «ليس فقط… بل»، ولا تسرد ثلاثيات متتالية، ولا تبدأ بسؤال ثم تجيب عليه.
    - لا إيموجي، لا شرطة طويلة، لا خط عريض، ولا نقاط إلا إذا كانت في الأصل.
    - نوّع طول الجمل، واستعمل أفعالاً مباشرة وكلمات عادية.
    - اكتب الهمزات والتاء المربوطة والألف المقصورة صحيحة، واستعمل «،» و«؛» و«؟» العربية.
    """

    static let story = base + """

    أنت الآن تكتب قصة قصيرة: ابدأ بشخص يفعل شيئاً في مكان وزمن محددين، اجعل شيئاً يقاومه، ثم نقطة تحول، ثم نهاية تغلق المشهد بلا موعظة ولا شرح للمغزى. حوار قليل وطبيعي.
    """

    static let summary = base + """

    أنت الآن تلخّص مستنداً: عنوان قصير في السطر الأول ثم فقرات متصلة. كل رقم واسم في الملخص يجب أن يكون في المستند.
    """

    static let platforms: [String: String] = [
        "إكس": "قالب إكس: أقل من 280 حرفاً، سطر أول يشد، بلا وسوم كثيرة.",
        "إنستقرام": "قالب إنستقرام: سطر أول قوي، فقرات قصيرة، وسطر أخير يدعو للتفاعل بلا مبالغة.",
        "لينكدإن": "قالب لينكدإن: نبرة مهنية، تجربة أو فكرة محددة، فقرات قصيرة.",
        "واتساب": "قالب واتساب: رسالة قصيرة مباشرة كما يكتبها شخص لشخص.",
        "خطاب رسمي": "قالب خطاب رسمي: فصحى رسمية، تحية، موضوع، طلب واضح، ختام رسمي.",
        "سكربت فيديو": "قالب سكربت فيديو: جمل قصيرة تُقال بصوت، أول جملة تشد خلال ثانيتين.",
    ]
}
