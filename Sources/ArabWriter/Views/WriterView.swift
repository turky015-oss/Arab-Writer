import SwiftUI
import AppKit
import ArabWriterCore

struct WriterView: View {
    @State private var input = ""
    @State private var mode: WriteMode = .rewrite
    @State private var register: Register = .keep
    @State private var platform: Platform = .none
    @State private var lockLength = false
    @State private var words = 60
    @State private var result: WriteResult?
    @State private var working = false
    @State private var showDiff = false
    @State private var toast: Toast?
    @State private var settings = AppSettings.shared
    @Namespace private var glass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "الكتابة", subtitle: mode.hint, symbol: "wand.and.stars", tint: .awBlue)
                controls
                HStack(alignment: .top, spacing: 16) {
                    inputPanel
                    outputPanel
                }
                .frame(minHeight: 380)
                if let r = result {
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(text: "تقرير الفحص", symbol: "checklist")
                            ReportView(report: r.report)
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

    // MARK: الأدوات

    private var controls: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 12) {
                Picker("", selection: $mode) {
                    ForEach(WriteMode.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 270)

                Menu {
                    Picker("السجل", selection: $register) {
                        ForEach(Register.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("السجل: \(register.rawValue)", systemImage: "text.bubble")
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .fixedSize()

                Menu {
                    Picker("المنصة", selection: $platform) {
                        ForEach(Platform.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(platform == .none ? "المنصة" : platform.rawValue, systemImage: platform.symbol)
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .fixedSize()

                HStack(spacing: 8) {
                    Toggle(isOn: $lockLength.animation(.smooth)) {
                        Label("قفل الطول", systemImage: "ruler")
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.glass)
                    if lockLength {
                        Stepper(value: $words, in: 10...1000, step: 10) {
                            Text("\(words) كلمة").monospacedDigit()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                        .glassEffectID("len", in: glass)
                    }
                }

                Spacer()

                Button(action: run) {
                    HStack(spacing: 8) {
                        if working { ProgressView().controlSize(.small) }
                        else { Image(systemName: "sparkles") }
                        Text(working ? "يشتغل…" : "نفّذ")
                    }
                    .font(.headline)
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(.awBlue)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(working || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var inputPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(text: mode == .write ? "الفكرة" : "النص الأصلي", symbol: "text.alignright")
                    Spacer()
                    Text("\(ArabicLinter.words(input).count) كلمة").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Button("لصق", systemImage: "doc.on.clipboard") {
                        if let s = NSPasteboard.general.string(forType: .string) { input = s }
                    }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    Button("مسح", systemImage: "xmark.circle") { input = ""; result = nil }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                        .disabled(input.isEmpty)
                }
                ArabicEditor(text: $input, placeholder: mode == .write
                             ? "اكتب فكرتك هنا… مثال: تطبيق جديد يرتب مواعيد الصيدلية"
                             : "الصق النص هنا…")
                    .frame(minHeight: 320)
            }
        }
    }

    private var outputPanel: some View {
        GlassPanel(tint: .awBlue) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(text: "النتيجة", symbol: "sparkles")
                    if let r = result, !r.usedAI {
                        Text("إصلاح آلي فقط").font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.awOrange.opacity(0.18), in: .capsule)
                    }
                    Spacer()
                    if let r = result {
                        Toggle(isOn: $showDiff) { Label("التغييرات", systemImage: "arrow.left.arrow.right") }
                            .toggleStyle(.button).buttonStyle(.borderless)
                            .help("التشابه مع الأصل \(r.similarity)%")
                        Button("نسخ", systemImage: "doc.on.doc") {
                            Panels.copy(r.text)
                            toast = Toast(text: "نُسخ النص")
                        }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                        Menu {
                            Button("مستند وورد", systemImage: "doc.richtext") { export(r.text, "docx") }
                            Button("ملف PDF", systemImage: "doc") { export(r.text, "pdf") }
                            Button("نص عادي", systemImage: "doc.plaintext") { export(r.text, "txt") }
                        } label: { Image(systemName: "square.and.arrow.up") }
                        .menuStyle(.borderlessButton).fixedSize()
                    }
                }
                Group {
                    if working {
                        VStack(spacing: 14) {
                            ProgressView()
                            Text(settings.hasKey ? "يكتب ويدقق ويفحص…" : "يصلح ويفحص…").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let r = result {
                        if showDiff { diffList(r) }
                        else {
                            VStack(alignment: .leading, spacing: 12) {
                                ArabicEditor(text: .constant(r.text), placeholder: "", editable: false)
                                if let q = r.question {
                                    Label(q, systemImage: "questionmark.bubble")
                                        .font(.callout)
                                        .padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .glassEffect(.regular.tint(Color.awOrange.opacity(0.15)), in: .rect(cornerRadius: 14))
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "text.badge.checkmark").font(.system(size: 36, weight: .light))
                                .foregroundStyle(Color.awBlue.opacity(0.7))
                            Text("النتيجة تظهر هنا").foregroundStyle(.secondary)
                            Text("⌘ + Return للتنفيذ").font(.caption).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minHeight: 320)
            }
        }
    }

    private func diffList(_ r: WriteResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("التشابه مع الأصل \(r.similarity)% · \(r.changes.count) تغيير")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(r.changes) { c in
                    HStack(alignment: .top, spacing: 8) {
                        Text(c.op.rawValue).font(.caption.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.awBlue.opacity(0.14), in: .capsule)
                        VStack(alignment: .leading, spacing: 2) {
                            if !c.before.isEmpty { Text(c.before).strikethrough().foregroundStyle(Color.awPink) }
                            if !c.after.isEmpty { Text(c.after).foregroundStyle(Color.awGreen) }
                        }
                        .font(.callout)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: التنفيذ

    private func run() {
        let req = WriteRequest(text: input, mode: mode, register: register, platform: platform,
                               words: lockLength ? words : nil)
        working = true
        showDiff = false
        Task {
            defer { working = false }
            do {
                result = try await WritingEngine.run(req)
                if !settings.hasKey { toast = Toast(text: "أصلحتُ الآمن آلياً. أضف مفتاحك لإعادة الصياغة الكاملة") }
            } catch {
                toast = Toast(text: error.localizedDescription, isError: true)
            }
        }
    }

    private func export(_ text: String, _ ext: String) {
        guard let url = Panels.save(name: "Arab Writer", ext: ext) else { return }
        do {
            switch ext {
            case "docx": try DocxService.save(DocxService.build(title: nil, body: text), to: url)
            case "pdf":
                guard let d = ArabicPDFWriter.make(title: nil, body: text) else { throw ToolError.write(url.lastPathComponent) }
                try PDFService.write(d, to: url)
            default: try text.write(to: url, atomically: true, encoding: .utf8)
            }
            toast = Toast(text: "حُفظ «\(url.lastPathComponent)»")
        } catch {
            toast = Toast(text: error.localizedDescription, isError: true)
        }
    }
}
