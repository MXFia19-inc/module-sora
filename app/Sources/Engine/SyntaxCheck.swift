import Foundation
import JavaScriptCore

/// Vérifie la syntaxe d'un script de module en l'évaluant dans un contexte jetable
/// (mêmes polyfills que le moteur réel) et remonte la première erreur localisée.
enum SyntaxCheck {
    struct Issue {
        let message: String
        let line: Int?
        let column: Int?
    }

    static func validate(_ script: String) -> Issue? {
        guard let ctx = JSContext() else { return nil }
        var issue: Issue?
        ctx.exceptionHandler = { _, exception in
            let message = exception?.toString() ?? "erreur JS"
            var line: Int?
            var column: Int?
            if let ex = exception {
                if let l = ex.objectForKeyedSubscript("line"), !l.isUndefined { line = Int(l.toInt32()) }
                if let c = ex.objectForKeyedSubscript("column"), !c.isUndefined { column = Int(c.toInt32()) }
            }
            issue = Issue(message: message, line: line, column: column)
        }
        ctx.evaluateScript(JSPolyfills.source)
        issue = nil // n'garder que les erreurs du script du module
        ctx.evaluateScript(script)
        return issue
    }
}
