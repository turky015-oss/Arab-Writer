import Foundation

public struct DiffChange: Identifiable, Sendable, Hashable {
    public enum Op: String, Sendable { case replace = "تعديل", delete = "حذف", insert = "إضافة" }
    public var id = UUID()
    public let op: Op
    public let before: String
    public let after: String
}

/// فرق على مستوى الكلمات (أطول تتابع مشترك).
public enum TextDiff {
    public static func compare(_ a: String, _ b: String) -> (changes: [DiffChange], similarity: Int) {
        let wa = a.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let wb = b.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let n = wa.count, m = wb.count
        if n == 0 && m == 0 { return ([], 100) }
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    dp[i][j] = wa[i] == wb[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }
        var changes: [DiffChange] = []
        var i = 0, j = 0
        var del: [String] = [], ins: [String] = []
        func flush() {
            if del.isEmpty && ins.isEmpty { return }
            let op: DiffChange.Op = del.isEmpty ? .insert : (ins.isEmpty ? .delete : .replace)
            changes.append(DiffChange(op: op, before: del.joined(separator: " "), after: ins.joined(separator: " ")))
            del = []; ins = []
        }
        while i < n || j < m {
            if i < n && j < m && wa[i] == wb[j] {
                flush(); i += 1; j += 1
            } else if j < m && (i == n || dp[i][j + 1] >= dp[i + 1][j]) {
                ins.append(wb[j]); j += 1
            } else {
                del.append(wa[i]); i += 1
            }
        }
        flush()
        let sim = Int((2.0 * Double(dp[0][0]) / Double(n + m) * 100).rounded())
        return (changes, sim)
    }
}
