import SwiftUI
import AppKit
import ArabWriterCore

// MARK: - ألوان أبل

extension Color {
    static let awBlue = Color(red: 0.04, green: 0.52, blue: 1.0)
    static let awPurple = Color(red: 0.75, green: 0.35, blue: 0.95)
    static let awPink = Color(red: 1.0, green: 0.22, blue: 0.37)
    static let awOrange = Color(red: 1.0, green: 0.62, blue: 0.04)
    static let awTeal = Color(red: 0.39, green: 0.82, blue: 1.0)
    static let awGreen = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let awIndigo = Color(red: 0.37, green: 0.36, blue: 0.90)
}

// MARK: - الخلفية الحيّة خلف الزجاج

struct AppBackdrop: View {
    var tint: Color = .awBlue
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { ctx in
            MeshGradient(width: 3, height: 3, points: points(ctx.date), colors: colors)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
    }

    private func points(_ date: Date) -> [SIMD2<Float>] {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60) / 60 * 2 * Double.pi
        let dx = Float(0.08 * sin(phase))
        let dy = Float(0.08 * cos(phase))
        return [
            SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
            SIMD2(0, 0.5), SIMD2(0.5 + dx, 0.5 + dy), SIMD2(1, 0.5),
            SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1),
        ]
    }

    private var colors: [Color] {
        let o: Double = scheme == .dark ? 0.55 : 0.35
        let base = Color(nsColor: .windowBackgroundColor)
        return [
            tint.opacity(o), Color.awPurple.opacity(o * 0.7), Color.awTeal.opacity(o * 0.6),
            Color.awPink.opacity(o * 0.45), base, tint.opacity(o * 0.5),
            Color.awOrange.opacity(o * 0.35), Color.awIndigo.opacity(o * 0.55), Color.awGreen.opacity(o * 0.3),
        ]
    }
}

// MARK: - مكوّنات الزجاج

struct GlassPanel<Content: View>: View {
    var radius: CGFloat = 26
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(tint.map { Glass.regular.tint($0.opacity(0.12)) } ?? Glass.regular, in: .rect(cornerRadius: radius))
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .top, endPoint: .bottom),
                    in: .rect(cornerRadius: 15)
                )
                .glassEffect(.clear, in: .rect(cornerRadius: 15))
                .shadow(color: tint.opacity(0.35), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 26, weight: .bold, design: .rounded))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct SectionLabel: View {
    let text: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

/// محرر نص عربي شفاف فوق الزجاج.
struct ArabicEditor: View {
    @Binding var text: String
    var placeholder: String
    var editable = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .allowsHitTesting(false)
            }
            if editable {
                TextEditor(text: $text)
                    .font(.system(size: 16))
                    .lineSpacing(5)
                    .scrollContentBackground(.hidden)
            } else {
                ScrollView {
                    Text(text)
                        .font(.system(size: 16))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var tint: Color = .primary
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 64)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

struct IssueRow: View {
    let issue: LintIssue
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.level == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(issue.level == .error ? Color.awPink : Color.awOrange)
                .font(.system(size: 14))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(issue.kind).font(.caption.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background((issue.level == .error ? Color.awPink : Color.awOrange).opacity(0.15), in: .capsule)
                    if let l = issue.line { Text("سطر \(l)").font(.caption).foregroundStyle(.secondary) }
                }
                Text(issue.message).font(.callout)
                if let ex = issue.excerpt {
                    Text(ex).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

struct ReportView: View {
    let report: LintReport
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                StatTile(value: "\(report.stats.words)", label: "كلمة")
                StatTile(value: "\(report.stats.sentences)", label: "جملة")
                StatTile(value: "\(report.errors.count)", label: "خطأ", tint: report.errors.isEmpty ? .awGreen : .awPink)
                StatTile(value: "\(report.warnings.count)", label: "تنبيه", tint: report.warnings.isEmpty ? .awGreen : .awOrange)
            }
            if report.issues.isEmpty {
                Label("نظيف وجاهز للنشر", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Color.awGreen).font(.headline)
                    .padding(.top, 4)
            } else {
                ForEach(report.errors + report.warnings) { IssueRow(issue: $0) }
            }
        }
    }
}

/// منطقة إسقاط ملف بشكل زجاجي.
struct DropZone: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let types: [String]
    var multiple = false
    let onFiles: ([URL]) -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            if let urls = Panels.open(types: types, multiple: multiple), !urls.isEmpty { onFiles(urls) }
        } label: {
            VStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: hovering)
                Text(title).font(.title3.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(tint.opacity(hovering ? 0.18 : 0.06)).interactive(), in: .rect(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                .foregroundStyle(tint.opacity(hovering ? 0.7 : 0.3))
        )
        .dropDestination(for: URL.self) { urls, _ in
            let ok = urls.filter { types.contains($0.pathExtension.lowercased()) }
            if !ok.isEmpty { onFiles(multiple ? ok : [ok[0]]) }
            return !ok.isEmpty
        } isTargeted: { hovering = $0 }
        .animation(.smooth, value: hovering)
    }
}

/// شريط رسالة عائم أسفل الصفحة.
struct Toast: Equatable {
    var text: String
    var isError = false
}

struct ToastView: View {
    let toast: Toast
    var body: some View {
        Label(toast.text, systemImage: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .foregroundStyle(toast.isError ? Color.awPink : Color.primary)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .glassEffect(.regular.tint((toast.isError ? Color.awPink : Color.awGreen).opacity(0.15)), in: .capsule)
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    func toast(_ toast: Binding<Toast?>) -> some View {
        overlay(alignment: .bottom) {
            if let t = toast.wrappedValue {
                ToastView(toast: t)
                    .task(id: t.text) {
                        try? await Task.sleep(for: .seconds(t.isError ? 5 : 3))
                        withAnimation(.smooth) { toast.wrappedValue = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.4), value: toast.wrappedValue)
    }
}
