import SwiftUI
import UIKit

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
    @State private var moduleToTest: LoadedModule?

    private var scriptEmpty: Bool {
        script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
                    if let target = overwriteTarget {
                        Button {
                            script = target.scriptContent
                        } label: {
                            Label("Charger le code actuel du module", systemImage: "arrow.down.doc")
                        }
                    }
                } footer: {
                    Text(overwriteTarget == nil
                         ? "Crée un module local à partir du code collé."
                         : "Remplace le script du module sélectionné (conserve son manifest). Le code actuel est chargé dans l'éditeur pour que tu puisses le modifier.")
                }

                if overwriteTarget == nil {
                    Section("Métadonnées") {
                        TextField("Nom", text: $name)
                        TextField("Type (anime, shows/movies, manga…)", text: $type)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Langue (optionnel)", text: $language)
                    }
                }

                Section {
                    TextEditor(text: $script)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 220)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    HStack {
                        Text("Code JS")
                        Spacer()
                        Button {
                            if let s = UIPasteboard.general.string { script = s }
                        } label: { Label("Coller", systemImage: "doc.on.clipboard") }
                            .textCase(nil)
                        Button(role: .destructive) {
                            script = ""
                        } label: { Label("Effacer", systemImage: "xmark.circle") }
                            .textCase(nil)
                            .disabled(scriptEmpty)
                    }
                }

                Section {
                    Button {
                        if let module = save() { moduleToTest = module }
                    } label: {
                        Label("Enregistrer & tester", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(scriptEmpty)
                }
            }
            .navigationTitle("Coller un module")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneToolbar()
            .onChange(of: overwriteTarget) { newValue in
                // Précharge le code du module ciblé (si l'éditeur est vide).
                if let target = newValue, scriptEmpty {
                    script = target.scriptContent
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") { _ = save(); dismiss() }
                        .disabled(scriptEmpty)
                }
            }
            .fullScreenCover(item: $moduleToTest) { module in
                NavigationStack {
                    ModuleTestView(module: module)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Fermer") { moduleToTest = nil }
                            }
                        }
                }
            }
        }
    }

    @discardableResult
    private func save() -> LoadedModule? {
        guard !scriptEmpty else { return nil }
        return store.addPasted(
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            language: language,
            script: script,
            overwriting: overwriteTarget
        )
    }
}
