import SwiftUI
import AppKit

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var key = ""
    @State private var saved = false
    @State private var sounds = SoundFX.enabled
    @AppStorage("menuBar") private var menuBar = true

    var body: some View {
        Form {
            SwiftUI.Section {
                HStack {
                    Circle().fill(settings.hasKey ? Color.awGreen : Color.awOrange).frame(width: 9, height: 9)
                    Text(settings.hasKey ? "المفتاح محفوظ في سلسلة المفاتيح" : "لا يوجد مفتاح")
                    Spacer()
                    if settings.hasKey {
                        Button("حذف المفتاح", role: .destructive) { settings.removeKey() }
                    }
                }
                SecureField("الصق مفتاحك هنا", text: $key)
                HStack {
                    Link("احصل على مفتاح من Anthropic", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                        .font(.caption)
                    Spacer()
                    if saved { Label("حُفظ", systemImage: "checkmark").foregroundStyle(Color.awGreen) }
                    Button("حفظ") {
                        settings.setKey(key)
                        key = ""
                        saved = true
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("مفتاح Claude")
            } footer: {
                Text("المفتاح يبقى على جهازك في سلسلة المفاتيح، ويُرسل مباشرة إلى Anthropic فقط. الفاحص وأدوات الملفات تعمل بدونه.")
            }

            SwiftUI.Section("النموذج") {
                Picker("النموذج", selection: $settings.model) {
                    ForEach(AppSettings.models, id: \.id) { Text($0.name).tag($0.id) }
                }
            }

            SwiftUI.Section("الكتابة") {
                Toggle("ضع كل كلمة إنجليزية في سطر مستقل", isOn: $settings.englishOnOwnLine)
                Toggle("جولة تصحيح ثانية تلقائية إن بقيت أخطاء", isOn: $settings.autoRetry)
            }

            SwiftUI.Section {
                Label("ظلّل أي نص في أي برنامج ← كليك يمين ← الخدمات", systemImage: "cursorarrow.click.2")
                Label("صحّح الإملاء والترقيم: فوري وبدون إنترنت", systemImage: "checkmark.seal")
                Label("أعد الصياغة بصوت بشري: يحتاج المفتاح", systemImage: "wand.and.stars")
                Label("افتح النص في البرنامج", systemImage: "arrow.up.forward.app")
                Button("افتح إعدادات الخدمات في النظام") {
                    if let u = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                        NSWorkspace.shared.open(u)
                    }
                }
            } header: {
                Text("دقّق من أي برنامج")
            } footer: {
                Text("إذا ما ظهرت الخدمات: لوحة المفاتيح ← اختصارات لوحة المفاتيح ← الخدمات ← النص، وفعّل خدمات Arab Writer. وتقدر تعطيها اختصاراً.")
            }

            SwiftUI.Section("الواجهة") {
                Toggle("أيقونة الفحص السريع في شريط القوائم", isOn: $menuBar)
                Toggle("أصوات الواجهة", isOn: $sounds)
                    .onChange(of: sounds) {
                        UserDefaults.standard.set(sounds, forKey: "sounds")
                        if sounds { SoundFX.play(.success) }
                    }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.model) { settings.persist() }
        .onChange(of: settings.englishOnOwnLine) { settings.persist() }
        .onChange(of: settings.autoRetry) { settings.persist() }
        .frame(width: 520)
        .padding(.vertical, 8)
    }
}
