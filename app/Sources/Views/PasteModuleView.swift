import SwiftUI

/// Ajoute un module en collant directement son code JS (test local),
/// avec possibilité de remplacer le script d'un module déjà installé.
struct PasteModuleView: View {
    @EnvironmentObject private var store: ModuleStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type = ""
    @State private var language = ""
    @State private var script = ""
    @State private var overwriteTarget: LoadedModule?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Cible", selection: $overwriteTarget) {
                        Text("Nouveau module local").tag(LoadedModule?.none)
                        ForEach(store.modules) { module in
                            Text(module.name).tag(LoadedModule?.some(module))
                        }
                    }
                } footer: {
                    Text(overwriteTarget == nil
                         ? "Crée un module local à partir du code collé."
                         : "Remplace le script du module sélectionné (conserve son manifest).")
                }

                if overwriteTarget == nil {
                    Section("Métadonnées") {
                        TextField("Nom", text: $name)
                        TextField("Type (anime, shows/movies, manga…)", text: $type)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Langue (optionnel)", text: $language)
                    }
                }

                Section("Code JS") {
                    TextEditor(text: $script)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 220)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Coller un module")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") { save() }
                        .disabled(script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        store.addPasted(
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            language: language,
            script: script,
            overwriting: overwriteTarget
        )
        dismiss()
    }
}
