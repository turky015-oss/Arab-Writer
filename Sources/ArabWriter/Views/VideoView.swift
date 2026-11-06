import SwiftUI
import AppKit
import ArabWriterCore

struct VideoView: View {
    @State private var input = ""
    @State private var seconds = 10
    @State private var style = "3D Pixar"
    @State private var audio = "موسيقى ومؤثرات بلا حوار"
    @State private var hero = "بلا بطل محدد"
    @State private var platform = "ريلز وشورتس"
    @State private var plan: VideoPlan?
    @State private var working = false
    @State private var progressText = ""
    @State private var toast: Toast?
    @State private var settings = AppSettings.shared

    private let tint = Color.awOrange
    private let shotColors: [Color] = [.awOrange, .awPink, .awPurple, .awBlue, .awTeal, .awGreen, .awIndigo]

    private let durations: [(Int, String)] = [(8, "8 ث"), (10, "10 ث"), (15, "15 ث"), (30, "30 ث")]
    private let styles: [(String, String, String)] = [
        ("3D Pixar", "3D بكسار", "cube.fill"), ("Cinematic realism", "واقعي سينمائي", "camera.aperture"),
        ("Anime", "أنمي", "sparkles"), ("Motion graphics", "موشن جرافيك", "square.stack.3d.forward.dottedline.fill"),
    ]
    private let audios: [(String, String, String)] = [
        ("موسيقى ومؤثرات بلا حوار", "موسيقى فقط", "music.note"),
        ("حوار عربي منطوق", "حوار عربي", "bubble.left.and.bubble.right.fill"),
        ("تعليق صوتي", "تعليق صوتي", "mic.fill"),
    ]
    private let heroes: [(String, String, String)] = [
        ("بلا بطل محدد", "بدون بطل", "person.slash"),
        ("الخيار أ: شاب سعودي 3D Pixar، ثوب أبيض، شماغ أحمر وعقال أسود، نظارة سوداء سميكة، لحية مهذبة، AirPods", "بشماغ", "person.fill"),
        ("الخيار ب: شاب سعودي 3D Pixar، ثوب أبيض، بلا شماغ، نظارة سوداء سميكة، لحية مهذبة، AirPods", "بدون شماغ", "person"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HeroHeader(badge: "فيديو", symbol: "film.stack", tint: tint,
                           headline: "من النص إلى فيديو",
                           subline: "سكربت مقطّع بالثواني، وبرومبت جاهز لكل مقطع، وحزمة كابشن")

                GlassPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionLabel(text: "النص أو الفكرة", symbol: "text.alignright")
                            Spacer()
                            Text("\(ArabicLinter.words(input).count) كلمة · تقريباً \(max(1, Int(Double(ArabicLinter.words(input).count) / 2.5))) ث قراءة")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("لصق", systemImage: "doc.on.clipboard") {
                                if let s = NSPasteboard.general.string(forType: .string) { input = s }
                            }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                        }
                        ArabicEditor(text: $input, placeholder: "الصق السكربت أو اكتب الفكرة… مثال: شاب يحاول يطبخ كبسة أول مرة ويحترق الرز")
                            .frame(minHeight: 140)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                    optionPanel("المدة", "timer") {
                        ForEach(durations, id: \.0) { d in
                            ActionTile(title: d.1, symbol: "clock", tint: tint, selected: seconds == d.0) { seconds = d.0 }
                        }
                    }
                    optionPanel("الأسلوب", "paintpalette") {
                        ForEach(styles, id: \.0) { s in
                            ActionTile(title: s.1, symbol: s.2, tint: .awPurple, selected: style == s.0) { style = s.0 }
                        }
                    }
                    optionPanel("الصوت", "speaker.wave.2") {
                        ForEach(audios, id: \.0) { a in
                            ActionTile(title: a.1, symbol: a.2, tint: .awBlue, selected: audio == a.0) { audio = a.0 }
                        }
                    }
                    optionPanel("البطل", "person.crop.square") {
                        ForEach(heroes, id: \.0) { h in
                            ActionTile(title: h.1, symbol: h.2, tint: .awGreen, selected: hero == h.0) { hero = h.0 }
                        }
                    }
                }

                HStack {
                    if working {
                        Label(progressText.isEmpty ? "يتصل بـ Claude…" : progressText, systemImage: "film")
                            .foregroundStyle(.secondary).symbolEffect(.pulse, isActive: true)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    Button(action: run) {
                        HStack(spacing: 10) {
                            if working { ProgressView().controlSize(.small) } else { Image(systemName: "film.stack.fill") }
                            Text(working ? "يجهّز…" : "جهّز الحزمة")
                        }
                        .font(.title3.weight(.semibold)).padding(.horizontal, 22).padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent).controlSize(.extraLarge).tint(tint)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(working || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !settings.aiAvailable)
                    .hoverTilt(radius: 30, tilt: 6, glow: .white, sound: false)
                }

                if !settings.aiAvailable {
                    Label("الفيديو يحتاج المحرّك الذكي. أضف مفتاح Claude من الإعدادات (⌘ ,)", systemImage: "key")
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular.tint(Color.awOrange.opacity(0.15)), in: .rect(cornerRadius: 16))
                }

                if let plan { planView(plan).transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            .padding(28)
            .animation(.smooth, value: plan?.text)
        }
        .scrollContentBackground(.hidden)
        .toast($toast)
    }

    private func optionPanel<C: View>(_ title: String, _ symbol: String, @ViewBuilder _ tiles: () -> C) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: title, symbol: symbol)
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) { tiles() }
                }
            }
        }
    }

    // MARK: الحزمة

    @ViewBuilder
    private func planView(_ p: VideoPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("الحزمة").font(.title2.weight(.bold))
                let ok = abs(p.totalSeconds - Double(seconds)) < 0.01
                Label(ok ? "المدة مضبوطة \(seconds) ث" : "المجموع \(SheetService.format(p.totalSeconds)) ث من \(seconds)",
                      systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(ok ? Color.awGreen : Color.awOrange)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassEffect(.regular, in: .capsule)
                Spacer()
                Button {
                    Panels.copy(p.packageText); SoundFX.play(.copy); toast = Toast(text: "نُسخت الحزمة كاملة")
                } label: { Label("انسخ الحزمة", systemImage: "doc.on.doc.fill") }
                .buttonStyle(.glassProminent).tint(tint)
            }

            // شريط الزمن: كل لقطة بعرض ثوانيها
            GlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "الخط الزمني", symbol: "timeline.selection")
                    GeometryReader { geo in
                        let total = max(p.totalSeconds, 1)
                        HStack(spacing: 3) {
                            ForEach(Array(p.shots.enumerated()), id: \.element.id) { i, s in
                                let c = shotColors[i % shotColors.count]
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(c.gradient)
                                    .overlay(Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(.white))
                                    .frame(width: max(18, (geo.size.width - CGFloat(p.shots.count) * 3) * CGFloat(s.seconds / total)))
                                    .help(s.action)
                            }
                        }
                    }
                    .frame(height: 34)
                    .environment(\.layoutDirection, .rightToLeft)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(p.shots.enumerated()), id: \.element.id) { i, s in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(SheetService.format(s.seconds)) ث")
                                    .font(.caption.weight(.bold)).foregroundStyle(.white)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(shotColors[i % shotColors.count].gradient, in: .capsule)
                                Text(s.action).font(.callout)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                GlassPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "النص النظيف", symbol: "text.quote")
                        Text(p.text).font(.callout).lineSpacing(5).textSelection(.enabled)
                    }
                }
                GlassPanel(tint: .awPurple) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "النموذج", symbol: "cpu")
                        Text(p.model).font(.title3.weight(.bold)).environment(\.layoutDirection, .leftToRight)
                        Text(p.modelReason).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 280)
            }

            ForEach(Array(p.segments.enumerated()), id: \.element.id) { i, seg in
                GlassPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionLabel(text: "برومبت المقطع \(i + 1) · \(SheetService.format(seg.seconds)) ث", symbol: "text.word.spacing")
                            Spacer()
                            Button {
                                Panels.copy(seg.prompt); SoundFX.play(.copy); toast = Toast(text: "نُسخ برومبت المقطع \(i + 1)")
                            } label: { Label("نسخ", systemImage: "doc.on.doc") }
                            .buttonStyle(.glass)
                        }
                        Text(seg.prompt)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.background.opacity(0.5), in: .rect(cornerRadius: 12))
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
                .hoverTilt(radius: 26, tilt: 2, glow: tint, sound: false)
            }

            GlassPanel(tint: .awPink) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionLabel(text: "حزمة الكابشن", symbol: "captions.bubble")
                        Spacer()
                        Button {
                            Panels.copy(p.caption + "\n\n" + p.hashtags.joined(separator: " "))
                            SoundFX.play(.copy); toast = Toast(text: "نُسخ الكابشن")
                        } label: { Label("نسخ الكابشن", systemImage: "doc.on.doc") }
                        .buttonStyle(.glass)
                    }
                    Label(p.hook, systemImage: "bolt.fill").font(.headline)
                    ForEach(p.screenLines) { l in
                        HStack(spacing: 8) {
                            Text(l.at).font(.caption.monospaced()).foregroundStyle(.secondary)
                                .environment(\.layoutDirection, .leftToRight)
                            Text(l.text).font(.callout)
                        }
                    }
                    Divider().opacity(0.4)
                    Text(p.caption).font(.callout).textSelection(.enabled)
                    Text(p.hashtags.joined(separator: " ")).font(.callout).foregroundStyle(Color.awBlue)
                }
            }
        }
    }

    private func run() {
        SoundFX.play(.start)
        working = true
        progressText = ""
        let opts = VideoOptions(seconds: seconds, style: style, audio: audio, hero: hero, platform: platform)
        Task {
            defer { working = false }
            do {
                plan = try await WritingEngine.video(input, options: opts) { partial in
                    let n = partial.components(separatedBy: "\"action\"").count - 1
                    let m = partial.components(separatedBy: "\"prompt\"").count - 1
                    progressText = m > 0 ? "يكتب البرومبت \(m)…" : (n > 0 ? "يقطّع اللقطة \(n)…" : "ينظّف النص…")
                }
            } catch {
                toast = Toast(text: error.localizedDescription, isError: true)
            }
        }
    }
}
