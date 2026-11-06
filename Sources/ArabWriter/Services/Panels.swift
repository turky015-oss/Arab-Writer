import AppKit
import UniformTypeIdentifiers

/// نوافذ الفتح والحفظ الأصلية في الماك.
@MainActor
enum Panels {
    static func open(types: [String], multiple: Bool = false) -> [URL]? {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = multiple
        p.canChooseDirectories = false
        p.allowedContentTypes = types.compactMap { UTType(filenameExtension: $0) }
        p.prompt = "فتح"
        return p.runModal() == .OK ? p.urls : nil
    }

    static func save(name: String, ext: String) -> URL? {
        let p = NSSavePanel()
        p.nameFieldStringValue = name.hasSuffix("." + ext) ? name : "\(name).\(ext)"
        if let t = UTType(filenameExtension: ext) { p.allowedContentTypes = [t] }
        p.canCreateDirectories = true
        p.prompt = "حفظ"
        return p.runModal() == .OK ? p.url : nil
    }

    static func folder() -> URL? {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.canCreateDirectories = true
        p.prompt = "اختيار"
        return p.runModal() == .OK ? p.url : nil
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
