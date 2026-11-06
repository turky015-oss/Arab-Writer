import AppKit
import Observation
import ArabWriterCore

/// نص وصل من برنامج آخر وينتظر قسم الكتابة.
@MainActor @Observable
final class Inbox {
    static let shared = Inbox()
    var text: String?
}

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ v: T) { value = v }
}

/// خدمات الماك: تظهر في كليك يمين ← الخدمات على أي نص مظلل في أي برنامج.
@MainActor
final class ServiceProvider: NSObject {
    static let shared = ServiceProvider()

    /// تصحيح فوري بدون إنترنت، ويرجع النص مكانه.
    @objc func fixText(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else { return }
        let fixed = ArabicLinter.fix(text, englishOnOwnLine: AppSettings.shared.englishOnOwnLine)
        pboard.clearContents()
        pboard.setString(fixed, forType: .string)
        SoundFX.play(.success)
    }

    /// إعادة صياغة بـ Claude، ويرجع النص مكانه.
    @objc func rewriteText(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else { return }
        let settings = AppSettings.shared
        guard let client = try? settings.client() else {
            error.pointee = "المحرّك الذكي غير متاح. أضف مفتاح Claude من إعدادات Arab Writer."
            return
        }
        let en = settings.englishOnOwnLine
        let system = SkillPrompt.pick(.writing, client)
        let user = WritingEngine.instruction(
            for: WriteRequest(text: text, mode: .rewrite, register: .keep, platform: .none, words: nil), en: en)

        // الخدمة تنتظر الرد، فالطلب يجري في الخلفية والخيط الرئيسي ينتظره بحد أقصى ٥٥ ثانية
        let result = Box<Result<String, Error>?>(nil)
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do { result.value = .success(try await client.complete(system: system, user: user)) }
            catch { result.value = .failure(error) }
            done.signal()
        }
        guard done.wait(timeout: .now() + 58) == .success, let r = result.value else {
            error.pointee = "تأخر الرد. جرّب نصاً أقصر أو افتحه في Arab Writer."
            return
        }
        switch r {
        case .success(let raw):
            let out = ArabicLinter.fix(WritingEngine.splitQuestion(raw).0, englishOnOwnLine: en)
            pboard.clearContents()
            pboard.setString(out, forType: .string)
            SoundFX.play(.success)
        case .failure(let e):
            error.pointee = e.localizedDescription as NSString
            SoundFX.play(.error)
        }
    }

    /// يفتح النص في قسم الكتابة.
    @objc func openText(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else { return }
        Inbox.shared.text = text
        NSApp.activate()
    }
}
