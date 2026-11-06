import SwiftUI
import ArabWriterCore

struct StoryView: View {
    @State private var title = ""
    @State private var length: StoryLength = .short
    @State private var register: Register = .keep
    @State private var result: WriteResult?
    @State private var working = false
    @State private var toast: Toast?
    @State private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "القصة", subtitle: "اكتب عنواناً، ويطلع لك قصة قصيرة تُقرأ في أقل من دقيقتين",
                           symbol: "book.pages", tint: .awPurple)

                GlassPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("العنوان أو الفكرة… مثال: آخر رحلة قطار من الأحساء", text: $title)
                            .textFieldStyle(.plain)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .onSubmit(run)
                        Divider().opacity(0.4)
                        GlassEffectContainer(spacing: 12) {
                            HStack(spacing: 12) {
                                Picker("", selection: $length) {
                                    ForEach(StoryLength.allCases) { Text($0.rawValue).tag($0) }
                                }
                                .pickerStyle(.segmented).labelsHidden().frame(width: 300)
                                Picker("", selection: $register) {
                                    ForEach(Register.allCases) { Text($0 == .keep ? "حسب العنوان" : $0.rawValue).tag($0) }
                                }
                                .pickerStyle(.segmented).labelsHidden().frame(width: 260)
                                Spacer()
                                Button(action: run) {
                                    HStack(spacing: 8) {
                                        if working { ProgressView().controlSize(.small) } else { Image(systemName: "sparkles") }
                                        Text(working ? "يكتب…" : "اكتب القصة")
                                    }
                                    .font(.headline).padding(.horizontal, 8)
                                }
                                .buttonStyle(.glassProminent).controlSize(.large).tint(.awPurple)
                                .disabled(working || title.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        Text("\(length.range) كلمة").font(.caption).foregroundStyle(.secondary)
                    }
                }

                if !settings.hasKey {
                    Label("القصة تحتاج مفتاح Claude. أضفه من الإعدادات (⌘ ,)", systemImage: "key")
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular.tint(Color.awOrange.opacity(0.15)), in: .rect(cornerRadius: 16))
                }

                if let r = result {
                    GlassPanel(tint: .awPurple) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                SectionLabel(text: "القصة", symbol: "book")
                                Spacer()
                                Text("\(r.report.stats.words) كلمة").font(.caption).foregroundStyle(.secondary)
                                Button("نسخ", systemImage: "doc.on.doc") { Panels.copy(r.text); toast = Toast(text: "نُسخت القصة") }
                                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                                Button("PDF", systemImage: "square.and.arrow.down") { savePDF(r.text) }
                                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                            }
                            Text(r.text)
                                .font(.system(size: 18))
                                .lineSpacing(9)
                                .textSelection(.enabled)
                                .frame(maxWidth: 720, alignment: .leading)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(28)
            .animation(.smooth, value: result?.text)
        }
        .scrollContentBackground(.hidden)
        .toast($toast)
    }

    private func run() {
        guard !working, !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        working = true
        Task {
            defer { working = false }
            do { result = try await WritingEngine.story(title: title, length: length, register: register) }
            catch { toast = Toast(text: error.localizedDescription, isError: true) }
        }
    }

    private func savePDF(_ text: String) {
        guard let url = Panels.save(name: title.isEmpty ? "قصة" : title, ext: "pdf") else { return }
        var lines = text.components(separatedBy: "\n")
        let head = lines.isEmpty ? nil : lines.removeFirst()
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = ArabicPDFWriter.make(title: head, body: body), (try? PDFService.write(d, to: url)) != nil {
            toast = Toast(text: "حُفظت القصة PDF")
        } else {
            toast = Toast(text: "تعذّر الحفظ", isError: true)
        }
    }
}
