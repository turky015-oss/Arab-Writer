import SwiftUI
import AppKit
import ArabWriterCore

struct TranslateView: View {
    @State private var input = ""
    @State private var direction: TranslateDirection = .auto
    @State private var register: Register = .keep
    @State private var result: WriteResult?
    @State private var live = ""
    @State private var working = false
    @State private var toast: Toast?
    @State private var settings = AppSettings.shared

    private let tint = Color.awTeal
    private var resolved: TranslateDirection { direction.resolved(for: input) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HeroHeader(badge: "ترجمة", symbol: "translate", tint: tint,
                           headline: "ترجمة بصوت إنسان",
                           subline: "تنقل المعنى لا الكلمات، وتمر على نفس الفحص فتطلع طبيعية")

                HStack(alignment: .top, spacing: 16) {
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(text: "الاتجاه", symbol: "arrow.left.arrow.right")
                            GlassEffectContainer(spacing: 8) {
                                HStack(spacing: 8) {
                                    ForEach(TranslateDirection.allCases) { d in
                                        ActionTile(title: d.rawValue, symbol: d.symbol, tint: tint, selected: direction == d) {
                                            withAnimation(.smooth) { direction = d }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(text: "العربي الناتج", symbol: "text.bubble")
                            GlassEffectContainer(spacing: 8) {
                                HStack(spacing: 8) {
                                    ForEach(Register.allCases) { r in
                                        ActionTile(title: r == .keep ? "حسب النص" : r.rawValue, symbol: r.symbol, tint: .awBlue,
                                                   selected: register == r, disabled: resolved == .toEnglish) {
                                            withAnimation(.smooth) { register = r }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                SectionLabel(text: resolved == .toArabic ? "English" : "العربي", symbol: "text.alignright")
                                Spacer()
                                Button("لصق", systemImage: "doc.on.clipboard") {
                                    if let s = NSPasteboard.general.string(forType: .string) { input = s }
                                }
                                .labelStyle(.iconOnly).buttonStyle(.borderless)
                            }
                            ArabicEditor(text: $input, placeholder: "الصق النص بأي لغة من الاثنتين…")
                                .environment(\.layoutDirection, resolved == .toArabic && !input.isEmpty ? .leftToRight : .rightToLeft)
                                .frame(minHeight: 300)
                        }
                    }

                    VStack(spacing: 12) {
                        Button(action: run) {
                            Image(systemName: working ? "hourglass" : "arrow.forward")
                                .font(.system(size: 20, weight: .bold))
                                .frame(width: 54, height: 54)
                                .symbolEffect(.pulse, isActive: working)
                        }
                        .buttonStyle(.glassProminent).tint(tint)
                        .clipShape(.circle)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(working || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !settings.hasKey)
                        .hoverTilt(radius: 27, tilt: 12, glow: .white, sound: false)
                        Button {
                            if let r = result { input = r.text; result = nil; SoundFX.play(.tap) }
                        } label: {
                            Image(systemName: "arrow.left.arrow.right").frame(width: 30, height: 30)
                        }
                        .buttonStyle(.glass).clipShape(.circle)
                        .disabled(result == nil)
                        .help("بدّل")
                    }
                    .padding(.top, 140)

                    GlassPanel(tint: tint) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                SectionLabel(text: resolved == .toArabic ? "العربي" : "English", symbol: "sparkles")
                                Spacer()
                                if let r = result {
                                    Button("نسخ", systemImage: "doc.on.doc") {
                                        Panels.copy(r.text); SoundFX.play(.copy); toast = Toast(text: "نُسخت الترجمة")
                                    }
                                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                                }
                            }
                            Group {
                                if working && !live.isEmpty {
                                    LiveText(text: live, tint: tint)
                                } else if working {
                                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                                } else if let r = result {
                                    ArabicEditor(text: .constant(r.text), placeholder: "", editable: false)
                                } else {
                                    FeatureGrid(features: [
                                        Feature(symbol: "quote.bubble.fill", title: "المعنى لا الحرف", caption: "يعيد بناء الجملة كما يقولها صاحب اللغة"),
                                        Feature(symbol: "eraser.fill", title: "بلا بصمات", caption: "لا «يلعب دوراً» ولا «delve»"),
                                        Feature(symbol: "lock.shield.fill", title: "أمين", caption: "لا يضيف رقماً ولا يحذف اسماً"),
                                    ], tint: tint, minimum: 180)
                                }
                            }
                            .environment(\.layoutDirection, resolved == .toEnglish ? .leftToRight : .rightToLeft)
                            .frame(minHeight: 300)
                        }
                    }
                }

                if !settings.hasKey {
                    Label("الترجمة تحتاج مفتاح Claude. أضفه من الإعدادات (⌘ ,)", systemImage: "key")
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular.tint(Color.awOrange.opacity(0.15)), in: .rect(cornerRadius: 16))
                }

                if let r = result, resolved == .toArabic || !r.report.issues.isEmpty {
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(text: "فحص الترجمة", symbol: "checklist")
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

    private func run() {
        SoundFX.play(.start)
        working = true
        live = ""
        let dir = direction
        Task {
            defer { working = false; live = "" }
            do {
                result = try await WritingEngine.translate(input, direction: dir, register: register) { live = $0 }
            } catch {
                toast = Toast(text: error.localizedDescription, isError: true)
            }
        }
    }
}
