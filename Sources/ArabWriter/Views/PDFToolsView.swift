import SwiftUI
import AppKit
import PDFKit
import ArabWriterCore

struct PDFPreview: NSViewRepresentable {
    let document: PDFDocument?

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displaysPageBreaks = true
        v.backgroundColor = .clear
        return v
    }

    func updateNSView(_ v: PDFView, context: Context) {
        if v.document !== document { v.document = document }
    }
}

enum PDFTool: String, CaseIterable, Identifiable {
    case merge, split, extract, delete, reorder, watermark, number, protect, compress, toImages, fromImages, text, summarize
    var id: String { rawValue }

    var title: String {
        switch self {
        case .merge: return "دمج"
        case .split: return "تقسيم"
        case .extract: return "استخراج صفحات"
        case .delete: return "حذف صفحات"
        case .reorder: return "ترتيب الصفحات"
        case .watermark: return "علامة مائية"
        case .number: return "ترقيم"
        case .protect: return "حماية"
        case .compress: return "ضغط"
        case .toImages: return "إلى صور"
        case .fromImages: return "صور إلى PDF"
        case .text: return "استخراج النص"
        case .summarize: return "تلخيص ذكي"
        }
    }

    var symbol: String {
        switch self {
        case .merge: return "square.stack.3d.down.right"
        case .split: return "square.split.2x1"
        case .extract: return "doc.on.doc"
        case .delete: return "trash"
        case .reorder: return "arrow.up.arrow.down"
        case .watermark: return "drop"
        case .number: return "number"
        case .protect: return "lock"
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .toImages: return "photo.on.rectangle"
        case .fromImages: return "photo.stack"
        case .text: return "text.quote"
        case .summarize: return "sparkles"
        }
    }

    var needsPDF: Bool { self != .fromImages }
}

struct PDFToolsView: View {
    @State private var files: [URL] = []
    @State private var active: PDFDocument?
    @State private var activeURL: URL?
    @State private var tool: PDFTool = .merge
    @State private var pages = ""
    @State private var stampText = "سري"
    @State private var password = ""
    @State private var numberStyle: PDFService.NumberStyle = .arabic
    @State private var summaryWords = 250
    @State private var logo: NSImage?
    @State private var output = ""
    @State private var working = false
    @State private var toast: Toast?
    @State private var settings = AppSettings.shared

    private let tint = Color.awPink
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "PDF", subtitle: "دمج وتقسيم وحماية وتلخيص، كله على جهازك", symbol: "doc.on.doc", tint: tint)

                GlassPanel {
                    GlassEffectContainer(spacing: 10) {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(PDFTool.allCases) { t in
                                Button { withAnimation(.smooth) { tool = t; output = "" } } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: t.symbol).font(.system(size: 18, weight: .medium))
                                        Text(t.title).font(.caption.weight(.medium)).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 58)
                                    .foregroundStyle(tool == t ? .white : .primary)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .glassEffect(tool == t ? Glass.regular.tint(tint).interactive() : Glass.regular.interactive(),
                                             in: .rect(cornerRadius: 16))
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        if files.isEmpty {
                            DropZone(title: tool == .fromImages ? "اسحب الصور هنا" : "اسحب ملفات PDF هنا",
                                     subtitle: tool == .fromImages ? "png · jpg · heic — بالترتيب" : "ملف واحد أو أكثر — أو اضغط للاختيار",
                                     symbol: tool == .fromImages ? "photo.stack" : "doc.badge.plus", tint: tint,
                                     types: tool == .fromImages ? ["png", "jpg", "jpeg", "heic", "tiff"] : ["pdf"],
                                     multiple: true) { add($0) }
                        } else {
                            fileList
                            GlassPanel(radius: 22) {
                                PDFPreview(document: active).frame(minHeight: 420)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    inspector.frame(width: 320)
                }
            }
            .padding(28)
        }
        .scrollContentBackground(.hidden)
        .toast($toast)
    }

    // MARK: الملفات

    private var fileList: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel(text: "الملفات (\(files.count))", symbol: "folder")
                    Spacer()
                    Button("إضافة", systemImage: "plus") {
                        let types = tool == .fromImages ? ["png", "jpg", "jpeg", "heic", "tiff"] : ["pdf"]
                        if let u = Panels.open(types: types, multiple: true) { add(u) }
                    }
                    .buttonStyle(.borderless)
                    Button("مسح", systemImage: "xmark") { files = []; active = nil; activeURL = nil; output = "" }
                        .buttonStyle(.borderless)
                }
                ForEach(Array(files.enumerated()), id: \.element) { i, u in
                    HStack(spacing: 8) {
                        Image(systemName: u.pathExtension.lowercased() == "pdf" ? "doc.fill" : "photo")
                            .foregroundStyle(tint)
                        Text(u.lastPathComponent).lineLimit(1)
                        if let d = PDFDocument(url: u) { Text("\(d.pageCount) ص").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button { move(i, -1) } label: { Image(systemName: "chevron.up") }.disabled(i == 0)
                        Button { move(i, 1) } label: { Image(systemName: "chevron.down") }.disabled(i == files.count - 1)
                        Button { files.remove(at: i); if files.isEmpty { active = nil } } label: { Image(systemName: "minus.circle") }
                    }
                    .buttonStyle(.borderless)
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .background(u == activeURL ? tint.opacity(0.12) : .clear, in: .rect(cornerRadius: 10))
                    .contentShape(.rect)
                    .onTapGesture { select(u) }
                }
            }
        }
    }

    // MARK: لوحة الأداة

    private var inspector: some View {
        GlassPanel(tint: tint) {
            VStack(alignment: .leading, spacing: 14) {
                Label(tool.title, systemImage: tool.symbol).font(.title3.weight(.semibold))
                Text(help).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                switch tool {
                case .extract, .delete, .reorder:
                    TextField(tool == .reorder ? "مثال: 3، 1، 2" : "مثال: 1-3، 5", text: $pages)
                        .textFieldStyle(.roundedBorder)
                case .watermark:
                    TextField("نص العلامة", text: $stampText).textFieldStyle(.roundedBorder)
                case .number:
                    Picker("", selection: $numberStyle) {
                        ForEach(PDFService.NumberStyle.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                case .protect:
                    SecureField("كلمة المرور", text: $password).textFieldStyle(.roundedBorder)
                case .summarize:
                    Stepper(value: $summaryWords, in: 80...1200, step: 50) { Text("\(summaryWords) كلمة").monospacedDigit() }
                    HStack {
                        Button(logo == nil ? "إضافة شعار" : "تغيير الشعار", systemImage: "photo") {
                            if let u = Panels.open(types: ["png", "jpg", "jpeg"])?.first { logo = NSImage(contentsOf: u) }
                        }
                        .buttonStyle(.glass)
                        if logo != nil {
                            Button("حذف", systemImage: "xmark") { logo = nil }.labelStyle(.iconOnly).buttonStyle(.glass)
                        }
                    }
                    if !settings.hasKey {
                        Label("يحتاج مفتاح Claude", systemImage: "key").font(.caption).foregroundStyle(Color.awOrange)
                    }
                default: EmptyView()
                }

                Button(action: run) {
                    HStack {
                        if working { ProgressView().controlSize(.small) } else { Image(systemName: "play.fill") }
                        Text(working ? "يشتغل…" : "نفّذ")
                    }
                    .frame(maxWidth: .infinity)
                    .font(.headline)
                }
                .buttonStyle(.glassProminent).controlSize(.large).tint(tint)
                .disabled(working || files.isEmpty || (tool == .summarize && !settings.hasKey))

                if !output.isEmpty {
                    Divider().opacity(0.4)
                    HStack {
                        SectionLabel(text: "الناتج", symbol: "text.alignright")
                        Spacer()
                        Button("نسخ", systemImage: "doc.on.doc") { Panels.copy(output); toast = Toast(text: "نُسخ") }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                    }
                    ScrollView {
                        Text(output).font(.callout).lineSpacing(4).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 280)
                }
            }
        }
    }

    private var help: String {
        switch tool {
        case .merge: return "يدمج الملفات بالترتيب الظاهر في القائمة."
        case .split: return "يحفظ كل صفحة من الملف المحدد كملف مستقل في مجلد تختاره."
        case .extract: return "يحفظ الصفحات المحددة في ملف جديد."
        case .delete: return "يحذف الصفحات المحددة ويحفظ نسخة جديدة."
        case .reorder: return "اكتب الترتيب الجديد للصفحات كلها."
        case .watermark: return "يكتب نصاً عربياً شفافاً بالمائل على كل صفحة."
        case .number: return "يضيف رقم الصفحة أسفل كل صفحة."
        case .protect: return "يقفل الملف بكلمة مرور عند الفتح."
        case .compress: return "يصغّر حجم الصور داخل الملف."
        case .toImages: return "يحفظ كل صفحة صورة PNG بدقة عالية."
        case .fromImages: return "يجمع الصور في ملف PDF واحد بالترتيب."
        case .text: return "يطلع النص من الملف المحدد (الملفات الممسوحة ضوئياً ما فيها نص)."
        case .summarize: return "يلخّص الملف بالعربية ويخرج PDF عربي مرتب، مع شعارك إن أضفته."
        }
    }

    // MARK: العمليات

    private func add(_ urls: [URL]) {
        for u in urls where !files.contains(u) { files.append(u) }
        if activeURL == nil, let f = files.first { select(f) }
    }

    private func select(_ u: URL) {
        activeURL = u
        active = u.pathExtension.lowercased() == "pdf" ? PDFDocument(url: u) : (try? PDFService.images([u]))
    }

    private func move(_ i: Int, _ d: Int) {
        let j = i + d
        guard files.indices.contains(j) else { return }
        files.swapAt(i, j)
    }

    private func baseName(_ suffix: String) -> String {
        ((activeURL ?? files.first)?.deletingPathExtension().lastPathComponent ?? "ملف") + " - " + suffix
    }

    private func saveDoc(_ d: PDFDocument, _ suffix: String, password: String? = nil, compress: Bool = false) throws {
        guard let out = Panels.save(name: baseName(suffix), ext: "pdf") else { return }
        try PDFService.write(d, to: out, password: password, compress: compress)
        toast = Toast(text: "حُفظ «\(out.lastPathComponent)» · \(d.pageCount) صفحة")
        Panels.reveal(out)
    }

    private func run() {
        do {
            let pdfs = files.filter { $0.pathExtension.lowercased() == "pdf" }
            let src: PDFDocument? = {
                if let u = activeURL, u.pathExtension.lowercased() == "pdf" { return PDFDocument(url: u) }
                return pdfs.first.flatMap { PDFDocument(url: $0) }
            }()
            if tool.needsPDF && src == nil { throw ToolError.invalid("أضف ملف PDF أولاً.") }

            switch tool {
            case .merge:
                guard pdfs.count >= 2 else { throw ToolError.invalid("الدمج يحتاج ملفين أو أكثر.") }
                try saveDoc(try PDFService.merge(pdfs), "مدمج")
            case .split:
                guard let d = src, let dir = Panels.folder() else { return }
                for (i, part) in PDFService.split(d).enumerated() {
                    try PDFService.write(part, to: dir.appendingPathComponent(baseName("صفحة \(i + 1)") + ".pdf"))
                }
                toast = Toast(text: "قُسّم إلى \(d.pageCount) ملف")
                Panels.reveal(dir)
            case .extract:
                let d = src!
                try saveDoc(PDFService.pick(d, pages: try PDFService.parsePages(pages, count: d.pageCount)), "مستخرج")
            case .delete:
                let d = src!
                try saveDoc(PDFService.delete(d, pages: try PDFService.parsePages(pages, count: d.pageCount)), "بعد الحذف")
            case .reorder:
                let d = src!
                let order = try PDFService.parsePages(pages, count: d.pageCount)
                guard Set(order).count == d.pageCount else {
                    throw ToolError.invalid("اكتب كل الصفحات (\(d.pageCount)) مرة واحدة بالترتيب الجديد.")
                }
                try saveDoc(PDFService.pick(d, pages: order), "مرتب")
            case .watermark:
                guard !stampText.isEmpty else { throw ToolError.invalid("اكتب نص العلامة.") }
                try saveDoc(try PDFService.watermark(src!, text: stampText), "علامة مائية")
            case .number:
                try saveDoc(try PDFService.number(src!, style: numberStyle), "مرقم")
            case .protect:
                guard password.count >= 4 else { throw ToolError.invalid("كلمة المرور 4 خانات على الأقل.") }
                try saveDoc(src!, "محمي", password: password)
            case .compress:
                try saveDoc(src!, "مضغوط", compress: true)
            case .toImages:
                guard let dir = Panels.folder() else { return }
                let d = src!
                for i in 0..<d.pageCount {
                    if let p = d.page(at: i), let png = PDFService.pngData(p) {
                        try png.write(to: dir.appendingPathComponent(baseName("\(i + 1)") + ".png"))
                    }
                }
                toast = Toast(text: "حُفظت \(d.pageCount) صورة")
                Panels.reveal(dir)
            case .fromImages:
                let imgs = files.filter { $0.pathExtension.lowercased() != "pdf" }
                guard !imgs.isEmpty else { throw ToolError.invalid("أضف صوراً أولاً.") }
                try saveDoc(try PDFService.images(imgs), "صور")
            case .text:
                let t = PDFService.text(src!).trimmingCharacters(in: .whitespacesAndNewlines)
                output = t.isEmpty ? "ما فيه نص قابل للنسخ. الملف غالباً صور ممسوحة." : t
            case .summarize:
                let t = PDFService.text(src!)
                guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ToolError.invalid("ما فيه نص في الملف ألخّصه.")
                }
                summarize(t)
            }
        } catch {
            toast = Toast(text: error.localizedDescription, isError: true)
        }
    }

    private func summarize(_ text: String) {
        working = true
        Task {
            defer { working = false }
            do {
                let s = try await WritingEngine.summarize(text, words: summaryWords)
                output = s
                var lines = s.components(separatedBy: "\n")
                let head = lines.isEmpty ? nil : lines.removeFirst()
                let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if let d = ArabicPDFWriter.make(title: head, body: body, logo: logo) {
                    try saveDoc(d, "ملخص")
                }
            } catch {
                toast = Toast(text: error.localizedDescription, isError: true)
            }
        }
    }
}
