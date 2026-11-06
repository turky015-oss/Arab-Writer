import Foundation
import Security

/// مخزن المفتاح في سلسلة مفاتيح الماك. المفتاح لا يُحفظ في ملف ولا في الإعدادات.
enum Keychain {
    private static let service = "app.arabwriter.mac"
    private static let account = "anthropic-api-key"

    static func read() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        delete()
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(trimmed.utf8),
        ]
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
    }
}

enum ClaudeError: LocalizedError {
    case noKey
    case http(Int, String)
    case empty

    var errorDescription: String? {
        switch self {
        case .noKey: return "أضف مفتاح Claude من الإعدادات لتفعيل المزايا الذكية."
        case .http(let code, let msg):
            switch code {
            case 401: return "المفتاح غير صحيح. راجعه من الإعدادات."
            case 429: return "وصلت حد الاستخدام مؤقتاً. جرّب بعد قليل."
            case 529, 503: return "خدمة Claude مزدحمة الحين. جرّب بعد دقيقة."
            default: return "تعذّر الاتصال (\(code)): \(msg)"
            }
        case .empty: return "وصل رد فارغ. جرّب مرة ثانية."
        }
    }
}

/// اتصال مباشر بواجهة Claude بمفتاح المستخدم نفسه.
struct ClaudeClient {
    var apiKey: String
    var model: String

    func complete(system: String, user: String, maxTokens: Int = 4096) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            // التعليمات ثابتة وطويلة، فتُخزَّن مؤقتاً لتقليل التكلفة
            "system": [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]],
            "messages": [["role": "user", "content": user]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard code == 200 else {
            let msg = ((json?["error"] as? [String: Any])?["message"] as? String) ?? String(decoding: data, as: UTF8.self)
            throw ClaudeError.http(code, msg)
        }
        let parts = (json?["content"] as? [[String: Any]]) ?? []
        let text = parts.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClaudeError.empty }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
