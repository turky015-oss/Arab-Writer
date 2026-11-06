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
                PageHeader(title: "إكسل", subtitle: "رتّب، نظّف، احسب، وعدّل الخلايا", symbol: "tablecells", tint: tint)
                if url != nil, sheets.indices.contains(current) { workspace }
                else {
                    DropZone(title: "اسحب ملف إكسل هنا", subtitle: "xlsx · csv — أو اضغط للاختيار",
                             symbol: "tablecells", tint: tint, types: ["xlsx", "xlsm", "csv", "tsv"]) { load($0[0]) }
                }
            }
            .padding(28)
        }
        .scrollContentBackground(.hidden)
        .toast($toast)
    }

    private var sheet: Sheet { sheets[current] }
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
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 10) {
                    Label(url?.lastPathComponent ?? "", systemImage: "tablecells.fill")
                        .font(.headline).lineLimit(1)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .glassEffect(.regular.tint(tint.opacity(0.12)), in: .capsule)
                    if sheets.count > 1 {
                        Picker("", selection: $current) {
                            ForEach(sheets.indices, id: \.self) { Text(sheets[$0].name).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                    }
                    Toggle("الصف الأول عناوين", isOn: $headerRow).toggleStyle(.switch).controlSize(.small)
                    Spacer()
                    Menu {
                        Button("حفظ إكسل", systemImage: "tablecells") { save("xlsx") }
                        Button("حفظ CSV", systemImage: "doc.plaintext") { save("csv") }
                    } label: { Label("حفظ", systemImage: "square.and.arrow.down") }
                    .menuStyle(.button).buttonStyle(.glassProminent).tint(tint).fixedSize()
                    Button("إغلاق", systemImage: "xmark") { url = nil; sheets = []; calc = nil }
                        .labelStyle(.iconOnly).buttonStyle(.glass)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                GlassPanel(radius: 22) { grid }
                tools.frame(width: 300)
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
            get: { sheets[current].rows[r].indices.contains(c) ? sheets[current].rows[r][c] : "" },
            set: { v in
                while sheets[current].rows[r].count <= c { sheets[current].rows[r].append("") }
                sheets[current].rows[r][c] = v
            }
        )
    }

    // MARK: الأدوات

    private var tools: some View {
        VStack(spacing: 14) {
            GlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "العمود", symbol: "rectangle.split.3x1")
                    Picker("", selection: $column) {
                        ForEach(0..<sheet.columnCount, id: \.self) { Text(headers[$0]).tag($0) }
                    }
                    .labelsHidden()
                    HStack {
                        Button("تصاعدي", systemImage: "arrow.up") { sort(asc: true) }
                        Button("تنازلي", systemImage: "arrow.down") { sort(asc: false) }
                    }
                    .buttonStyle(.glass)
                }
            }
            GlassPanel(tint: tint) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "احسب", symbol: "function")
                    HStack {
                        Button("مجموع") { aggregate("المجموع") { $0.reduce(0, +) } }
                        Button("متوسط") { aggregate("المتوسط") { $0.isEmpty ? 0 : $0.reduce(0, +) / Double($0.count) } }
                    }
                    HStack {
                        Button("أكبر") { aggregate("الأكبر") { $0.max() ?? 0 } }
                        Button("أصغر") { aggregate("الأصغر") { $0.min() ?? 0 } }
                        Button("عدد") { aggregate("العدد") { Double($0.count) } }
                    }
                    if let calc {
                        Text(calc).font(.system(.title3, design: .rounded).weight(.bold)).textSelection(.enabled)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Divider().opacity(0.4)
                    HStack {
                        TextField("الرقم", text: $operand).textFieldStyle(.roundedBorder).frame(width: 70)
                        Button("×") { apply { $0 * $1 } }
                        Button("÷") { apply { $1 == 0 ? $0 : $0 / $1 } }
                        Button("+") { apply { $0 + $1 } }
                        Button("−") { apply { $0 - $1 } }
                    }
                    Text("يطبّق على العمود المحدد").font(.caption2).foregroundStyle(.secondary)
                }
                .buttonStyle(.glass)
                .animation(.smooth, value: calc)
            }
            GlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "نظّف", symbol: "sparkles")
                    Button("احذف المسافات الزائدة", systemImage: "text.badge.minus") { trim() }
                    Button("احذف الصفوف الفارغة", systemImage: "rectangle.badge.minus") { dropEmpty() }
                    Button("احذف المكرر", systemImage: "square.on.square") { dedupe() }
                    Button("دقّق النص العربي في العمود", systemImage: "checkmark.seal") { proofColumn() }
                }
                .buttonStyle(.glass)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        guard !ns.isEmpty else { toast = Toast(text: "العمود «\(headers[column])» ما فيه أرقام", isError: true); return }
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
        toast = Toast(text: "عُدّلت \(n) خلية في «\(headers[column])»")
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
        toast = Toast(text: "رُتّب حسب «\(headers[c])»")
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
