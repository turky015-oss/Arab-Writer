import SwiftUI
import ArabWriterCore

/// فحص فوري أثناء الكتابة — يعمل بدون إنترنت.
struct CheckerView: View {
    @State private var text = ""
    @State private var source = ""
    @State private var useSource = false
    @State private var lockWords = false
    @State private var words = 60
    @State private var report = LintReport()
    @State private var toast: Toast?
    @State private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HeroHeader(badge: "فحص", symbol: "checkmark.seal.fill", tint: .awGreen,
                           headline: "افحص قبل ما تنشر",
                           subline: "يكشف البصمات والأخطاء لحظة الكتابة، بدون إنترنت")

                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        ActionTile(title: "قارن بالأصل", symbol: "doc.on.doc.fill", tint: .awIndigo, selected: useSource) {
                            withAnimation(.smooth) { useSource.toggle() }
                        }
                        .frame(width: 120)
                        ActionTile(title: "قفل الطول", symbol: "ruler", tint: .awOrange, selected: lockWords) {
                            withAnimation(.smooth) { lockWords.toggle() }
                        }
                        .frame(width: 120)
                        if lockWords {
                            Stepper(value: $words, in: 10...1000, step: 10) { Text("\(words) كلمة").font(.headline).monospacedDigit() }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .glassEffect(.regular, in: .capsule)
                                .transition(.scale.combined(with: .opacity))
                        }
                        Spacer()
                        ActionTile(title: "انسخ النص", symbol: "doc.on.clipboard.fill", tint: .awBlue, disabled: text.isEmpty) {
                            Panels.copy(text); SoundFX.play(.copy)
                        }
                        .frame(width: 120)
                        ActionTile(title: "أصلح الآمن", symbol: "bandage.fill", tint: .awGreen, disabled: text.isEmpty) {
                            text = ArabicLinter.fix(text, englishOnOwnLine: settings.englishOnOwnLine)
                            toast = Toast(text: "أُصلح الآمن: الإملاء والترقيم والمسافات")
                        }
                        .frame(width: 120)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        if useSource {
                            GlassPanel {
                                VStack(alignment: .leading, spacing: 8) {
                                    SectionLabel(text: "الأصل", symbol: "doc.text")
                                    ArabicEditor(text: $source, placeholder: "الصق النص الأصلي لكشف الأرقام والأسماء المضافة")
                                        .frame(minHeight: 120)
                                }
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        GlassPanel {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel(text: "النص", symbol: "text.alignright")
                                ArabicEditor(text: $text, placeholder: "اكتب أو الصق النص، والفحص يجري وأنت تكتب…")
                                    .frame(minHeight: useSource ? 280 : 440)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    GlassPanel(tint: report.isClean ? .awGreen : .awPink) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(text: "التقرير", symbol: "checklist")
                            if text.isEmpty {
                                Text("يفحص:").font(.caption).foregroundStyle(.secondary)
                                FeatureGrid(features: [
                                    Feature(symbol: "cpu", title: "بصمات آلية", caption: "افتتاح وختام وحشو وترجمة حرفية"),
                                    Feature(symbol: "textformat.abc", title: "الإملاء", caption: "أكثر من ١٥٠ خطأ شائع"),
                                    Feature(symbol: "textformat.alt", title: "الترقيم", caption: "الفواصل والمسافات وعلامة الاستفهام"),
                                    Feature(symbol: "arrow.left.and.right.text.vertical", title: "الاتجاه", caption: "الإنجليزي داخل السطر العربي"),
                                    Feature(symbol: "waveform.path", title: "الإيقاع", caption: "جمل متشابهة الطول وتقطيع درامي"),
                                    Feature(symbol: "exclamationmark.shield.fill", title: "الاختلاق", caption: "أرقام وأسماء ما هي في الأصل"),
                                ], tint: .awGreen, minimum: 150)
                            } else {
                                ReportView(report: report)
                            }
                        }
                    }
                    .frame(width: 380)
                }
            }
            .padding(28)
        }
        .scrollContentBackground(.hidden)
        .toast($toast)
        .task(id: key) {
            try? await Task.sleep(for: .milliseconds(250))
            let opts = LintOptions(wordsTarget: lockWords ? words : nil,
                                   source: useSource && !source.isEmpty ? source : nil,
                                   englishOnOwnLine: settings.englishOnOwnLine)
            withAnimation(.smooth) { report = ArabicLinter.check(text, options: opts) }
        }
    }

    private var key: String { "\(text.hashValue)|\(source.hashValue)|\(useSource)|\(lockWords)|\(words)" }
}
