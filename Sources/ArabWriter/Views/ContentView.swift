import SwiftUI
import AppKit

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case writer, checker, translate, story, video, word, sheet, pdf
    var id: String { rawValue }

    var title: String {
        switch self {
        case .writer: return "الكتابة"
        case .checker: return "الفاحص"
        case .translate: return "الترجمة"
        case .story: return "القصة"
        case .video: return "الفيديو"
        case .word: return "وورد"
        case .sheet: return "إكسل"
        case .pdf: return "PDF"
        }
    }

    var subtitle: String {
        switch self {
        case .writer: return "صياغة وتدقيق وكتابة"
        case .checker: return "فحص فوري بدون إنترنت"
        case .translate: return "عربي وإنجليزي بصوت بشري"
        case .story: return "قصة من عنوان"
        case .video: return "سكربت ولقطات وبرومبتات"
        case .word: return "تدقيق مع بقاء التنسيق"
        case .sheet: return "ترتيب وحساب وتنظيف"
        case .pdf: return "دمج وتقسيم وتلخيص"
        }
    }

    var symbol: String {
        switch self {
        case .writer: return "wand.and.stars"
        case .checker: return "checkmark.seal"
        case .translate: return "translate"
        case .story: return "book.pages"
        case .video: return "film.stack"
        case .word: return "doc.richtext"
        case .sheet: return "tablecells"
        case .pdf: return "doc.on.doc"
        }
    }

    var tint: Color {
        switch self {
        case .writer: return .awBlue
        case .checker: return .awGreen
        case .translate: return .awTeal
        case .story: return .awPurple
        case .video: return .awOrange
        case .word: return .awIndigo
        case .sheet: return Color(red: 0.13, green: 0.64, blue: 0.33)
        case .pdf: return .awPink
        }
    }

    var shortcut: Character { Character(String((AppSection.allCases.firstIndex(of: self) ?? 0) + 1)) }

    static let textGroup: [AppSection] = [.writer, .checker, .translate, .story, .video]
    static let filesGroup: [AppSection] = [.word, .sheet, .pdf]
}

/// مكان التنقل المشترك بين النافذة والقوائم ولوحة الأوامر.
@MainActor @Observable
final class Router {
    static let shared = Router()
    var section: AppSection? = .writer
    var palette = false
}

struct ContentView: View {
    @State private var router = Router.shared
    @State private var settings = AppSettings.shared
    @Environment(\.openSettings) private var openSettings
    @State private var pointer: CGPoint?
    @State private var inbox = Inbox.shared

    private var current: AppSection { router.section ?? .writer }

    var body: some View {
        // تخطيط يدوي بدل NavigationSplitView: الشريط الجانبي ثابت ويظهر دائماً،
        // ولا ينكمش أو يختفي مع الاتجاه من اليمين لليسار.
        ZStack {
            AppBackdrop(tint: current.tint).ignoresSafeArea()
            PointerSpotlight(point: pointer, tint: current.tint).ignoresSafeArea()
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 250)
                    .frame(maxHeight: .infinity)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    .padding(.vertical, 10).padding(.leading, 10)
                Group {
                    switch current {
                    case .writer: WriterView()
                    case .checker: CheckerView()
                    case .translate: TranslateView()
                    case .story: StoryView()
                    case .video: VideoView()
                    case .word: WordView()
                    case .sheet: SheetView()
                    case .pdf: PDFToolsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .transition(.opacity.combined(with: .scale(scale: 0.99)))
                .id(current)
            }
        }
        .animation(.smooth(duration: 0.35), value: router.section)
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let p): pointer = p
            case .ended: withAnimation(.smooth) { pointer = nil }
            }
        }
        .overlay {
            if router.palette {
                CommandPalette()
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: router.palette)
        .onChange(of: router.section) { SoundFX.play(.switchTab) }
        .onChange(of: inbox.text) { if inbox.text != nil { router.section = .writer } }
        .navigationTitle("Arab Writer")
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            searchButton
            List(selection: $router.section) {
                SwiftUI.Section("النص") {
                    ForEach(AppSection.textGroup) { row($0) }
                }
                SwiftUI.Section("الملفات") {
                    ForEach(AppSection.filesGroup) { row($0) }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            keyBadge
        }
    }

    private func row(_ s: AppSection) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(s.title).font(.body.weight(router.section == s ? .semibold : .regular))
                if router.section == s {
                    Text(s.subtitle).font(.caption2).foregroundStyle(.secondary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        } icon: {
            Image(systemName: s.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(s.tint.gradient, in: .rect(cornerRadius: 8))
                .shadow(color: s.tint.opacity(0.4), radius: 3, y: 1)
                .symbolEffect(.bounce, value: router.section == s)
        }
        .padding(.vertical, 3)
        .animation(.smooth, value: router.section)
        .tag(s)
    }

    private var searchButton: some View {
        Button { router.palette = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text("ابحث أو انتقل").foregroundStyle(.secondary)
                Spacer()
                Text("⌘K").font(.caption.monospaced()).foregroundStyle(.tertiary)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 10).padding(.top, 12)
    }

    private var keyBadge: some View {
        Button { openSettings() } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(settings.aiAvailable ? Color.awGreen : Color.awOrange)
                    .frame(width: 8, height: 8)
                    .shadow(color: (settings.aiAvailable ? Color.awGreen : Color.awOrange).opacity(0.8), radius: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(settings.usingLocal ? "داخلي · بدون إنترنت" : (settings.hasKey ? "Claude متصل" : "الأدوات فقط"))
                        .font(.caption.weight(.semibold))
                    Text(settings.usingLocal ? "كل شيء يبقى على جهازك" : (settings.hasKey ? "بمفتاحك الخاص" : "أضف مفتاحاً للمزايا الذكية"))
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

// MARK: - لوحة الأوامر

/// لوحة بحث سريعة بأسلوب Raycast: اكتب وانتقل بالكيبورد.
struct CommandPalette: View {
    @State private var router = Router.shared
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool
    @Environment(\.openSettings) private var openSettings

    private struct Item: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let tint: Color
        let run: @MainActor () -> Void
    }

    private var items: [Item] {
        var all = AppSection.allCases.map { s in
            Item(id: s.rawValue, title: s.title, subtitle: s.subtitle, symbol: s.symbol, tint: s.tint) {
                Router.shared.section = s
            }
        }
        all.append(Item(id: "paste", title: "الصق وصغ", subtitle: "ينقل الحافظة لقسم الكتابة", symbol: "doc.on.clipboard",
                        tint: .awBlue) {
            if let t = NSPasteboard.general.string(forType: .string) { Inbox.shared.text = t }
        })
        all.append(Item(id: "settings", title: "الإعدادات", subtitle: "المفتاح والنموذج والأصوات", symbol: "gearshape",
                        tint: .gray) { openSettings() })
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { $0.title.contains(q) || $0.subtitle.contains(q) || $0.id.contains(q.lowercased()) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18).ignoresSafeArea()
                .onTapGesture { close() }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(.secondary)
                    TextField("وين تبي تروح؟", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20))
                        .focused($focused)
                        .onSubmit { pick() }
                        .onKeyPress(.downArrow) { move(1); return .handled }
                        .onKeyPress(.upArrow) { move(-1); return .handled }
                        .onKeyPress(.escape) { close(); return .handled }
                }
                .padding(18)
                Divider().opacity(0.4)
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                            HStack(spacing: 12) {
                                Image(systemName: it.symbol)
                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(it.tint.gradient, in: .rect(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(it.title).font(.headline)
                                    Text(it.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if i == index { Image(systemName: "return").foregroundStyle(.secondary) }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(i == index ? it.tint.opacity(0.16) : .clear, in: .rect(cornerRadius: 12))
                            .contentShape(.rect)
                            .onTapGesture { index = i; pick() }
                            .onHover { if $0 { index = i } }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 380)
            }
            .frame(width: 560)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
            .shadow(color: .black.opacity(0.25), radius: 40, y: 20)
            .padding(.top, 90)
        }
        .onAppear { focused = true; index = 0 }
        .onChange(of: query) { index = 0 }
    }

    private func move(_ d: Int) {
        let n = items.count
        guard n > 0 else { return }
        index = (index + d + n) % n
        SoundFX.play(.hover)
    }

    private func pick() {
        let list = items
        guard list.indices.contains(index) else { return }
        SoundFX.play(.tap)
        close()
        list[index].run()
    }

    private func close() {
        router.palette = false
        query = ""
    }
}
