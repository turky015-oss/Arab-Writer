import SwiftUI
import ArabWriterCore

struct SheetView: View {
    @State private var url: URL?
    @State private var sheets: [Sheet] = []
    @State private var current = 0
    @State private var column = 0
    @State private var headerRow = true
    @State private var operand = "2"
    @State private var calc: String?
    @State private var toast: Toast?

    private let tint = Color(red: 0.13, green: 0.64, blue: 0.33)
    private let cellWidth: CGFloat = 150
    private let maxRows = 1500

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if url != nil, sheets.indices.contains(current) { workspace }
                else {
                    FileHero(format: "XLSX", symbol: "tablecells", tint: tint,
                             headline: "رتّب جدولك واحسبه في ثواني",
                             features: [
                                Feature(symbol: "pencil.and.list.clipboard", title: "تعديل الخلايا", caption: "اكتب في أي خلية مباشرة، وأضف صفوفاً وأعمدة"),
                                Feature(symbol: "arrow.up.arrow.down", title: "ترتيب", caption: "تصاعدي وتنازلي، أرقام ونصوص عربية"),
                                Feature(symbol: "sum", title: "حسابات سريعة", caption: "مجموع ومتوسط وأكبر وأصغر وعدد"),
                                Feature(symbol: "plus.forwardslash.minus", title: "ضرب وقسمة", caption: "طبّق رقماً على عمود كامل دفعة وحدة"),
                                Feature(symbol: "sparkles", title: "تنظيف", caption: "مسافات زائدة وصفوف فارغة ومكررة"),
                                Feature(symbol: "checkmark.seal.fill", title: "تدقيق عربي", caption: "يصحح إملاء النصوص داخل العمود"),
                             ],
                             dropTitle: "اسحب ملف إكسل هنا", dropSubtitle: "xlsx · csv — أو اضغط للاختيار",
                             types: ["xlsx", "xlsm", "csv", "tsv"]) { load($0[0]) }
                }
            }
            .padding(28)
        }
        .scrollContentBackground(.hidden)
        .toast($toast)
        .onChange(of: current) { column = 0; calc = nil }
        .onChange(of: sheets) {
            if !sheets.indices.contains(current) { current = 0 }
            if sheets.indices.contains(current), column >= max(sheets[current].columnCount, 1) { column = max(sheets[current].columnCount - 1, 0) }
        }
    }

    private var sheet: Sheet { sheets.indices.contains(current) ? sheets[current] : Sheet(name: "", rows: []) }
    private var headers: [String] {
        (0..<sheet.columnCount).map { i in
            let h = headerRow ? (sheet.rows.first?[i] ?? "") : ""
            return h.isEmpty ? SheetService.colName(i) : h
        }
    }
    private var dataRange: Range<Int> { min(headerRow ? 1 : 0, sheet.rows.count)..<sheet.rows.count }

    // MARK: مساحة العمل

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                FormatBadge(label: url?.pathExtension.uppercased() == "CSV" ? "CSV" : "XLSX", symbol: "tablecells", tint: tint, size: 58)
                    .rotationEffect(.degrees(-6))
                    .hoverTilt(radius: 10, tilt: 14, glow: tint, sound: false)
                VStack(alignment: .leading, spacing: 3) {
                    Text(url?.lastPathComponent ?? "").font(.title3.weight(.semibold)).lineLimit(1)
                    Text("\(sheet.rows.count) صف · \(sheet.columnCount) عمود").font(.callout).foregroundStyle(.secondary)
                }
                if sheets.count > 1 {
                    Picker("", selection: $current) {
                        ForEach(sheets.indices, id: \.self) { Text(sheets[$0].name).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                Spacer()
                Toggle("الصف الأول عناوين", isOn: $headerRow).toggleStyle(.switch).controlSize(.small)
                Menu {
                    Button("حفظ إكسل", systemImage: "tablecells") { save("xlsx") }
                    Button("حفظ CSV", systemImage: "doc.plaintext") { save("csv") }
                } label: { Label("حفظ", systemImage: "square.and.arrow.down") }
                .menuStyle(.button).buttonStyle(.glassProminent).tint(tint).fixedSize()
                Button("إغلاق", systemImage: "xmark") { url = nil; sheets = []; calc = nil }
                    .labelStyle(.iconOnly).buttonStyle(.glass)
            }

            HStack(alignment: .top, spacing: 16) {
                GlassPanel(radius: 22) { grid }
                tools.frame(width: 320)
            }
        }
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(sheet.rows.count) صف · \(sheet.columnCount) عمود").font(.caption).foregroundStyle(.secondary)
                if sheet.rows.count > maxRows {
                    Text("· يظهر أول \(maxRows) صف، والعمليات تشمل الكل").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("صف جديد", systemImage: "plus") {
                    sheets[current].rows.append(Array(repeating: "", count: max(sheet.columnCount, 1)))
                }
                .buttonStyle(.borderless).font(.caption)
                Button("عمود جديد", systemImage: "plus.rectangle") {
                    for i in sheets[current].rows.indices { sheets[current].rows[i].append("") }
                    if sheets[current].rows.isEmpty { sheets[current].rows = [[""]] }
                }
                .buttonStyle(.borderless).font(.caption)
            }
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    SwiftUI.Section {
                        ForEach(0..<min(sheet.rows.count, maxRows), id: \.self) { r in
                            HStack(spacing: 0) {
                                Text("\(r + 1)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                    .frame(width: 40)
                                ForEach(0..<sheet.columnCount, id: \.self) { c in
                                    TextField("", text: cell(r, c))
                                        .textFieldStyle(.plain)
                                        .font(r == 0 && headerRow ? .callout.weight(.semibold) : .callout)
                                        .padding(.horizontal, 8)
                                        .frame(width: cellWidth, height: 28)
                                        .background(c == column ? tint.opacity(0.08) : .clear)
                                        .overlay(Rectangle().stroke(.separator.opacity(0.5), lineWidth: 0.5))
                                }
                            }
                            .background(r == 0 && headerRow ? tint.opacity(0.12) : .clear)
                        }
                    } header: {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: 40, height: 22)
                            ForEach(0..<sheet.columnCount, id: \.self) { c in
                                Button(SheetService.colName(c)) { column = c }
                                    .buttonStyle(.plain)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(c == column ? tint : .secondary)
                                    .frame(width: cellWidth, height: 22)
                            }
                        }
                        .background(.ultraThinMaterial)
                    }
                }
            }
            .frame(minHeight: 460)
            .background(.background.opacity(0.5), in: .rect(cornerRadius: 12))
        }
    }

    private func cell(_ r: Int, _ c: Int) -> Binding<String> {
        Binding(
            get: {
                guard sheets.indices.contains(current), sheets[current].rows.indices.contains(r),
                      sheets[current].rows[r].indices.contains(c) else { return "" }
                return sheets[current].rows[r][c]
            },
            set: { v in
                guard sheets.indices.contains(current), sheets[current].rows.indices.contains(r) else { return }
                while sheets[current].rows[r].count <= c { sheets[current].rows[r].append("") }
                sheets[current].rows[r][c] = v
            }
        )
    }

    private func header(_ i: Int) -> String { headers.indices.contains(i) ? headers[i] : SheetService.colName(i) }

    // MARK: الأدوات

    private var tools: some View {
        let grid = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return VStack(spacing: 14) {
            GlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "العمود المحدد", symbol: "rectangle.split.3x1")
                    Picker("", selection: $column) {
                        ForEach(0..<sheet.columnCount, id: \.self) { Text(header($0)).tag($0) }
                    }
                    .labelsHidden()
                    GlassEffectContainer(spacing: 8) {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ActionTile(title: "تصاعدي", symbol: "arrow.up", tint: .awBlue) { sort(asc: true) }
                            ActionTile(title: "تنازلي", symbol: "arrow.down", tint: .awIndigo) { sort(asc: false) }
                        }
                    }
                }
            }
            GlassPanel(tint: tint) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "احسب", symbol: "function")
                    GlassEffectContainer(spacing: 8) {
                        LazyVGrid(columns: grid, spacing: 8) {
                            ActionTile(title: "مجموع", symbol: "sum", tint: tint) { aggregate("المجموع") { $0.reduce(0, +) } }
                            ActionTile(title: "متوسط", symbol: "divide", tint: .awTeal) {
                                aggregate("المتوسط") { $0.isEmpty ? 0 : $0.reduce(0, +) / Double($0.count) }
                            }
                            ActionTile(title: "عدد", symbol: "number", tint: .awBlue) { aggregate("العدد") { Double($0.count) } }
                            ActionTile(title: "أكبر", symbol: "arrow.up.to.line", tint: .awOrange) { aggregate("الأكبر") { $0.max() ?? 0 } }
                            ActionTile(title: "أصغر", symbol: "arrow.down.to.line", tint: .awPurple) { aggregate("الأصغر") { $0.min() ?? 0 } }
                        }
                    }
                    if let calc {
                        Text(calc).font(.system(.title2, design: .rounded).weight(.bold)).textSelection(.enabled)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .glassEffect(.regular.tint(tint.opacity(0.2)), in: .rect(cornerRadius: 14))
                            .transition(.scale.combined(with: .opacity))
                    }
                    Divider().opacity(0.4)
                    HStack(spacing: 8) {
                        TextField("الرقم", text: $operand).textFieldStyle(.roundedBorder).frame(width: 64)
                        GlassEffectContainer(spacing: 6) {
                            HStack(spacing: 6) {
                                ForEach([("multiply", "×"), ("divide", "÷"), ("plus", "+"), ("minus", "−")], id: \.1) { item in
                                    Button {
                                        SoundFX.play(.tap)
                                        switch item.1 {
                                        case "×": apply { $0 * $1 }
                                        case "÷": apply { $1 == 0 ? $0 : $0 / $1 }
                                        case "+": apply { $0 + $1 }
                                        default: apply { $0 - $1 }
                                        }
                                    } label: {
                                        Image(systemName: item.0).font(.system(size: 14, weight: .bold)).frame(width: 22, height: 22)
                                    }
                                    .buttonStyle(.glass)
                                }
                            }
                        }
                    }
                    Text("يطبّق الرقم على العمود المحدد").font(.caption2).foregroundStyle(.secondary)
                }
                .animation(.smooth, value: calc)
            }
            GlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "نظّف", symbol: "sparkles")
                    GlassEffectContainer(spacing: 8) {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ActionTile(title: "المسافات", symbol: "text.badge.minus", tint: .awTeal) { trim() }
                            ActionTile(title: "الصفوف الفارغة", symbol: "rectangle.badge.minus", tint: .awOrange) { dropEmpty() }
                            ActionTile(title: "المكرر", symbol: "square.on.square", tint: .awPink) { dedupe() }
                            ActionTile(title: "تدقيق عربي", symbol: "checkmark.seal.fill", tint: .awGreen) { proofColumn() }
                        }
                    }
                }
            }
        }
    }

    // MARK: العمليات

    private func load(_ u: URL) {
        do {
            sheets = try SheetService.open(u)
            url = u; current = 0; column = 0; calc = nil
        } catch { toast = Toast(text: error.localizedDescription, isError: true) }
    }

    private func numbers() -> [Double] {
        dataRange.compactMap { r in
            sheet.rows[r].indices.contains(column) ? SheetService.number(sheet.rows[r][column]) : nil
        }
    }

    private func aggregate(_ name: String, _ f: ([Double]) -> Double) {
        let ns = numbers()
        guard !ns.isEmpty else { toast = Toast(text: "العمود «\(header(column))» ما فيه أرقام", isError: true); return }
        calc = "\(name): \(SheetService.format(f(ns)))"
    }

    private func apply(_ f: (Double, Double) -> Double) {
        guard let k = SheetService.number(operand) else { toast = Toast(text: "اكتب رقماً صحيحاً", isError: true); return }
        var n = 0
        for r in dataRange where sheets[current].rows[r].indices.contains(column) {
            if let v = SheetService.number(sheets[current].rows[r][column]) {
                sheets[current].rows[r][column] = SheetService.format(f(v, k)); n += 1
            }
        }
        toast = Toast(text: "عُدّلت \(n) خلية في «\(header(column))»")
    }

    private func sort(asc: Bool) {
        let head = headerRow && !sheet.rows.isEmpty ? [sheet.rows[0]] : []
        var rest = Array(sheet.rows[dataRange])
        let c = column
        rest.sort { a, b in
            let x = a.indices.contains(c) ? a[c] : "", y = b.indices.contains(c) ? b[c] : ""
            if let nx = SheetService.number(x), let ny = SheetService.number(y) { return asc ? nx < ny : nx > ny }
            let o = x.localizedStandardCompare(y)
            return asc ? o == .orderedAscending : o == .orderedDescending
        }
        sheets[current].rows = head + rest
        toast = Toast(text: "رُتّب حسب «\(header(c))»")
    }

    private func trim() {
        var n = 0
        for r in sheets[current].rows.indices {
            for c in sheets[current].rows[r].indices {
                let v = sheets[current].rows[r][c]
                let t = v.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                if t != v { sheets[current].rows[r][c] = t; n += 1 }
            }
        }
        toast = Toast(text: "نُظّفت \(n) خلية")
    }

    private func dropEmpty() {
        let before = sheet.rows.count
        sheets[current].rows.removeAll { $0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        toast = Toast(text: "حُذف \(before - sheet.rows.count) صف فارغ")
    }

    private func dedupe() {
        var seen = Set<[String]>()
        let head = headerRow && !sheet.rows.isEmpty ? [sheet.rows[0]] : []
        let kept = sheet.rows[dataRange].filter { seen.insert($0).inserted }
        let removed = sheet.rows.count - head.count - kept.count
        sheets[current].rows = head + kept
        toast = Toast(text: "حُذف \(removed) صف مكرر")
    }

    private func proofColumn() {
        var n = 0
        for r in dataRange where sheets[current].rows[r].indices.contains(column) {
            let v = sheets[current].rows[r][column]
            let f = ArabicLinter.fix(v, englishOnOwnLine: false)
            if f != v && !v.isEmpty { sheets[current].rows[r][column] = f; n += 1 }
        }
        toast = Toast(text: "دُقّقت \(n) خلية")
    }

    private func save(_ ext: String) {
        let base = (url?.deletingPathExtension().lastPathComponent ?? "جدول") + " - مرتب"
        guard let out = Panels.save(name: base, ext: ext) else { return }
        do {
            if ext == "csv" { try SheetService.saveCSV(sheet, to: out) }
            else { try SheetService.saveXLSX(sheets, to: out) }
            toast = Toast(text: "حُفظ «\(out.lastPathComponent)»")
        } catch { toast = Toast(text: error.localizedDescription, isError: true) }
    }
}
