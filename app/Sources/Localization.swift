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
    "Anime": "Anime", "Film": "Film", "Series": "Série", "Manga": "Manga",
    "keyword": "mot-clé",
    "Auto": "Auto",
    "Set all": "Tout définir",
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
