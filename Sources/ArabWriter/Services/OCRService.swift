import AppKit
import PDFKit
import Vision

/// قراءة النص من الصور وملفات PDF الممسوحة بمحرك التعرف على النصوص في الماك نفسه، بدون إنترنت.
enum OCRService {
    static func languages(for req: VNRecognizeTextRequest) -> [String]? {
        let supported = (try? req.supportedRecognitionLanguages()) ?? []
        let wanted = ["ar-SA", "ar", "en-US"].filter { supported.contains($0) }
        return wanted.contains(where: { $0.hasPrefix("ar") }) ? wanted : nil
    }

    static func recognize(_ image: CGImage) throws -> String {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        if let langs = languages(for: req) { req.recognitionLanguages = langs }
        else { req.automaticallyDetectsLanguage = true }

        try VNImageRequestHandler(cgImage: image, options: [:]).perform([req])
        let obs = req.results ?? []
        // من الأعلى للأسفل، وفي نفس السطر من اليمين لليسار
        let sorted = obs.sorted { a, b in
            let dy = a.boundingBox.midY - b.boundingBox.midY
            if abs(dy) > 0.012 { return dy > 0 }
            return a.boundingBox.minX > b.boundingBox.minX
        }
        var lines: [String] = []
        var lastY: CGFloat?
        for o in sorted {
            guard let s = o.topCandidates(1).first?.string else { continue }
            if let y = lastY, abs(y - o.boundingBox.midY) <= 0.012, !lines.isEmpty {
                lines[lines.count - 1] += " " + s
            } else {
                lines.append(s)
            }
            lastY = o.boundingBox.midY
        }
        return lines.joined(separator: "\n")
    }

    static func cgImage(_ page: PDFPage, scale: CGFloat = 2.5) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        let img = page.thumbnail(of: NSSize(width: box.width * scale, height: box.height * scale), for: .mediaBox)
        return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// يقرأ ملف PDF أو صورة. يعمل خارج الخيط الرئيسي.
    static func read(_ url: URL, progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            if url.pathExtension.lowercased() == "pdf" {
                guard let doc = PDFDocument(url: url) else { throw ToolError.open(url.lastPathComponent) }
                var pages: [String] = []
                for i in 0..<doc.pageCount {
                    progress(i + 1, doc.pageCount)
                    guard let p = doc.page(at: i), let cg = cgImage(p) else { continue }
                    let t = try recognize(cg)
                    if !t.isEmpty { pages.append(t) }
                }
                return pages.joined(separator: "\n\n")
            } else {
                guard let img = NSImage(contentsOf: url),
                      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    throw ToolError.open(url.lastPathComponent)
                }
                progress(1, 1)
                return try recognize(cg)
            }
        }.value
    }
}
