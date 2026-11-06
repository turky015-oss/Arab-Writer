import AppKit
import ArabWriterCore

/// وورد عبر محرك النصوص الأصلي في الماك (يقرأ ويكتب docx مباشرة).
enum DocxService {
    static func open(_ url: URL) throws -> NSMutableAttributedString {
        let ext = url.pathExtension.lowercased()
        var opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
        switch ext {
        case "docx": opts[.documentType] = NSAttributedString.DocumentType.officeOpenXML
        case "doc": opts[.documentType] = NSAttributedString.DocumentType.docFormat
        case "rtf": opts[.documentType] = NSAttributedString.DocumentType.rtf
        case "txt", "md": opts[.documentType] = NSAttributedString.DocumentType.plain
            opts[.characterEncoding] = String.Encoding.utf8.rawValue
        default: break
        }
        do {
            let s = try NSAttributedString(url: url, options: opts, documentAttributes: nil)
            return NSMutableAttributedString(attributedString: s)
        } catch {
            throw ToolError.open(url.lastPathComponent)
        }
    }

    static func save(_ s: NSAttributedString, to url: URL) throws {
        let type: NSAttributedString.DocumentType
        switch url.pathExtension.lowercased() {
        case "rtf": type = .rtf
        case "txt": type = .plain
        default: type = .officeOpenXML
        }
        do {
            let data = try s.data(from: NSRange(location: 0, length: s.length), documentAttributes: [.documentType: type])
            try data.write(to: url)
        } catch {
            throw ToolError.write(url.lastPathComponent)
        }
    }

    /// مستند عربي جديد من نص: فقرات من اليمين، والسطر الأول عنوان.
    static func build(title: String?, body: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = .right
        para.baseWritingDirection = .rightToLeft
        para.lineSpacing = 4
        para.paragraphSpacing = 8
        let out = NSMutableAttributedString()
        if let title, !title.isEmpty {
            out.append(NSAttributedString(string: title + "\n", attributes: [
                .font: ArabicFont.bold(size: 20), .paragraphStyle: para,
            ]))
        }
        out.append(NSAttributedString(string: body, attributes: [
            .font: ArabicFont.regular(size: 14), .paragraphStyle: para,
        ]))
        return out
    }

    /// يجعل كل الفقرات من اليمين لليسار مع بقاء باقي التنسيق.
    static func forceRTL(_ s: NSMutableAttributedString) {
        let full = NSRange(location: 0, length: s.length)
        s.enumerateAttribute(.paragraphStyle, in: full) { value, range, _ in
            let p = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            p.baseWritingDirection = .rightToLeft
            if p.alignment == .left || p.alignment == .natural { p.alignment = .right }
            s.addAttribute(.paragraphStyle, value: p, range: range)
        }
    }

    static func replaceAll(_ s: NSMutableAttributedString, find: String, with repl: String) -> Int {
        guard !find.isEmpty else { return 0 }
        return s.mutableString.replaceOccurrences(of: find, with: repl, options: [], range: NSRange(location: 0, length: s.length))
    }
}
