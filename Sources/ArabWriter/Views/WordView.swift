import SwiftUI
import AppKit
import ArabWriterCore

/// معاينة نص منسّق (قراءة فقط) داخل الواجهة.
struct RichPreview: NSViewRepresentable {
    let text: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        if let tv = scroll.documentView as? NSTextView {
            tv.isEditable = false
            tv.isSelectable = true
            tv.drawsBackground = false
            tv.textContainerInset = NSSize(width: 8, height: 8)
            tv.baseWritingDirection = .rightToLeft
        }
        return scroll
    }

    func updateNSView(_ v: NSScrollView, context: Context) {
        guard let tv = v.documentView as? NSTextView else { return }
        if tv.attributedString() != text { tv.textStorage?.setAttributedString(text) }
    }
}

struct WordView: View {
    @State private var url: URL?
    @State private var doc = NSMutableAttributedString()
    @State private var version = 0
    @State private var report: LintReport?
    @State private var find = ""
    @State private var replace = ""
    @State private var working = false
    @State private var toast: Toast?
    @State private var settings = AppSettings.shared

    private let tint = Color.awIndigo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "وورد", subtitle: "دقّق ملفك وعدّله مع بقاء تنسيقه كما هو", symbol: "doc.richtext", tint: tint)
                if let url { editor(url) }
                else {
                    DropZone(title: "اسحب ملف وورد هنا", subtitle: "docx · doc · rtf · txt — أو اضغط للاختيار",
                             symbol: "doc.richtext", tint: tint, types: ["docx", "doc", "rtf", "txt", "md"]) { load($0[0]) }
                }
            }
            .padding(28)
        }
        .scrollContentBackground(.hidden)
        .toast($toast)
    }

    private func editor(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 10) {
                    Label(url.lastPathComponent, systemImage: "doc.fill")
                        .font(.headline).lineLimit(1)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .glassEffect(.regular.tint(tint.opacity(0.12)), in: .capsule)
                    Spacer()
                    Button("تدقيق آمن", systemImage: "checkmark.seal") { safeProof() }
                        .buttonStyle(.glass)
                    Button("إعادة صياغة ذكية", systemImage: "wand.and.stars") { aiRewrite() }
                        .buttonStyle(.glass).disabled(!settings.hasKey || working)
                    Button("اتجاه عربي", systemImage: "text.alignright") {
                        DocxService.forceRTL(doc); bump(); toast = Toast(text: "كل الفقرات صارت من اليمين")
                    }
                    .buttonStyle(.glass)
                    Menu {
                        Button("حفظ وورد", systemImage: "doc.richtext") { save("docx") }
                        Button("حفظ PDF", systemImage: "doc") { save("pdf") }
                        Button("حفظ نص", systemImage: "doc.plaintext") { save("txt") }
                    } label: { Label("حفظ", systemImage: "square.and.arrow.down") }
                    .menuStyle(.button).buttonStyle(.glassProminent).tint(tint).fixedSize()
                    Button("إغلاق", systemImage: "xmark") { self.url = nil; report = nil }
                        .labelStyle(.iconOnly).buttonStyle(.glass)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                GlassPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionLabel(text: "المستند", symbol: "doc.text")
                            Spacer()
                            if working { ProgressView().controlSize(.small) }
                            Text("\(ArabicLinter.words(doc.string).count) كلمة").font(.caption).foregroundStyle(.secondary)
                        }
                        RichPreview(text: doc)
                            .id(version)
                            .frame(minHeight: 460)
                            .background(.background.opacity(0.55), in: .rect(cornerRadius: 14))
                    }
                }
                VStack(spacing: 16) {
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(text: "بحث واستبدال", symbol: "magnifyingglass")
                            TextField("ابحث عن", text: $find).textFieldStyle(.roundedBorder)
                            TextField("استبدل بـ", text: $replace).textFieldStyle(.roundedBorder)
                            Button("استبدل الكل") {
                                let n = DocxService.replaceAll(doc, find: find, with: replace)
                                bump()
                                toast = Toast(text: n == 0 ? "ما لقيت «\(find)»" : "استُبدل \(n) موضع", isError: n == 0)
                            }
                            .buttonStyle(.glass).disabled(find.isEmpty)
                        }
                    }
                    GlassPanel(tint: (report?.isClean ?? true) ? .awGreen : .awPink) {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(text: "الفحص", symbol: "checklist")
                            if let report { ReportView(report: report) }
                            else { Text("اضغط «تدقيق آمن»").foregroundStyle(.secondary) }
                        }
                    }
                }
                .frame(width: 360)
            }
        }
    }

    private func bump() { version += 1 }

    private func load(_ u: URL) {
        do {
            doc = try DocxService.open(u)
            url = u
            report = ArabicLinter.check(doc.string, options: LintOptions(englishOnOwnLine: false))
            bump()
        } catch {
            toast = Toast(text: error.localizedDescription, isError: true)
        }
    }

    private func safeProof() {
        let n = ArabicLinter.fixPreservingFormat(doc)
        bump()
        report = ArabicLinter.check(doc.string, options: LintOptions(englishOnOwnLine: false))
        toast = Toast(text: n == 0 ? "ما فيه أخطاء آمنة للإصلاح" : "أُصلح \(n) موضع والتنسيق باقٍ")
    }

    private func aiRewrite() {
        let original = doc.string
        working = true
        Task {
            defer { working = false }
            do {
                let r = try await WritingEngine.run(WriteRequest(text: original, mode: .rewrite, register: .keep,
                                                                 platform: .none, words: nil))
                doc = NSMutableAttributedString(attributedString: DocxService.build(title: nil, body: r.text))
                report = r.report
                bump()
                toast = Toast(text: "أعيدت الصياغة. احفظ بنسخة جديدة حتى يبقى الأصل")
            } catch {
                toast = Toast(text: error.localizedDescription, isError: true)
            }
        }
    }

    private func save(_ ext: String) {
        let base = (url?.deletingPathExtension().lastPathComponent ?? "مستند") + " - مدقق"
        guard let out = Panels.save(name: base, ext: ext) else { return }
        do {
            switch ext {
            case "pdf":
                guard let d = ArabicPDFWriter.make(title: nil, body: doc.string) else { throw ToolError.write(out.lastPathComponent) }
                try PDFService.write(d, to: out)
            case "txt":
                try doc.string.write(to: out, atomically: true, encoding: .utf8)
            default:
                try DocxService.save(doc, to: out)
            }
            toast = Toast(text: "حُفظ «\(out.lastPathComponent)»")
        } catch {
            toast = Toast(text: error.localizedDescription, isError: true)
        }
    }
}
