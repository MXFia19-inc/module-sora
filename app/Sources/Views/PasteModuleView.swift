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
    @State private var jumpLine: Int?
    @State private var syntaxIssue: SyntaxCheck.Issue?
    @State private var syntaxChecked = false

    private var scriptEmpty: Bool {
        script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L("Target"), selection: $overwriteTarget) {
                        Text(L("New local module")).tag(LoadedModule?.none)
                        ForEach(store.modules) { module in
                            Text(module.name).tag(LoadedModule?.some(module))
                        }
                    }
                    if let target = overwriteTarget {
                        Button {
                            script = target.scriptContent
                        } label: {
                            Label(L("Load the module's current code"), systemImage: "arrow.down.doc")
                        }
                    }
                } footer: {
                    Text(overwriteTarget == nil
                         ? L("Creates a local module from the pasted code.")
                         : L("Replaces the selected module's script (keeps its manifest). The current code is loaded into the editor so you can edit it."))
                }

                if overwriteTarget == nil {
                    Section(L("Metadata")) {
                        TextField(L("Name"), text: $name)
                        TextField(L("Type (anime, shows/movies, manga…)"), text: $type)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField(L("Language (optional)"), text: $language)
                    }
                }

                Section {
                    CodeEditorView(text: $script, jumpLine: $jumpLine)
                        .frame(height: 320)
                        .listRowInsets(EdgeInsets())
                        .onChange(of: script) { _ in syntaxChecked = false; syntaxIssue = nil }
                } header: {
                    HStack {
                        Text(L("JS Code"))
                        Spacer()
                        Button {
                            if let s = UIPasteboard.general.string { script = s }
                        } label: { Label(L("Paste"), systemImage: "doc.on.clipboard") }
                            .textCase(nil)
                        Button(role: .destructive) {
                            script = ""
                        } label: { Label(L("Clear"), systemImage: "xmark.circle") }
                            .textCase(nil)
                            .disabled(scriptEmpty)
                    }
                }

                Section {
                    Button {
                        syntaxIssue = SyntaxCheck.validate(script)
                        syntaxChecked = true
                    } label: {
                        Label(L("Check syntax"), systemImage: "checkmark.seal")
                    }
                    .disabled(scriptEmpty)

                    if let issue = syntaxIssue {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                            if let line = issue.line {
                                Button {
                                    jumpLine = line
                                } label: {
                                    Label("\(L("Go to line")) \(line)\(issue.column.map { ", \(L("col")) \($0)" } ?? "")",
                                          systemImage: "arrow.down.to.line")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    } else if syntaxChecked {
                        Label(L("Syntax OK"), systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Section {
                    Button {
                        if let module = save() { moduleToTest = module }
                    } label: {
                        Label(L("Save & test"), systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(scriptEmpty)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L("Paste a module"))
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneToolbar()
            .onChange(of: overwriteTarget) { newValue in
                // Précharge le code du module ciblé (si l'éditeur est vide).
                if let target = newValue, scriptEmpty {
                    script = target.scriptContent
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(L("Cancel")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Save")) { _ = save(); dismiss() }
                        .disabled(scriptEmpty)
                }
            }
            .fullScreenCover(item: $moduleToTest) { module in
                NavigationStack {
                    ModuleTestView(module: module)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(L("Close")) { moduleToTest = nil }
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
