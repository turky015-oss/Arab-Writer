import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var key = ""
    @State private var saved = false
    @State private var sounds = SoundFX.enabled

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

            SwiftUI.Section("الواجهة") {
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
