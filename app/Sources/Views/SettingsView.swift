import SwiftUI

/// Réglages : timeout JS, blocage des trackers, User-Agent par défaut.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ModuleStore

    var body: some View {
        Form {
            Section("Exécution des modules") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Délai maximum")
                        Spacer()
                        Text("\(Int(settings.jsTimeout)) s").foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.jsTimeout, in: 5...120, step: 5)
                }
                Toggle("Bloquer les trackers", isOn: $settings.blockWebhooks)
            }

            if settings.blockWebhooks {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Motifs d'URL bloqués (un par ligne)")
                            .font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $settings.blockedPatternsText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 90)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                } footer: {
                    Text("Toute requête fetchv2 dont l'URL contient un de ces motifs est bloquée (réponse vide). Pour le tracking Supabase, ajoute l'endpoint exact, p. ex. « projet.supabase.co/rest/v1/tracking ». Ne bloque pas tout « supabase.co » si un module y lit aussi ses données.")
                }
            }

            Section("Réseau") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("User-Agent par défaut").font(.caption).foregroundStyle(.secondary)
                    TextField("User-Agent", text: $settings.defaultUserAgent, axis: .vertical)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1...4)
                }
            }

            Section("Modules installés") {
                Text("\(store.modules.count) module(s)")
                    .foregroundStyle(.secondary)
            }

            Section {
                Link(destination: URL(string: "https://github.com/MXFia19/module-sora")!) {
                    Label("Dépôt module-sora", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            } footer: {
                Text("App de test des modules « Sora ». Aucune fonctionnalité AniList/social.")
            }
        }
        .navigationTitle("Réglages")
        .navigationBarTitleDisplayMode(.inline)
    }
}
