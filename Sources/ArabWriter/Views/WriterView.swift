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
    @State private var live = ""
    @State private var inbox = Inbox.shared
    @State private var toast: Toast?
    @State private var settings = AppSettings.shared
    @Namespace private var glass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HeroHeader(badge: "نص", symbol: "wand.and.stars", tint: .awBlue,
                           headline: "اكتب بصوت إنسان", subline: mode.hint)
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
        .onChange(of: inbox.text, initial: true) {
            if let t = inbox.text {
                input = t
                result = nil
                inbox.text = nil
                toast = Toast(text: "وصل النص، اختر المهمة واضغط نفّذ")
            }
        }
    }

    // MARK: الأدوات

    private var controls: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                GlassPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "المهمة", symbol: "target")
                        GlassEffectContainer(spacing: 8) {
                            HStack(spacing: 8) {
                                ForEach(WriteMode.allCases) { m in
                                    ActionTile(title: m.rawValue, symbol: m.symbol, tint: .awBlue, selected: mode == m) {
                                        withAnimation(.smooth) { mode = m }
                                    }
                                }
                            }
                        }
                    }
                }
                GlassPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "السجل", symbol: "text.bubble")
                        GlassEffectContainer(spacing: 8) {
                            HStack(spacing: 8) {
                                ForEach(Register.allCases) { r in
                                    ActionTile(title: r.rawValue, symbol: r.symbol, tint: .awTeal, selected: register == r) {
                                        withAnimation(.smooth) { register = r }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "المنصة", symbol: "square.grid.2x2")
                    GlassEffectContainer(spacing: 8) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 10) {
                            ForEach(Platform.allCases) { p in
                                PlatformTile(platform: p, selected: platform == p) {
                                    withAnimation(.smooth) { platform = p }
                                }
                            }
                        }
                    }
                }
            }

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 10) {
                    ActionTile(title: "قفل الطول", symbol: "ruler", tint: .awOrange, selected: lockLength) {
                        withAnimation(.smooth) { lockLength.toggle() }
                    }
                    .frame(width: 110)
                    if lockLength {
                        Stepper(value: $words, in: 10...1000, step: 10) {
                            Text("\(words) كلمة").font(.headline).monospacedDigit()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .glassEffect(.regular, in: .capsule)
                        .glassEffectID("len", in: glass)
                        .transition(.scale.combined(with: .opacity))
                    }
                    Spacer()
                    Button(action: run) {
                        HStack(spacing: 10) {
                            if working { ProgressView().controlSize(.small) }
                            else { Image(systemName: "sparkles").symbolEffect(.pulse, isActive: !input.isEmpty) }
                            Text(working ? "يشتغل…" : "نفّذ")
                        }
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 22).padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.extraLarge)
                    .tint(.awBlue)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(working || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .hoverTilt(radius: 30, tilt: 6, glow: .white, sound: false)
                }
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
                            SoundFX.play(.copy)
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
                    if working && !live.isEmpty {
                        LiveText(text: live, tint: .awBlue)
                    } else if working {
                        VStack(spacing: 14) {
                            ProgressView()
                            Text(settings.hasKey ? "يتصل بـ Claude…" : "يصلح ويفحص…").foregroundStyle(.secondary)
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
                        VStack(alignment: .leading, spacing: 12) {
                            FeatureGrid(features: [
                                Feature(symbol: "eraser.fill", title: "يمسح البصمات", caption: "«في عالم اليوم» و«يلعب دوراً» وأخواتها"),
                                Feature(symbol: "character.textbox", title: "يدقق اللغة", caption: "الهمزات والتاء والترقيم والنحو الشائع"),
                                Feature(symbol: "lock.shield.fill", title: "لا يختلق", caption: "أي رقم أو اسم جديد ينكشف ويتعلّم عليه"),
                                Feature(symbol: "arrow.left.arrow.right", title: "يوريك الفرق", caption: "كل كلمة تغيّرت عن الأصل"),
                            ], tint: .awBlue, minimum: 200)
                            Text("⌘ + Return للتنفيذ").font(.caption).foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                        }
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
        SoundFX.play(.start)
        let req = WriteRequest(text: input, mode: mode, register: register, platform: platform,
                               words: lockLength ? words : nil)
        working = true
        showDiff = false
        Task {
            defer { working = false }
            do {
                live = ""
                result = try await WritingEngine.run(req) { live = $0 }
                live = ""
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

extension Register {
    var symbol: String {
        switch self {
        case .keep: return "equal.circle"
        case .saudi: return "bubble.left.and.text.bubble.right.fill"
        case .fusha: return "book.closed.fill"
        }
    }
}

extension Platform {
    /// الألوان الرسمية للمنصات.
    var colors: [Color] {
        switch self {
        case .none: return [Color(white: 0.55), Color(white: 0.4)]
        case .x: return [Color(white: 0.18), .black]
        case .instagram: return [Color(red: 0.99, green: 0.69, blue: 0.27), Color(red: 0.99, green: 0.11, blue: 0.47), Color(red: 0.51, green: 0.23, blue: 0.71)]
        case .linkedin: return [Color(red: 0.04, green: 0.4, blue: 0.76), Color(red: 0.0, green: 0.3, blue: 0.6)]
        case .whatsapp: return [Color(red: 0.15, green: 0.83, blue: 0.4), Color(red: 0.07, green: 0.55, blue: 0.49)]
        case .official: return [Color(red: 0.12, green: 0.2, blue: 0.4), Color(red: 0.75, green: 0.6, blue: 0.25)]
        case .script: return [.awOrange, .awPink]
        }
    }
    var tint: Color { colors[colors.count / 2] }
}

/// مربع منصة: أيقونة على تدرج لونها الرسمي، والاسم ونوع المحتوى تحتها.
struct PlatformTile: View {
    let platform: Platform
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            SoundFX.play(.tap)
            action()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: platform.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: platform.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: selected)
                }
                .frame(width: 40, height: 40)
                .shadow(color: platform.tint.opacity(0.4), radius: 5, y: 3)
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white, platform.tint)
                            .offset(x: 6, y: -6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(platform.rawValue).font(.callout.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Text(platform.caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? Glass.regular.tint(platform.tint.opacity(0.35)).interactive() : Glass.regular.interactive(),
                     in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(platform.tint.opacity(selected ? 0.8 : 0), lineWidth: 2))
        .hoverTilt(radius: 18, tilt: 9, glow: platform.tint)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: selected)
    }
}
