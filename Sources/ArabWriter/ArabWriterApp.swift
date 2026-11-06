import SwiftUI
import AppKit

@main
struct ArabWriterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage("menuBar") private var showMenuBar = true

    var body: some Scene {
        WindowGroup("Arab Writer", id: "main") {
            ContentView()
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
                .frame(minWidth: 1000, minHeight: 680)
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("انتقال") {
                Button("ابحث أو انتقل") { Router.shared.palette.toggle() }
                    .keyboardShortcut("k", modifiers: .command)
                Divider()
                ForEach(AppSection.allCases) { s in
                    Button(s.title) { Router.shared.section = s }
                        .keyboardShortcut(KeyEquivalent(s.shortcut), modifiers: .command)
                }
            }
            CommandGroup(replacing: .help) {
                Link("صفحة المشروع", destination: URL(string: "https://github.com/turky015-oss/Arab-Writer")!)
            }
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            QuickCheckView()
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
        } label: {
            Image(systemName: "text.badge.checkmark")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ArabicFont.registerBundled()
        NSApp.servicesProvider = ServiceProvider.shared
        NSUpdateDynamicServices()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// مع أيقونة شريط القوائم يبقى البرنامج شغالاً بعد إغلاق النافذة.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(UserDefaults.standard.object(forKey: "menuBar") as? Bool ?? true)
    }
}
