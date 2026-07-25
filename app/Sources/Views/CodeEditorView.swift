import SwiftUI
import UIKit

/// Éditeur de code avec gouttière de numéros de ligne + saut/surlignage d'une ligne.
struct CodeEditorView: UIViewRepresentable {
    @Binding var text: String
    /// Quand renseigné, l'éditeur défile vers cette ligne, la sélectionne et la
    /// surligne brièvement, puis remet la valeur à nil.
    @Binding var jumpLine: Int?

    private let font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private let gutterWidth: CGFloat = 40

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()

        let editor = UITextView()
        editor.font = font
        editor.autocapitalizationType = .none
        editor.autocorrectionType = .no
        editor.smartQuotesType = .no
        editor.smartDashesType = .no
        editor.spellCheckingType = .no
        editor.backgroundColor = .clear
        editor.textColor = .label
        editor.delegate = context.coordinator
        editor.textContainerInset = UIEdgeInsets(top: 6, left: 4, bottom: 6, right: 6)
        editor.text = text
        editor.translatesAutoresizingMaskIntoConstraints = false

        let gutter = UITextView()
        gutter.font = font
        gutter.isEditable = false
        gutter.isSelectable = false
        gutter.isScrollEnabled = true
        gutter.isUserInteractionEnabled = false
        gutter.showsVerticalScrollIndicator = false
        gutter.backgroundColor = UIColor.secondarySystemBackground
        gutter.textColor = .secondaryLabel
        gutter.textContainerInset = UIEdgeInsets(top: 6, left: 2, bottom: 6, right: 4)
        gutter.textAlignment = .right
        gutter.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(gutter)
        container.addSubview(editor)
        NSLayoutConstraint.activate([
            gutter.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            gutter.topAnchor.constraint(equalTo: container.topAnchor),
            gutter.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            gutter.widthAnchor.constraint(equalToConstant: gutterWidth),

            editor.leadingAnchor.constraint(equalTo: gutter.trailingAnchor),
            editor.topAnchor.constraint(equalTo: container.topAnchor),
            editor.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            editor.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        context.coordinator.editor = editor
        context.coordinator.gutter = gutter
        context.coordinator.refreshLineNumbers()
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let editor = context.coordinator.editor else { return }
        if editor.text != text {
            editor.text = text
            context.coordinator.refreshLineNumbers()
        }
        if let line = jumpLine {
            context.coordinator.focusLine(line)
            DispatchQueue.main.async { self.jumpLine = nil }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: CodeEditorView
        weak var editor: UITextView?
        weak var gutter: UITextView?

        init(_ parent: CodeEditorView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            refreshLineNumbers()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            gutter?.contentOffset.y = scrollView.contentOffset.y
        }

        func refreshLineNumbers() {
            guard let editor, let gutter else { return }
            let count = max(1, editor.text.components(separatedBy: "\n").count)
            gutter.text = (1...count).map(String.init).joined(separator: "\n")
            gutter.contentOffset.y = editor.contentOffset.y
        }

        func focusLine(_ line: Int) {
            guard let editor else { return }
            let ns = editor.text as NSString
            let lines = editor.text.components(separatedBy: "\n")
            guard line >= 1, line <= lines.count else { return }
            var location = 0
            for i in 0..<(line - 1) { location += (lines[i] as NSString).length + 1 }
            let length = min((lines[line - 1] as NSString).length, ns.length - location)
            let range = NSRange(location: location, length: max(0, length))

            editor.becomeFirstResponder()
            editor.selectedRange = range
            editor.scrollRangeToVisible(range)

            // Surlignage temporaire de la ligne.
            let storage = editor.textStorage
            if range.location + range.length <= storage.length {
                storage.addAttribute(.backgroundColor,
                                     value: UIColor.systemYellow.withAlphaComponent(0.4),
                                     range: range)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak editor] in
                    guard let editor, range.location + range.length <= editor.textStorage.length else { return }
                    editor.textStorage.removeAttribute(.backgroundColor, range: range)
                }
            }
        }
    }
}
