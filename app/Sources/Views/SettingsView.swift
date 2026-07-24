import SwiftUI

/// Settings: interface language, JS timeout, tracker blocking, default User-Agent.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ModuleStore

    var body: some View {
        Form {
            Section(L("Interface")) {
                Picker(L("Language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang)
                    }
                }
            }

            Section(L("Module execution")) {
                VStack(alignment: .leading) {
                    HStack {
                        Text(L("Max delay"))
                        Spacer()
                        Text("\(Int(settings.jsTimeout)) s").foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.jsTimeout, in: 5...120, step: 5)
                }
                Toggle(L("Block trackers"), isOn: $settings.blockWebhooks)
            }

            if settings.blockWebhooks {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Blocked URL patterns (one per line)"))
                            .font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $settings.blockedPatternsText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 90)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }
            }

            Section(L("Network")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Default User-Agent")).font(.caption).foregroundStyle(.secondary)
                    TextField("User-Agent", text: $settings.defaultUserAgent, axis: .vertical)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1...4)
                }
            }

            Section(L("Installed modules")) {
                Text("\(store.modules.count)")
                    .foregroundStyle(.secondary)
            }

            Section {
                Link(destination: URL(string: "https://git.luna-app.eu/MXFia19/sources")!) {
                    Label(L("Luna source"), systemImage: "chevron.left.forwardslash.chevron.right")
                }
            } footer: {
                Text(L("App to test « Sora » modules. No AniList/social features."))
            }
        }
        .navigationTitle(L("Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneToolbar()
    }
}
