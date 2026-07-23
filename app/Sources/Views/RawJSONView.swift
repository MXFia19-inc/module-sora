import SwiftUI
import UIKit

/// Affiche la chaîne JSON brute retournée par une fonction de module.
struct RawJSONView: View {
    let title: String
    let raw: String
    @Environment(\.dismiss) private var dismiss

    private var pretty: String {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes]),
              let s = String(data: out, encoding: .utf8) else {
            return raw.isEmpty ? "(vide)" : raw
        }
        return s
    }

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Text(pretty)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Copier") { UIPasteboard.general.string = pretty }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}
