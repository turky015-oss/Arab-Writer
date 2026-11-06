import SwiftUI
import AppKit

// MARK: - الأصوات

/// أصوات الواجهة من أصوات النظام الأصلية، بمستويات هادئة.
@MainActor
enum SoundFX {
    case hover, tap, start, success, error, drop, copy, switchTab

    private var spec: (name: String, volume: Float) {
        switch self {
        case .hover: return ("Tink", 0.08)
        case .tap: return ("Pop", 0.25)
        case .start: return ("Morse", 0.22)
        case .success: return ("Glass", 0.35)
        case .error: return ("Funk", 0.35)
        case .drop: return ("Hero", 0.3)
        case .copy: return ("Tink", 0.3)
        case .switchTab: return ("Pop", 0.12)
        }
    }

    private static var cache: [String: NSSound] = [:]
    private static var lastHover = Date.distantPast

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: "sounds") as? Bool ?? true
    }

    static func play(_ fx: SoundFX) {
        guard enabled else { return }
        if fx == .hover {
            // لا تتكرر أصوات المرور بسرعة
            guard Date().timeIntervalSince(lastHover) > 0.09 else { return }
            lastHover = Date()
        }
        let s = fx.spec
        let sound: NSSound
        if let c = cache[s.name], !c.isPlaying {
            sound = c
        } else if let fresh = NSSound(named: NSSound.Name(s.name))?.copy() as? NSSound {
            sound = fresh
            cache[s.name] = fresh
        } else { return }
        sound.volume = s.volume
        sound.play()
        if fx == .tap || fx == .success || fx == .drop {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }
}

// MARK: - تفاعل الماوس

/// يميل العنصر نحو المؤشر، ويضيء مكانه، ويكبر قليلاً عند المرور.
struct HoverTilt: ViewModifier {
    var radius: CGFloat = 20
    var tilt: Double = 7
    var glow: Color = .white
    var sound = true

    @State private var point: CGPoint?
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        let p = point ?? CGPoint(x: size.width / 2, y: size.height / 2)
        let nx = size.width > 0 ? (p.x / size.width - 0.5) : 0
        let ny = size.height > 0 ? (p.y / size.height - 0.5) : 0
        let active = point != nil

        content
            .overlay {
                RadialGradient(colors: [glow.opacity(active ? 0.28 : 0), .clear],
                               center: UnitPoint(x: nx + 0.5, y: ny + 0.5),
                               startRadius: 0, endRadius: max(size.width, size.height) * 0.75)
                    .clipShape(.rect(cornerRadius: radius))
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(
                        AngularGradient(colors: [glow.opacity(0.6), .clear, glow.opacity(0.25), .clear, glow.opacity(0.6)],
                                        center: .center, angle: .degrees(Double(atan2(ny, nx)) * 180 / Double.pi)),
                        lineWidth: 1
                    )
                    .opacity(active ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .scaleEffect(active ? 1.025 : 1)
            .rotation3DEffect(.degrees(active ? -Double(ny) * tilt : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(active ? Double(nx) * tilt : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .shadow(color: .black.opacity(active ? 0.16 : 0), radius: active ? 16 : 0, y: active ? 8 : 0)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    if point == nil, sound { SoundFX.play(.hover) }
                    withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.75)) { point = loc }
                case .ended:
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { point = nil }
                }
            }
    }
}

extension View {
    func hoverTilt(radius: CGFloat = 20, tilt: Double = 7, glow: Color = .white, sound: Bool = true) -> some View {
        modifier(HoverTilt(radius: radius, tilt: tilt, glow: glow, sound: sound))
    }
}

/// بقعة ضوء تتبع المؤشر فوق الخلفية.
struct PointerSpotlight: View {
    let point: CGPoint?
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            if let p = point {
                RadialGradient(colors: [tint.opacity(0.35), tint.opacity(0.08), .clear],
                               center: UnitPoint(x: p.x / max(geo.size.width, 1), y: p.y / max(geo.size.height, 1)),
                               startRadius: 0, endRadius: 420)
                    .blendMode(.plusLighter)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - بطاقات الملفات

/// شارة صيغة الملف (DOCX، XLSX، PDF) بشكل أيقونة مستند.
struct FormatBadge: View {
    let label: String
    let symbol: String
    let tint: Color
    var size: CGFloat = 120

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: size * 0.16)
                .fill(LinearGradient(colors: [.white, Color(white: 0.92)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.8, height: size)
                .overlay(alignment: .topTrailing) {
                    // الزاوية المطوية
                    Triangle()
                        .fill(Color(white: 0.82))
                        .frame(width: size * 0.22, height: size * 0.22)
                }
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.32, weight: .semibold))
                        .foregroundStyle(tint.gradient)
                        .offset(y: -size * 0.1)
                }
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            Text(label)
                .font(.system(size: size * 0.13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, size * 0.09).padding(.vertical, size * 0.04)
                .background(tint.gradient, in: .rect(cornerRadius: size * 0.06))
                .offset(y: -size * 0.12)
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

struct Feature: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let caption: String
}

/// بطاقة قدرة: أيقونة ملونة وعنوان ووصف، تتفاعل مع الماوس.
struct FeatureTile: View {
    let feature: Feature
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feature.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(tint.gradient, in: .rect(cornerRadius: 11))
                .shadow(color: tint.opacity(0.35), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title).font(.headline)
                Text(feature.caption).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .hoverTilt(radius: 18, tilt: 6, glow: tint)
    }
}

/// رأس القسم: شارة مائلة كبيرة بجانب العنوان.
struct HeroHeader: View {
    let badge: String
    let symbol: String
    let tint: Color
    let headline: String
    let subline: String
    var size: CGFloat = 96

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 24) {
            FormatBadge(label: badge, symbol: symbol, tint: tint, size: size)
                .rotationEffect(.degrees(appeared ? -6 : -16))
                .offset(y: appeared ? 0 : 16)
                .hoverTilt(radius: 18, tilt: 14, glow: tint)
            VStack(alignment: .leading, spacing: 6) {
                Text(headline).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(subline).font(.title3).foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            Spacer()
        }
        .padding(.horizontal, 6)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appeared = true } }
    }
}

/// شبكة بطاقات القدرات تظهر بالتتابع.
struct FeatureGrid: View {
    let features: [Feature]
    let tint: Color
    var minimum: CGFloat = 230
    @State private var appeared = false

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 12)], spacing: 12) {
            ForEach(Array(features.enumerated()), id: \.element.id) { i, f in
                FeatureTile(feature: f, tint: tint)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 14)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05 * Double(i)), value: appeared)
            }
        }
        .onAppear { appeared = true }
    }
}

/// واجهة البداية لأقسام الملفات: شارة كبيرة، قدرات، ومنطقة إسقاط.
struct FileHero: View {
    let format: String
    let symbol: String
    let tint: Color
    let headline: String
    let features: [Feature]
    let dropTitle: String
    let dropSubtitle: String
    let types: [String]
    var multiple = false
    let onFiles: ([URL]) -> Void

    @State private var appeared = false
    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 12)]

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 28) {
                FormatBadge(label: format, symbol: symbol, tint: tint)
                    .rotationEffect(.degrees(appeared ? -6 : -14))
                    .offset(y: appeared ? 0 : 20)
                    .hoverTilt(radius: 20, tilt: 14, glow: tint)
                VStack(alignment: .leading, spacing: 8) {
                    Text(headline).font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("اسحب الملف لأي مكان هنا أو اختره، وكل شيء يصير على جهازك.")
                        .font(.title3).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 8)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(features.enumerated()), id: \.element.id) { i, f in
                    FeatureTile(feature: f, tint: tint)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.04 * Double(i)), value: appeared)
                }
            }

            DropZone(title: dropTitle, subtitle: dropSubtitle, symbol: "arrow.down.doc", tint: tint,
                     types: types, multiple: multiple, onFiles: onFiles)
        }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appeared = true } }
    }
}

/// زر أداة: أيقونة ملونة فوق اسمها، بزجاج تفاعلي.
struct ActionTile: View {
    let title: String
    let symbol: String
    let tint: Color
    var selected = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button {
            SoundFX.play(.tap)
            action()
        } label: {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(tint.gradient))
                    .frame(width: 34, height: 34)
                    .background(selected ? AnyShapeStyle(.white.opacity(0.2)) : AnyShapeStyle(tint.opacity(0.14)),
                                in: .rect(cornerRadius: 10))
                Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                    .foregroundStyle(selected ? .white : .primary)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? Glass.regular.tint(tint).interactive() : Glass.regular.interactive(),
                     in: .rect(cornerRadius: 18))
        .hoverTilt(radius: 18, tilt: 9, glow: selected ? .white : tint, sound: !disabled)
        .opacity(disabled ? 0.45 : 1)
        .disabled(disabled)
    }
}
