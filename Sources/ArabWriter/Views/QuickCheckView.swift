import SwiftUI
import AppKit
import ArabWriterCore

/// نافذة شريط القوائم: فحص وتصحيح سريع بدون فتح البرنامج.
struct QuickCheckView: View {
    @State private var text = ""
    @State private var report = LintReport()
    @State private var working = false
    @State private var note: String?
    @State private var settings = AppSettings.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "text.badge.checkmark")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.awGreen.gradient, in: .rect(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 0) {
                    Text("فحص سريع").font(.headline)
                    Text("Arab Writer").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if !text.isEmpty { Inbox.shared.text = text }
                    openWindow(id: "main")
                    NSApp.activate()
                } label: { Image(systemName: "arrow.up.forward.app") }
                .buttonStyle(.glass).help("افتح في البرنامج")
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("الصق نصاً أو اكتب هنا…").foregroundStyle(.tertiary).padding(.horizontal, 5).padding(.top, 1)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
            }
            .padding(10)
            .frame(height: 150)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))

            HStack(spacing: 6) {
                chip("\(report.stats.words)", "كلمة", .primary)
                chip("\(report.errors.count)", "خطأ", report.errors.isEmpty ? .awGreen : .awPink)
                chip("\(report.warnings.count)", "تنبيه", report.warnings.isEmpty ? .awGreen : .awOrange)
                Spacer()
                if let note { Text(note).font(.caption).foregroundStyle(.secondary).transition(.opacity) }
            }

            if !text.isEmpty && !report.issues.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach((report.errors + report.warnings).prefix(4)) { IssueRow(issue: $0) }
                    if report.issues.count > 4 {
                        Text("و\(report.issues.count - 4) غيرها").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
            }

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ActionTile(title: "لصق", symbol: "doc.on.clipboard", tint: .awBlue) {
                        text = NSPasteboard.general.string(forType: .string) ?? text
                    }
                    ActionTile(title: "صحّح", symbol: "bandage.fill", tint: .awGreen, disabled: text.isEmpty) {
                        text = ArabicLinter.fix(text, englishOnOwnLine: settings.englishOnOwnLine)
                        flash("صُحّح الآمن")
                    }
                    ActionTile(title: working ? "يصيغ…" : "صغ", symbol: "wand.and.stars", tint: .awPurple,
                               disabled: text.isEmpty || working || !settings.hasKey) { rewrite() }
                    ActionTile(title: "انسخ", symbol: "doc.on.doc.fill", tint: .awIndigo, disabled: text.isEmpty) {
                        Panels.copy(text); SoundFX.play(.copy); flash("نُسخ")
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 420)
        .task(id: text) {
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.smooth) {
                report = ArabicLinter.check(text, options: LintOptions(englishOnOwnLine: settings.englishOnOwnLine))
            }
        }
    }

    private func chip(_ v: String, _ label: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(v).font(.callout.weight(.bold)).foregroundStyle(tint).contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
    }

    private func flash(_ s: String) {
        withAnimation { note = s }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { note = nil }
        }
    }

    private func rewrite() {
        working = true
        let req = WriteRequest(text: text, mode: .rewrite, register: .keep, platform: .none, words: nil)
        Task {
            defer { working = false }
            do {
                let r = try await WritingEngine.run(req) { text = $0 }
                text = r.text
                SoundFX.play(.success)
                flash("صيغ بصوت بشري")
            } catch {
                SoundFX.play(.error)
                flash(error.localizedDescription)
            }
        }
    }
}
