import SwiftUI
import ArabWriterCore

struct StoryView: View {
    @State private var title = ""
    @State private var length: StoryLength = .short
    @State private var register: Register = .keep
    @State private var result: WriteResult?
    @State private var working = false
    @State private var live = ""
    @State private var toast: Toast?
    @State private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HeroHeader(badge: "قصة", symbol: "book.pages.fill", tint: .awPurple,
                           headline: "من عنوان إلى قصة",
                           subline: "قصة قصيرة تُقرأ في أقل من دقيقتين، بلا تمهيد ولا موعظة")

                GlassPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("العنوان أو الفكرة… مثال: آخر رحلة قطار من الأحساء", text: $title)
                            .textFieldStyle(.plain)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .onSubmit(run)
                        Divider().opacity(0.4)
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel(text: "الطول", symbol: "ruler")
                                GlassEffectContainer(spacing: 8) {
                                    HStack(spacing: 8) {
                                        ForEach(StoryLength.allCases) { l in
                                            ActionTile(title: l.rawValue, symbol: l.symbol, tint: .awPurple, selected: length == l) {
                                                withAnimation(.smooth) { length = l }
                                            }
                                        }
                                    }
                                }
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel(text: "اللغة", symbol: "text.bubble")
                                GlassEffectContainer(spacing: 8) {
                                    HStack(spacing: 8) {
                                        ForEach(Register.allCases) { r in
                                            ActionTile(title: r == .keep ? "حسب العنوان" : r.rawValue, symbol: r.symbol,
                                                       tint: .awPink, selected: register == r) {
                                                withAnimation(.smooth) { register = r }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        HStack {
                            Spacer()
                            Button(action: run) {
                                HStack(spacing: 10) {
                                    if working { ProgressView().controlSize(.small) } else { Image(systemName: "sparkles") }
                                    Text(working ? "يكتب…" : "اكتب القصة")
                                }
                                .font(.title3.weight(.semibold)).padding(.horizontal, 22).padding(.vertical, 6)
                            }
                            .buttonStyle(.glassProminent).controlSize(.extraLarge).tint(.awPurple)
                            .disabled(working || title.trimmingCharacters(in: .whitespaces).isEmpty)
                            .hoverTilt(radius: 30, tilt: 6, glow: .white, sound: false)
                        }
                        Text("\(length.range) كلمة").font(.caption).foregroundStyle(.secondary)
                    }
                }

                if !settings.hasKey {
                    Label("القصة تحتاج مفتاح Claude. أضفه من الإعدادات (⌘ ,)", systemImage: "key")
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular.tint(Color.awOrange.opacity(0.15)), in: .rect(cornerRadius: 16))
                }

                if working && !live.isEmpty {
                    GlassPanel(tint: .awPurple) {
                        LiveText(text: live, tint: .awPurple, fontSize: 18).frame(minHeight: 260)
                    }
                    .transition(.opacity)
                } else if result == nil {
                    FeatureGrid(features: [
                        Feature(symbol: "figure.walk", title: "يبدأ بفعل", caption: "شخص يسوي شيئاً في مكان وزمن محدد"),
                        Feature(symbol: "chart.line.uptrend.xyaxis", title: "تصعيد", caption: "شيء يقاوم البطل ويضيّق خياراته"),
                        Feature(symbol: "arrow.triangle.turn.up.right.diamond.fill", title: "نقطة تحول", caption: "قرار أو معلومة تقلب الموقف"),
                        Feature(symbol: "flag.checkered", title: "نهاية صامتة", caption: "تغلق المشهد بلا شرح للمغزى"),
                    ], tint: .awPurple, minimum: 200)
                }

                if let r = result, !working {
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
        SoundFX.play(.start)
        working = true
        Task {
            defer { working = false }
            live = ""
            do { result = try await WritingEngine.story(title: title, length: length, register: register) { live = $0 } }
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

extension StoryLength {
    var symbol: String {
        switch self {
        case .flash: return "bolt.fill"
        case .short: return "book.fill"
        case .script: return "video.fill"
        }
    }
}
