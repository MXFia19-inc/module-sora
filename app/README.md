# ModuleTester

App iOS **minimale** pour **tester les modules « Sora »** de ce dépôt (paires
`<nom>.json` + `<nom>.js`). Contrairement à Shirox/Sora, elle ne contient **aucune**
fonctionnalité AniList / MAL / réseau social / bibliothèque : uniquement de quoi
charger un module et parcourir **recherche → détails → épisodes → lecture**, avec des
outils de **debug**.

## Fonctionnalités

- **Gestion des modules** : ajout par URL de manifest, ajout en un tap des 8 modules
  MXFia19, import d'un `.json`(+`.js`) local pour tester une version non publiée,
  rafraîchissement, suppression.
- **Flux de test** : recherche → grille de résultats → détails (synopsis, alias, date) +
  épisodes → liste des flux → lecteur natif.
- **Lecteur** : `AVPlayer` avec transmission des **en-têtes HTTP par flux**
  (`AVURLAssetHTTPHeaderFieldsKey`), HLS/MP4, PiP + audio en arrière-plan, export
  VLC/Infuse/Outplayer.
- **Debug** : onglet **Logs** (console.log des modules, journal des requêtes `fetchv2`,
  exceptions JS), bouton **« JSON brut »** sur chaque écran, timeout d'exécution
  configurable, blocage optionnel des trackers (webhooks Discord).

## Contrat des modules

Le moteur (`JSEngine`) exécute chaque module dans un `JSContext` isolé et injecte les
globals attendus : `fetchv2`/`fetch`, `console`, `atob`/`btoa`, `setTimeout`, plus les
polyfills `URL` et `Buffer` absents de JavaScriptCore. Il appelle quatre fonctions
globales `async` qui renvoient chacune une **chaîne JSON** :

| Fonction | Entrée | Sortie |
|---|---|---|
| `searchResults(keyword)` | mot-clé | `[{title, image, href}]` |
| `extractDetails(url)` | `href` | `[{description, aliases, airdate}]` |
| `extractEpisodes(url)` | `href` | `[{href, number, title?, image?, season?}]` |
| `extractStreamUrl(url)` | `href` épisode | `{streams:[{title, streamUrl, headers}], subtitles}` |

Le parseur de flux tolère aussi les formes historiques de Sora (URL brute, `stream`,
`streams:[…]`, sous-titres divers).

## Build

Le projet est généré par **XcodeGen** et se compile **non signé** (sideload).

```bash
cd app
xcodegen generate --spec project.yml   # génère ModuleTester.xcodeproj
./buildipa.sh                          # produit build/ModuleTester.ipa (non signé)
```

Ou laissez la CI (`.github/workflows/build-app.yml`, runner macOS) produire l'IPA à
chaque push touchant `app/`.

## Smoke test (sans Xcode)

`tools/smoke.mjs` recrée les globals de l'app avec Node et vérifie que le contrat d'un
module tient (fonctions présentes, JSON valide, polyfills suffisants) :

```bash
node tools/smoke.mjs nakios "one piece"   # un module
node tools/smoke.mjs --all                # les 8 modules
```
