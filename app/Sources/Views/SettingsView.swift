import SwiftUI

/// Settings: interface language, JS timeout, tracker blocking, default User-Agent.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ModuleStore
    @EnvironmentObject private var presets: PresetStore
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var monitor: MonitorScheduler
    @EnvironmentObject private var tester: MassTester
    @EnvironmentObject private var debugLog: DebugLog

    @State private var showHistory = false

    /// Champs de saisie de l'écran (pour pouvoir fermer le clavier à coup sûr).
    private enum Field: Hashable { case patterns, userAgent, webhook }
    @FocusState private var focusedField: Field?

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

            Section {
                Toggle(L("Cloudflare bypass"), isOn: $settings.cloudflareBypass)
                if settings.cloudflareBypass {
                    Button(L("Reset Cloudflare clearances")) {
                        CloudflareBypass.shared.reset()
                    }
                }
            } footer: {
                Text(L("When a module hits a « Just a moment… » page, the challenge is solved in a hidden web view and the resulting cookies (and its User-Agent) are reused for the module's requests."))
            }

            Section {
                Toggle(L("Check stream links"), isOn: $settings.checkStreams)
            } footer: {
                Text(L("In mass test, probes every returned stream URL (with its headers) to detect dead servers, 403 (wrong headers), timeouts…"))
            }

            Section {
                Toggle(L("Scheduled monitoring"), isOn: $settings.monitorEnabled)
                if settings.monitorEnabled {
                    Picker(L("Interval"), selection: $settings.monitorHours) {
                        ForEach(AppSettings.monitorChoices, id: \.self) { hours in
                            Text(hours < 1 ? "30 min" : "\(Int(hours)) h").tag(hours)
                        }
                    }
                    Picker(L("Monitored preset"), selection: $settings.monitorPresetName) {
                        Text(L("All modules")).tag("")
                        ForEach(presets.presets) { preset in
                            Text(preset.name).tag(preset.name)
                        }
                    }
                    Toggle(L("Notify only on regression"), isOn: $settings.monitorOnlyOnRegression)
                    if let last = monitor.lastRun {
                        LabeledContent(L("Last run"),
                                       value: last.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let outcome = monitor.lastOutcome {
                        LabeledContent(L("Last result"), value: outcome)
                    }
                    Button {
                        Task {
                            await monitor.run(store: store, tester: tester, presets: presets,
                                              history: history, debugLog: debugLog,
                                              settings: settings, source: "Manual monitor")
                        }
                    } label: {
                        Label(L("Run monitoring now"), systemImage: "play.circle")
                    }
                    .disabled(monitor.isRunning || tester.isRunning)
                }
            } header: {
                Text(L("Monitoring"))
            } footer: {
                Text(L("Re-runs the selected preset on a schedule and reports regressions. Runs reliably while the app is open; iOS only allows best-effort background runs."))
            }

            Section {
                Button {
                    showHistory = true
                } label: {
                    Label("\(L("History")) (\(history.runs.count))", systemImage: "clock.arrow.circlepath")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Discord webhook")).font(.caption).foregroundStyle(.secondary)
                    TextField("https://discord.com/api/webhooks/…",
                              text: $settings.discordWebhook, axis: .vertical)
                        .focused($focusedField, equals: .webhook)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1...3)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Toggle(L("Send automatically after a mass test"), isOn: $settings.autoSendReport)
                    .disabled(!settings.hasWebhook)
            } footer: {
                Text(L("Posts the mass test summary to a Discord channel. Leave empty to disable."))
            }

            if settings.blockWebhooks {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Blocked URL patterns (one per line)"))
                            .font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $settings.blockedPatternsText)
                            .focused($focusedField, equals: .patterns)
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
                        .focused($focusedField, equals: .userAgent)
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
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showHistory) { HistoryView() }
        .navigationTitle(L("Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("Done")) { focusedField = nil }
            }
        }
    }
}
