import AppKit
import PDFKit
import CoreText

enum ToolError: LocalizedError {
    case open(String)
    case invalid(String)
    case write(String)
    var errorDescription: String? {
        switch self {
        case .open(let n): return "تعذّر فتح الملف «\(n)»."
        case .invalid(let m): return m
        case .write(let n): return "تعذّر حفظ «\(n)»."
        }
    }
}

/// أدوات PDF مبنية على PDFKit الأصلية في النظام.
enum PDFService {
    static func open(_ url: URL) throws -> PDFDocument {
        guard let d = PDFDocument(url: url) else { throw ToolError.open(url.lastPathComponent) }
        return d
    }

    static func merge(_ urls: [URL]) throws -> PDFDocument {
        let out = PDFDocument()
        for u in urls {
            let d = try open(u)
            for i in 0..<d.pageCount {
                if let p = d.page(at: i)?.copy() as? PDFPage { out.insert(p, at: out.pageCount) }
            }
        }
        return out
    }

    /// يحوّل نصاً مثل «1-3, 5, 8-» إلى أرقام صفحات (من الصفر).
    static func parsePages(_ spec: String, count: Int) throws -> [Int] {
        let cleaned = spec.replacingOccurrences(of: "،", with: ",").replacingOccurrences(of: " ", with: "")
        let digits = String(cleaned.map { ch -> Character in
            if let v = ch.unicodeScalars.first?.value, (0x0660...0x0669).contains(v) {
                return Character(String(v - 0x0660))
            }
            return ch
        })
        var out: [Int] = []
        for part in digits.split(separator: ",") where !part.isEmpty {
            let bits = part.split(separator: "-", omittingEmptySubsequences: false)
            if bits.count == 1, let n = Int(bits[0]) {
                out.append(n)
            } else if bits.count == 2 {
                let a = Int(bits[0]) ?? 1
                let b = bits[1].isEmpty ? count : (Int(bits[1]) ?? count)
                guard a <= b else { throw ToolError.invalid("النطاق «\(part)» غير صحيح.") }
                out.append(contentsOf: a...b)
            } else {
                throw ToolError.invalid("لم أفهم «\(part)». اكتب مثل: 1-3، 5")
            }
        }
        guard !out.isEmpty else { throw ToolError.invalid("اكتب أرقام الصفحات.") }
        for n in out where n < 1 || n > count {
            throw ToolError.invalid("الصفحة \(n) غير موجودة. الملف فيه \(count) صفحة.")
        }
        return out.map { $0 - 1 }
    }

    static func pick(_ d: PDFDocument, pages: [Int]) -> PDFDocument {
        let out = PDFDocument()
        for i in pages {
            if let p = d.page(at: i)?.copy() as? PDFPage { out.insert(p, at: out.pageCount) }
        }
        return out
    }

    static func delete(_ d: PDFDocument, pages: [Int]) -> PDFDocument {
        let drop = Set(pages)
        return pick(d, pages: (0..<d.pageCount).filter { !drop.contains($0) })
    }

    static func split(_ d: PDFDocument) -> [PDFDocument] {
        (0..<d.pageCount).map { pick(d, pages: [$0]) }
    }

    /// يرسم الصفحات من جديد مع طبقة فوقها (علامة مائية، ترقيم).
    static func stamp(_ d: PDFDocument, draw: (CGContext, CGRect, Int) -> Void) throws -> PDFDocument {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw ToolError.invalid("تعذّر تجهيز الملف.") }
        for i in 0..<d.pageCount {
            guard let page = d.page(at: i) else { continue }
            var box = page.bounds(for: .mediaBox)
            let info = [kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary
            ctx.beginPDFPage(info)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            page.draw(with: .mediaBox, to: ctx)
            draw(ctx, box, i)
            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        guard let out = PDFDocument(data: data as Data) else { throw ToolError.invalid("تعذّر تجهيز الملف.") }
        return out
    }

    static func watermark(_ d: PDFDocument, text: String, opacity: CGFloat = 0.14) throws -> PDFDocument {
        try stamp(d) { ctx, box, _ in
            let size = min(box.width, box.height) / CGFloat(max(4, text.count / 2 + 3))
            let attr = NSAttributedString(string: text, attributes: [
                .font: ArabicFont.bold(size: max(28, size)),
                .foregroundColor: NSColor.black.withAlphaComponent(opacity),
                ctColor: NSColor.black.withAlphaComponent(opacity).cgColor,
            ])
            let line = CTLineCreateWithAttributedString(attr)
            let w = CTLineGetTypographicBounds(line, nil, nil, nil)
            ctx.saveGState()
            ctx.translateBy(x: box.midX, y: box.midY)
            ctx.rotate(by: .pi / 5)
            ctx.textPosition = CGPoint(x: -w / 2, y: 0)
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
    }

    enum NumberStyle: String, CaseIterable, Identifiable {
        case arabic = "١ ٢ ٣"
        case latin = "1 2 3"
        case ofTotal = "١ من ١٠"
        var id: String { rawValue }
    }

    static func number(_ d: PDFDocument, style: NumberStyle) throws -> PDFDocument {
        let total = d.pageCount
        let ar = NumberFormatter()
        ar.locale = Locale(identifier: "ar_SA")
        return try stamp(d) { ctx, box, i in
            let n = i + 1
            let s: String
            switch style {
            case .arabic: s = ar.string(from: NSNumber(value: n)) ?? "\(n)"
            case .latin: s = "\(n)"
            case .ofTotal: s = "\(ar.string(from: NSNumber(value: n)) ?? "\(n)") من \(ar.string(from: NSNumber(value: total)) ?? "\(total)")"
            }
            let attr = NSAttributedString(string: s, attributes: [
                .font: ArabicFont.regular(size: 11),
                .foregroundColor: NSColor.darkGray,
                ctColor: NSColor.darkGray.cgColor,
            ])
            let line = CTLineCreateWithAttributedString(attr)
            let w = CTLineGetTypographicBounds(line, nil, nil, nil)
            ctx.textPosition = CGPoint(x: box.midX - w / 2, y: box.minY + 24)
            CTLineDraw(line, ctx)
        }
    }

    static func write(_ d: PDFDocument, to url: URL, password: String? = nil, compress: Bool = false) throws {
        var opts: [PDFDocumentWriteOption: Any] = [:]
        if let pw = password, !pw.isEmpty {
            opts[.userPasswordOption] = pw
            opts[.ownerPasswordOption] = pw
        }
        if compress {
            opts[.saveImagesAsJPEGOption] = true
            opts[.optimizeImagesForScreenOption] = true
        }
        guard d.write(to: url, withOptions: opts) else { throw ToolError.write(url.lastPathComponent) }
    }

    static func text(_ d: PDFDocument) -> String {
        (0..<d.pageCount).compactMap { d.page(at: $0)?.string }.joined(separator: "\n\n")
    }

    static func images(_ urls: [URL]) throws -> PDFDocument {
        let out = PDFDocument()
        for u in urls {
            guard let img = NSImage(contentsOf: u), let page = PDFPage(image: img) else {
                throw ToolError.open(u.lastPathComponent)
            }
            out.insert(page, at: out.pageCount)
        }
        return out
    }

    static func pngData(_ page: PDFPage, scale: CGFloat = 2) -> Data? {
        let box = page.bounds(for: .mediaBox)
        let size = NSSize(width: box.width * scale, height: box.height * scale)
        let img = page.thumbnail(of: size, for: .mediaBox)
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// مفتاح لون النص الذي يقرؤه CoreText مباشرة.
let ctColor = NSAttributedString.Key(kCTForegroundColorAttributeName as String)

// MARK: - خط عربي

enum ArabicFont {
    static func registerBundled() {
        for name in ["Amiri-Regular", "Amiri-Bold"] {
            let url = Bundle.main.url(forResource: name, withExtension: "ttf")
                ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent("Resources/\(name).ttf")
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func regular(size: CGFloat) -> NSFont {
        NSFont(name: "Amiri-Regular", size: size) ?? NSFont.systemFont(ofSize: size)
    }

    static func bold(size: CGFloat) -> NSFont {
        NSFont(name: "Amiri-Bold", size: size) ?? NSFont.boldSystemFont(ofSize: size)
    }
}

// MARK: - إخراج نص عربي إلى PDF

enum ArabicPDFWriter {
    /// يصف نصاً عربياً على صفحات A4 من اليمين لليسار، مع عنوان وشعار اختياري.
    static func make(title: String?, body: String, logo: NSImage? = nil) -> PDFDocument? {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 56

        let para = NSMutableParagraphStyle()
        para.alignment = .right
        para.baseWritingDirection = .rightToLeft
        para.lineSpacing = 6
        para.paragraphSpacing = 10

        let doc = NSMutableAttributedString()
        if let title, !title.isEmpty {
            let tp = para.mutableCopy() as! NSMutableParagraphStyle
            tp.paragraphSpacing = 18
            doc.append(NSAttributedString(string: title + "\n", attributes: [
                .font: ArabicFont.bold(size: 22), .paragraphStyle: tp, .foregroundColor: NSColor.black, ctColor: NSColor.black.cgColor,
            ]))
        }
        doc.append(NSAttributedString(string: body, attributes: [
            .font: ArabicFont.regular(size: 14), .paragraphStyle: para, .foregroundColor: NSColor.black, ctColor: NSColor.black.cgColor,
        ]))

        let data = NSMutableData()
        var media = page
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &media, nil) else { return nil }
        let setter = CTFramesetterCreateWithAttributedString(doc as CFAttributedString)
        var start = 0
        var first = true
        repeat {
            ctx.beginPDFPage(nil)
            var top = page.height - margin
            if first, let logo, let cg = logo.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let h: CGFloat = 48
                let w = h * CGFloat(cg.width) / CGFloat(max(cg.height, 1))
                ctx.draw(cg, in: CGRect(x: page.width - margin - w, y: top - h, width: w, height: h))
                top -= h + 16
            }
            first = false
            let frameRect = CGRect(x: margin, y: margin, width: page.width - margin * 2, height: top - margin)
            let path = CGPath(rect: frameRect, transform: nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: start, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            let visible = CTFrameGetVisibleStringRange(frame)
            ctx.endPDFPage()
            if visible.length == 0 { break }
            start += visible.length
        } while start < doc.length
        ctx.closePDF()
        return PDFDocument(data: data as Data)
    }
}
