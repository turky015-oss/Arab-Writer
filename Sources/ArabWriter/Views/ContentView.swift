import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case writer, checker, story, word, sheet, pdf
    var id: String { rawValue }

    var title: String {
        switch self {
        case .writer: return "الكتابة"
        case .checker: return "الفاحص"
        case .story: return "القصة"
        case .word: return "وورد"
        case .sheet: return "إكسل"
        case .pdf: return "PDF"
        }
    }

    var symbol: String {
        switch self {
        case .writer: return "wand.and.stars"
        case .checker: return "checkmark.seal"
        case .story: return "book.pages"
        case .word: return "doc.richtext"
        case .sheet: return "tablecells"
        case .pdf: return "doc.on.doc"
        }
    }

    var tint: Color {
        switch self {
        case .writer: return .awBlue
        case .checker: return .awGreen
        case .story: return .awPurple
        case .word: return .awIndigo
        case .sheet: return Color(red: 0.13, green: 0.64, blue: 0.33)
        case .pdf: return .awPink
        }
    }

    static let textGroup: [AppSection] = [.writer, .checker, .story]
    static let filesGroup: [AppSection] = [.word, .sheet, .pdf]
}

struct ContentView: View {
    @State private var selection: AppSection? = .writer
    @State private var settings = AppSettings.shared
    @Environment(\.openSettings) private var openSettings
    @State private var pointer: CGPoint?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                SwiftUI.Section("النص") {
                    ForEach(AppSection.textGroup) { row($0) }
                }
                SwiftUI.Section("الملفات") {
                    ForEach(AppSection.filesGroup) { row($0) }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
            .safeAreaInset(edge: .bottom) { keyBadge }
        } detail: {
            ZStack {
                AppBackdrop(tint: (selection ?? .writer).tint)
                PointerSpotlight(point: pointer, tint: (selection ?? .writer).tint)
                Group {
                    switch selection ?? .writer {
                    case .writer: WriterView()
                    case .checker: CheckerView()
                    case .story: StoryView()
                    case .word: WordView()
                    case .sheet: SheetView()
                    case .pdf: PDFToolsView()
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.99)))
            }
            .animation(.smooth(duration: 0.35), value: selection)
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p): pointer = p
                case .ended: withAnimation(.smooth) { pointer = nil }
                }
            }
        }
        .onChange(of: selection) { SoundFX.play(.switchTab) }
        .navigationTitle("Arab Writer")
    }

    private func row(_ s: AppSection) -> some View {
        Label {
            Text(s.title).font(.body.weight(selection == s ? .semibold : .regular))
        } icon: {
            Image(systemName: s.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(s.tint.gradient, in: .rect(cornerRadius: 7))
                .shadow(color: s.tint.opacity(0.4), radius: 3, y: 1)
                .symbolEffect(.bounce, value: selection == s)
        }
        .padding(.vertical, 3)
        .tag(s)
    }

    private var keyBadge: some View {
        Button { openSettings() } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(settings.hasKey ? Color.awGreen : Color.awOrange)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(settings.hasKey ? "الذكاء مفعّل" : "وضع بدون إنترنت")
                        .font(.caption.weight(.semibold))
                    Text(settings.hasKey ? "Claude متصل بمفتاحك" : "أضف مفتاحك للمزايا الذكية")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "gearshape").foregroundStyle(.secondary)
            }
            .padding(10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        .padding(10)
    }
}
