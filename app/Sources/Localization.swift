import Foundation

/// Langue de l'interface.
enum AppLanguage: String, CaseIterable, Identifiable {
    case en, fr
    var id: String { rawValue }
    var label: String { self == .en ? "English" : "Français" }
}

/// Localisation légère : la clé est le texte anglais, le français vient d'un
/// dictionnaire. En anglais, la clé est renvoyée telle quelle.
enum Loc {
    static var current: AppLanguage = .en
}

/// Traduit une chaîne (clé = texte anglais).
func L(_ english: String) -> String {
    Loc.current == .fr ? (frenchStrings[english] ?? english) : english
}

/// Traduit une chaîne à format (`%@`, `%lld`…) puis applique les arguments.
func Lf(_ englishFormat: String, _ args: CVarArg...) -> String {
    let f = Loc.current == .fr ? (frenchStrings[englishFormat] ?? englishFormat) : englishFormat
    return String(format: f, locale: Locale(identifier: "en_US_POSIX"), arguments: args)
}

/// Dictionnaire anglais → français. Toute clé absente retombe sur l'anglais.
let frenchStrings: [String: String] = [
    // Onglets
    "Modules": "Modules",
    "Test": "Test",
    "Logs": "Logs",
    "Settings": "Réglages",

    // Communs
    "Add": "Ajouter",
    "Cancel": "Annuler",
    "Close": "Fermer",
    "Save": "Enregistrer",
    "Delete": "Supprimer",
    "Error": "Erreur",
    "OK": "OK",
    "Copy": "Copier",
    "Refresh": "Rafraîchir",
    "None": "Aucun",
    "All": "Tous",
    "Language": "Langue",

    // Modules list
    "No module": "Aucun module",
    "Add a module by URL, from a library (cufiy…), the Luna list, or a file.":
        "Ajoutez un module par URL, via une bibliothèque (cufiy…), la liste Luna, ou un fichier.",
    "Pin": "Épingler",
    "Unpin": "Désépingler",
    "Search a module": "Rechercher un module",
    "Refresh all": "Tout rafraîchir",
    "Delete all": "Tout supprimer",
    "Add by URL": "Ajouter par URL",
    "Libraries (cufiy…)": "Bibliothèques (cufiy…)",
    "Luna modules (MXFia19)": "Modules Luna (MXFia19)",
    "Paste code (local)": "Coller du code (local)",
    "Import a file": "Importer un fichier",
    "Paste the module's .json manifest URL.": "Collez l'URL du manifest .json du module.",
    "Delete all modules?": "Supprimer tous les modules ?",
    "Select the module's .json file (and its .js).":
        "Sélectionnez le fichier .json (et son .js) du module.",
    "Also add the module's .js file.": "Ajoutez aussi le fichier .js du module.",
    "Luna modules": "Modules Luna",

    // Library
    "Libraries": "Bibliothèques",
    "Library": "Bibliothèque",
    "Load": "Charger",
    "Index .json URL": "URL d'un index .json",
    "All languages": "Toutes les langues",
    "Language filter": "Langue",
    "Search (name, author, type…)": "Rechercher (nom, auteur, type…)",
    "Index loaded but no module recognized.": "Index chargé mais aucun module reconnu.",

    // Test (mass tester)
    "Mass test": "Test en masse",
    "Keywords by type": "Mots-clés par type",
    "Anime": "Anime", "Movie": "Film", "Show": "Série", "Manga": "Manga",
    "keyword": "mot-clé",
    "Auto": "Auto",
    "Custom": "Perso",
    "Custom keyword": "Mot-clé personnalisé",
    "Relaunch with this keyword": "Relancer avec ce mot-clé",
    "Set all": "Tout définir",
    "Presets": "Préréglages",
    "Save as preset…": "Enregistrer comme préréglage…",
    "Preset name": "Nom du préréglage",
    "Delete a preset": "Supprimer un préréglage",
    "Saves the current selection, forced categories and custom keywords.":
        "Enregistre la sélection actuelle, les catégories forcées et les mots-clés personnalisés.",
    "Check stream links": "Vérifier les liens de flux",
    "In mass test, probes every returned stream URL (with its headers) to detect dead servers, 403 (wrong headers), timeouts…":
        "Dans le test en masse, sonde chaque lien de flux retourné (avec ses en-têtes) pour détecter les serveurs morts, les 403 (mauvais en-têtes), les délais dépassés…",
    "Links": "Liens",
    // Console interactive
    "Reuse": "Réutiliser",
    "JS expression…": "Expression JS…",
    "Type JavaScript to run it inside the module's context.":
        "Tapez du JavaScript pour l'exécuter dans le contexte du module.",

    // Historique
    "History": "Historique",
    "No run yet": "Aucun lancement",
    "Mass test runs are recorded here so you can compare them.":
        "Les lancements du test en masse sont enregistrés ici pour pouvoir les comparer.",
    "Changes since previous run": "Changements depuis le lancement précédent",
    "Date": "Date",
    "Source": "Origine",
    "Result": "Résultat",
    "new": "nouveau",
    "removed": "retiré",

    // Surveillance
    "Monitoring": "Surveillance",
    "Scheduled monitoring": "Surveillance planifiée",
    "Interval": "Intervalle",
    "Monitored preset": "Préréglage surveillé",
    "Notify only on regression": "Notifier seulement en cas de régression",
    "Last run": "Dernier lancement",
    "Last result": "Dernier résultat",
    "Run monitoring now": "Lancer la surveillance maintenant",
    "No module to monitor.": "Aucun module à surveiller.",
    "%@ regression(s)": "%@ régression(s)",
    "Re-runs the selected preset on a schedule and reports regressions. Runs reliably while the app is open; iOS only allows best-effort background runs.":
        "Relance le préréglage choisi à intervalle régulier et signale les régressions. Fiable tant que l'app est ouverte ; iOS ne permet qu'une exécution « au mieux » en arrière-plan.",

    "Cloudflare bypass": "Contournement Cloudflare",
    "Reset Cloudflare clearances": "Réinitialiser les clearances Cloudflare",
    "When a module hits a « Just a moment… » page, the challenge is solved in a hidden web view and the resulting cookies (and its User-Agent) are reused for the module's requests.":
        "Quand un module tombe sur une page « Just a moment… », le challenge est résolu dans une vue web masquée et les cookies obtenus (ainsi que son User-Agent) sont réutilisés pour les requêtes du module.",
    "Discord": "Discord",
    "Discord webhook": "Webhook Discord",
    "Send to Discord": "Envoyer sur Discord",
    "Send automatically after a mass test": "Envoyer automatiquement après un test en masse",
    "Posts the mass test summary to a Discord channel. Leave empty to disable.":
        "Publie le résumé du test en masse dans un salon Discord. Laisser vide pour désactiver.",
    "Report sent to Discord.": "Résumé envoyé sur Discord.",
    "Invalid webhook URL.": "URL de webhook invalide.",
    "Discord refused the request (HTTP %@).": "Discord a refusé la requête (HTTP %@).",
    "Loading": "Chargement",
    "Search": "Recherche",
    "Details": "Détails",
    "Episodes": "Épisodes",
    "Streams": "Flux",
    "Testing…": "Test en cours…",
    "Results": "Résultats",
    "Type": "Type",
    "Keyword": "Mot-clé",
    "Steps": "Étapes",
    "See JSON": "Voir le JSON",
    "Copy (text)": "Copier (texte)",
    "Share .txt": "Partager .txt",
    "Share .json": "Partager .json",
    "Relaunch": "Relancer",
    "Relaunch this module": "Relancer ce module",
    "Report unavailable.": "Rapport indisponible.",
    "No log captured.": "Aucun log capturé.",
    "Copy the snippet": "Copier l'extrait",
    "Copy this log": "Copier ce log",
    "ignored": "ignoré",
    "module loaded": "module chargé",
    "multi-type": "multi-type",

    // Logs
    "Console": "Console",
    "Network": "Réseau",
    "Errors": "Erreurs",
    "No log.": "Aucun log.",
    "Filter (text, URL, HTTP code…)": "Filtrer (texte, URL, code HTTP…)",
    "All modules": "Tous les modules",
    "Copy all (filtered)": "Copier tout (filtré)",
    "Copy the message only": "Copier le message seul",
    "Replay the request": "Rejouer la requête",
    "BLOCKED": "BLOQUÉ",
    "Replay": "Rejouer",
    "Request": "Requête",
    "Method": "Méthode",
    "Headers": "En-têtes",
    "Response": "Réponse",
    "Status": "Statut",
    "Body": "Corps",
    "(empty)": "(vide)",

    // Settings
    "Module execution": "Exécution des modules",
    "Max delay": "Délai maximum",
    "Block trackers": "Bloquer les trackers",
    "Blocked URL patterns (one per line)": "Motifs d'URL bloqués (un par ligne)",
    "Default User-Agent": "User-Agent par défaut",
    "Installed modules": "Modules installés",
    "Interface": "Interface",

    // Paste / editor
    "Paste a module": "Coller un module",
    "Target": "Cible",
    "New local module": "Nouveau module local",
    "Metadata": "Métadonnées",
    "Name": "Nom",
    "Language (optional)": "Langue (optionnel)",
    "JS Code": "Code JS",
    "Paste": "Coller",
    "Clear": "Effacer",
    "Load the module's current code": "Charger le code actuel du module",
    "Check syntax": "Vérifier la syntaxe",
    "Syntax OK": "Syntaxe OK",
    "Save & test": "Enregistrer & tester",

    // Player / streams
    "Subtitles": "Sous-titres",
    "Copy the stream URL": "Copier l'URL du flux",
    "No stream returned.": "Aucun flux retourné.",
    "Open in": "Ouvrir dans",
    "subtitle track(s) — not muxed by the native player; use export.":
        "piste(s) de sous-titres — non muxées par le lecteur natif ; utilisez l'export.",

    // Divers (ajouts)
    "Filter": "Filtre",
    "Module": "Module",
    "Module logs": "Logs du module",
    "Module not loaded.": "Module non chargé.",
    "Modules to test": "Modules à tester",
    "No module installed.": "Aucun module installé.",
    "No result (the module responded, but empty).": "Aucun résultat (le module a répondu, mais vide).",
    "Run test": "Lancer le test",
    "Search in": "Rechercher dans",
    "Synopsis": "Synopsis",
    "Tested episode (series)": "Épisode testé (séries)",
    "characters": "caractères",
    "headers": "en-têtes",
    "line": "ligne",
    "col": "col",
    "modules OK": "modules OK",
    "Go to line": "Aller à la ligne",
    "Code around the error": "Code autour de l'erreur",
    "Creates a local module from the pasted code.": "Crée un module local à partir du code collé.",
    "Replaces the selected module's script (keeps its manifest). The current code is loaded into the editor so you can edit it.":
        "Remplace le script du module sélectionné (conserve son manifest). Le code actuel est chargé dans l'éditeur pour que tu puisses le modifier.",
    "extractStreamUrl responded, but with no playable stream.":
        "extractStreamUrl a répondu, mais sans flux jouable.",
    "Done": "Terminé",
    "Episode": "Épisode",
    // Erreurs (formats)
    "JavaScript context unavailable.": "Contexte JavaScript indisponible.",
    "Error while evaluating the script: %@": "Erreur à l'évaluation du script : %@",
    "Function « %@ » missing from the module.": "Fonction « %@ » absente du module.",
    "JS error: %@": "Erreur JS : %@",
    "Timeout (%@s) for « %@ ».": "Délai dépassé (%@s) pour « %@ ».",
    "Invalid manifest URL.": "URL de manifest invalide.",
    "Invalid script URL (scriptUrl) in the manifest.": "URL de script (scriptUrl) invalide dans le manifest.",
    "Network error: %@": "Erreur réseau : %@",
    "Unreadable manifest: %@": "Manifest illisible : %@",
    "Luna source": "Source Luna",
    "App to test « Sora » modules. No AniList/social features.":
        "App de test des modules « Sora ». Aucune fonctionnalité AniList/social.",
    "Any fetchv2 request whose URL contains one of these patterns is blocked (empty response). For Supabase tracking, add the exact endpoint, e.g. « project.supabase.co/rest/v1/tracking ». Don't block all « supabase.co » if a module also reads its data there.":
        "Toute requête fetchv2 dont l'URL contient un de ces motifs est bloquée (réponse vide). Pour le tracking Supabase, ajoute l'endpoint exact, p. ex. « projet.supabase.co/rest/v1/tracking ». Ne bloque pas tout « supabase.co » si un module y lit aussi ses données.",
]
