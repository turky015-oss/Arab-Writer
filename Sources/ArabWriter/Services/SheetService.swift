import Foundation

struct Sheet: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var rows: [[String]]

    var columnCount: Int { rows.map(\.count).max() ?? 0 }

    mutating func normalize() {
        let n = max(columnCount, 1)
        rows = rows.map { $0 + Array(repeating: "", count: max(0, n - $0.count)) }
    }
}

/// قراءة وكتابة xlsx و csv بأدوات النظام (unzip و zip) بلا مكتبات خارجية.
enum SheetService {
    // MARK: قراءة

    static func open(_ url: URL) throws -> [Sheet] {
        switch url.pathExtension.lowercased() {
        case "csv", "tsv", "txt":
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { throw ToolError.open(url.lastPathComponent) }
            let sep: Character = url.pathExtension.lowercased() == "tsv" ? "\t" : ","
            var s = Sheet(name: url.deletingPathExtension().lastPathComponent, rows: parseCSV(raw, sep: sep))
            s.normalize()
            return [s]
        case "xlsx", "xlsm":
            return try readXLSX(url)
        default:
            throw ToolError.invalid("الصيغة غير مدعومة. افتح xlsx أو csv.")
        }
    }

    static func parseCSV(_ text: String, sep: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var it = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        if it.first == "\u{FEFF}" { it.removeFirst() }
        var i = 0
        while i < it.count {
            let c = it[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < it.count && it[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else { field.append(c) }
            } else if c == "\"" {
                quoted = true
            } else if c == sep {
                row.append(field); field = ""
            } else if c == "\n" {
                row.append(field); rows.append(row); row = []; field = ""
            } else {
                field.append(c)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    private static func run(_ tool: String, _ args: [String], cwd: URL? = nil) throws -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw ToolError.invalid("تعذّر قراءة الملف.") }
        return data
    }

    private static func entry(_ url: URL, _ path: String) -> Data? {
        try? run("/usr/bin/unzip", ["-p", url.path, path])
    }

    static func readXLSX(_ url: URL) throws -> [Sheet] {
        guard let list = try? run("/usr/bin/unzip", ["-Z1", url.path]) else { throw ToolError.open(url.lastPathComponent) }
        let files = String(decoding: list, as: UTF8.self).split(separator: "\n").map(String.init)

        var shared: [String] = []
        if let d = entry(url, "xl/sharedStrings.xml") { shared = SharedStringsParser.parse(d) }

        // أسماء الأوراق وترتيبها من workbook.xml وملف العلاقات
        var order: [(name: String, path: String)] = []
        if let wb = entry(url, "xl/workbook.xml"), let rels = entry(url, "xl/_rels/workbook.xml.rels") {
            let targets = RelsParser.parse(rels)
            for (name, rid) in WorkbookParser.parse(wb) {
                if var t = targets[rid] {
                    if t.hasPrefix("/") { t.removeFirst() } else { t = "xl/" + t }
                    order.append((name, t))
                }
            }
        }
        if order.isEmpty {
            let sheets = files.filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }.sorted()
            order = sheets.enumerated().map { ("ورقة \($0.offset + 1)", $0.element) }
        }

        var out: [Sheet] = []
        for (name, path) in order {
            guard let d = entry(url, path) else { continue }
            var s = Sheet(name: name, rows: WorksheetParser.parse(d, shared: shared))
            s.normalize()
            out.append(s)
        }
        guard !out.isEmpty else { throw ToolError.open(url.lastPathComponent) }
        return out
    }

    // MARK: كتابة

    static func saveCSV(_ s: Sheet, to url: URL) throws {
        let body = s.rows.map { row in
            row.map { v in
                v.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
                    ? "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : v
            }.joined(separator: ",")
        }.joined(separator: "\n")
        // BOM حتى يفتحه إكسل بالعربي صحيحاً
        guard (try? ("\u{FEFF}" + body).write(to: url, atomically: true, encoding: .utf8)) != nil else {
            throw ToolError.write(url.lastPathComponent)
        }
    }

    static func saveXLSX(_ sheets: [Sheet], to url: URL) throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("aw-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: dir) }
        func put(_ path: String, _ s: String) throws {
            let u = dir.appendingPathComponent(path)
            try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try s.write(to: u, atomically: true, encoding: .utf8)
        }
        let n = sheets.count
        try put("[Content_Types].xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\((1...n).map { "<Override PartName=\"/xl/worksheets/sheet\($0).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>" }.joined())</Types>
        """)
        try put("_rels/.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
        """)
        try put("xl/workbook.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><bookViews><workbookView/></bookViews><sheets>\(sheets.enumerated().map { "<sheet name=\"\(xml(String($0.element.name.prefix(31))))\" sheetId=\"\($0.offset + 1)\" r:id=\"rId\($0.offset + 1)\"/>" }.joined())</sheets></workbook>
        """)
        try put("xl/_rels/workbook.xml.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\((1...n).map { "<Relationship Id=\"rId\($0)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0).xml\"/>" }.joined())<Relationship Id="rId\(n + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
        """)
        try put("xl/styles.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="12"/><name val="Arial"/></font><font><b/><sz val="12"/><name val="Arial"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="2"><xf fontId="0"/><xf fontId="1" applyFont="1"/></cellXfs></styleSheet>
        """)
        for (i, s) in sheets.enumerated() {
            var rowsXML = ""
            for (r, row) in s.rows.enumerated() {
                var cells = ""
                for (c, v) in row.enumerated() where !v.isEmpty {
                    let ref = colName(c) + "\(r + 1)"
                    let style = r == 0 ? " s=\"1\"" : ""
                    if let num = Double(v.replacingOccurrences(of: ",", with: "")), !v.hasPrefix("0") || v == "0" || v.hasPrefix("0.") {
                        cells += "<c r=\"\(ref)\"\(style)><v>\(num)</v></c>"
                    } else {
                        cells += "<c r=\"\(ref)\" t=\"inlineStr\"\(style)><is><t xml:space=\"preserve\">\(xml(v))</t></is></c>"
                    }
                }
                rowsXML += "<row r=\"\(r + 1)\">\(cells)</row>"
            }
            try put("xl/worksheets/sheet\(i + 1).xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView rightToLeft="1" workbookViewId="0"/></sheetViews><sheetData>\(rowsXML)</sheetData></worksheet>
            """)
        }
        try? fm.removeItem(at: url)
        _ = try run("/usr/bin/zip", ["-q", "-X", "-r", url.path, "[Content_Types].xml", "_rels", "xl"], cwd: dir)
    }

    static func colName(_ i: Int) -> String {
        var n = i + 1, s = ""
        while n > 0 {
            let r = (n - 1) % 26
            s = String(UnicodeScalar(65 + r)!) + s
            n = (n - 1) / 26
        }
        return s
    }

    static func colIndex(_ ref: String) -> Int {
        var n = 0
        for ch in ref.uppercased() {
            guard let a = ch.asciiValue, a >= 65, a <= 90 else { break }
            n = n * 26 + Int(a - 64)
        }
        return max(n - 1, 0)
    }

    static func xml(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: عمليات

    static func number(_ s: String) -> Double? {
        let latin = String(s.map { ch -> Character in
            if let v = ch.unicodeScalars.first?.value, (0x0660...0x0669).contains(v) { return Character(String(v - 0x0660)) }
            if ch == "٫" { return "." }
            return ch
        })
        return Double(latin.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "٬", with: "")
            .trimmingCharacters(in: .whitespaces))
    }

    static func format(_ d: Double) -> String {
        if d == d.rounded() && abs(d) < 1e15 { return String(Int64(d)) }
        let f = NumberFormatter()
        f.maximumFractionDigits = 4
        f.minimumFractionDigits = 0
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: NSNumber(value: d)) ?? "\(d)"
    }
}

// MARK: - محللات XML

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    var out: [String] = []
    var cur = ""
    var inT = false
    var inSI = false
    var inRPh = false

    static func parse(_ d: Data) -> [String] {
        let p = SharedStringsParser()
        let x = XMLParser(data: d)
        x.delegate = p
        x.parse()
        return p.out
    }

    func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch e {
        case "si": inSI = true; cur = ""
        case "t": inT = true
        case "rPh": inRPh = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters s: String) {
        if inSI && inT && !inRPh { cur += s }
    }

    func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        switch e {
        case "si": out.append(cur); inSI = false
        case "t": inT = false
        case "rPh": inRPh = false
        default: break
        }
    }
}

private final class WorkbookParser: NSObject, XMLParserDelegate {
    var out: [(String, String)] = []
    static func parse(_ d: Data) -> [(String, String)] {
        let p = WorkbookParser()
        let x = XMLParser(data: d)
        x.delegate = p
        x.parse()
        return p.out
    }
    func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        if e == "sheet", let name = a["name"], let rid = a["r:id"] ?? a.first(where: { $0.key.hasSuffix(":id") })?.value {
            out.append((name, rid))
        }
    }
}

private final class RelsParser: NSObject, XMLParserDelegate {
    var out: [String: String] = [:]
    static func parse(_ d: Data) -> [String: String] {
        let p = RelsParser()
        let x = XMLParser(data: d)
        x.delegate = p
        x.parse()
        return p.out
    }
    func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        if e == "Relationship", let id = a["Id"], let t = a["Target"] { out[id] = t }
    }
}

private final class WorksheetParser: NSObject, XMLParserDelegate {
    let shared: [String]
    var rows: [Int: [Int: String]] = [:]
    var curRow = 0
    var curCol = 0
    var type = ""
    var buf = ""
    var capturing = false
    var nextCol = 0

    init(shared: [String]) { self.shared = shared }

    static func parse(_ d: Data, shared: [String]) -> [[String]] {
        let p = WorksheetParser(shared: shared)
        let x = XMLParser(data: d)
        x.delegate = p
        x.parse()
        guard let maxRow = p.rows.keys.max() else { return [] }
        let maxCol = p.rows.values.flatMap(\.keys).max() ?? 0
        return (0...maxRow).map { r in (0...maxCol).map { c in p.rows[r]?[c] ?? "" } }
    }

    func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        switch e {
        case "row":
            curRow = (Int(a["r"] ?? "") ?? (curRow + 1)) - 1
            nextCol = 0
        case "c":
            if let r = a["r"] { curCol = SheetService.colIndex(r) } else { curCol = nextCol }
            nextCol = curCol + 1
            type = a["t"] ?? ""
            buf = ""
        case "v", "t":
            capturing = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters s: String) {
        if capturing { buf += s }
    }

    func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        switch e {
        case "v", "t": capturing = false
        case "c":
            var v = buf
            if type == "s", let i = Int(buf), i < shared.count { v = shared[i] }
            else if type == "b" { v = buf == "1" ? "TRUE" : "FALSE" }
            else if type.isEmpty || type == "n", let d = Double(buf) { v = SheetService.format(d) }
            if !v.isEmpty { rows[curRow, default: [:]][curCol] = v }
        default: break
        }
    }
}
