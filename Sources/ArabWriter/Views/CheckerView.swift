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
                PageHeader(title: "الفاحص", subtitle: "يكشف بصمات الذكاء الاصطناعي والأخطاء لحظة الكتابة، بدون إنترنت",
                           symbol: "checkmark.seal", tint: .awGreen)

                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 10) {
                        Toggle(isOn: $useSource.animation(.smooth)) { Label("قارن بالأصل", systemImage: "doc.on.doc") }
                            .toggleStyle(.button).buttonStyle(.glass)
                        Toggle(isOn: $lockWords.animation(.smooth)) { Label("قفل الطول", systemImage: "ruler") }
                            .toggleStyle(.button).buttonStyle(.glass)
                        if lockWords {
                            Stepper(value: $words, in: 10...1000, step: 10) { Text("\(words) كلمة").monospacedDigit() }
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .glassEffect(.regular, in: .capsule)
                        }
                        Spacer()
                        Button {
                            text = ArabicLinter.fix(text, englishOnOwnLine: settings.englishOnOwnLine)
                            toast = Toast(text: "أُصلح الآمن: الإملاء والترقيم والمسافات")
                        } label: {
                            Label("أصلح الآمن", systemImage: "bandage")
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.awGreen)
                        .disabled(text.isEmpty)
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
                                Text("التقرير يظهر هنا").foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 200)
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
