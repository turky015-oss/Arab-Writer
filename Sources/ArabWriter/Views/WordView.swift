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
                if let url { editor(url) }
                else {
                    FileHero(format: "DOCX", symbol: "doc.richtext", tint: tint,
                             headline: "دقّق ملف وورد بدون ما يخرب تنسيقه",
                             features: [
                                Feature(symbol: "checkmark.seal.fill", title: "تدقيق آمن", caption: "إملاء وترقيم ومسافات، والخطوط والألوان باقية"),
                                Feature(symbol: "wand.and.stars", title: "صياغة ذكية", caption: "يمسح بصمات الذكاء الاصطناعي من المستند كله"),
                                Feature(symbol: "magnifyingglass", title: "بحث واستبدال", caption: "يغيّر كلمة في كل المستند بضغطة"),
                                Feature(symbol: "text.alignright", title: "اتجاه عربي", caption: "يقلب الفقرات المعكوسة لليمين"),
                                Feature(symbol: "doc.fill", title: "تحويل إلى PDF", caption: "بخط أميري وترتيب عربي صحيح"),
                                Feature(symbol: "chart.bar.doc.horizontal", title: "تقرير الفحص", caption: "عدد الأخطاء والتنبيهات وموضع كل واحد"),
                             ],
                             dropTitle: "اسحب ملف وورد هنا", dropSubtitle: "docx · doc · rtf · txt — أو اضغط للاختيار",
                             types: ["docx", "doc", "rtf", "txt", "md"]) { load($0[0]) }
                }
            }
            .padding(28)
        }
        .scrollContentBackground(.hidden)
        .toast($toast)
    }

    private func editor(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                FormatBadge(label: "DOCX", symbol: "doc.richtext", tint: tint, size: 58)
                    .rotationEffect(.degrees(-6))
                    .hoverTilt(radius: 10, tilt: 14, glow: tint, sound: false)
                VStack(alignment: .leading, spacing: 3) {
                    Text(url.lastPathComponent).font(.title3.weight(.semibold)).lineLimit(1)
                    Text("\(ArabicLinter.words(doc.string).count) كلمة · \(doc.string.components(separatedBy: "\n").filter { !$0.isEmpty }.count) فقرة")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("إغلاق", systemImage: "xmark") { self.url = nil; report = nil }
                    .labelStyle(.iconOnly).buttonStyle(.glass).controlSize(.large)
            }

            GlassEffectContainer(spacing: 10) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                    ActionTile(title: "تدقيق آمن", symbol: "checkmark.seal.fill", tint: .awGreen) { safeProof() }
                    ActionTile(title: "صياغة ذكية", symbol: "wand.and.stars", tint: .awPurple,
                               disabled: !settings.hasKey || working) { aiRewrite() }
                    ActionTile(title: "اتجاه عربي", symbol: "text.alignright", tint: .awBlue) {
                        DocxService.forceRTL(doc); bump(); toast = Toast(text: "كل الفقرات صارت من اليمين")
                    }
                    ActionTile(title: "حفظ وورد", symbol: "doc.richtext.fill", tint: tint) { save("docx") }
                    ActionTile(title: "حفظ PDF", symbol: "doc.fill", tint: .awPink) { save("pdf") }
                    ActionTile(title: "حفظ نص", symbol: "doc.plaintext.fill", tint: .gray) { save("txt") }
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
