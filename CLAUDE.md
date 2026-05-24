# Prompteur Video — Instructions permanentes Claude
_Dernière mise à jour : 2026-05-24 (v2.0 — refonte "no-library")_

## Statut du projet
**Application en production / usage personnel.** Repo GitHub : `hichamozor/prompteur-video`.
Le créateur écrit ses scripts dans Google Docs et les colle dans l'app au moment du tournage. Pas de bibliothèque interne.

## Contexte projet
- App Flutter Android : prompteur vidéo qui affiche un texte défilant sur le flux caméra en arrière-plan
- Cible : créateur de contenu TikTok (usage perso)
- Build : GitHub Actions → APK distribué via artifact (workflow `.github/workflows/build.yml`)
- Build local USB : `install_usb.bat` à la racine du projet (build + adb install sur tel connecté)
- WiFi server (port 8080) : contrôle distant depuis navigateur PC + envoi de scripts via WebSocket
- Workflow type : Home → "Démarrer" → Prompteur (texte vide + IP affichée) → coller depuis PC

## Architecture (lib/) — v2.0
```
main.dart                       — bootstrap MultiProvider, orientations
models/
  settings_model.dart           — PrompterSettings (~24 champs, presets TikTok/YT/Reels/Podcast)
providers/
  settings_provider.dart        — ChangeNotifier unique de l'app
screens/
  home_screen.dart              — accueil minimal (gros bouton "Démarrer")
  prompter_screen.dart          — vue caméra + texte défilant + serveur WiFi
  settings_screen.dart          — paramètres
  logs_screen.dart              — logs serveur WiFi (debug)
services/
  wifi_server.dart              — HttpServer port 8080 (dart:io pur)
  mjpeg_isolate.dart            — stream caméra via Isolate (~15 fps throttle)
  storage_service.dart          — settings + auth token (shared_preferences only)
  logger.dart                   — log circulaire 500 entrées
  markdown_parser.dart          — **gras**, # section, // commentaire
  hard_words.dart               — détection mots ≥4 syllabes pour slowdown auto
theme.dart                      — palette noir + or (AppColors, AppText, AppRadii)
```

## Ce qui A ÉTÉ RETIRÉ en v2.0 (refonte "no-library")
Le créateur n'utilisait pas la bibliothèque interne. Sont supprimés :
- Tout le système de **Scripts** (model, provider, editor screen, import file/URL)
- Tout le système de **Takes** (model, provider, screens detail/sheet)
- Le **BackupService** (export/restore ZIP) — devenu inutile sans données métier
- La double sauvegarde des vidéos (avant : `/takes/` interne + galerie ; maintenant : galerie système uniquement, album "Prompteur")
- Les packages associés : `video_player`, `file_picker`, `share_plus`, `archive`, `path_provider`, `http`

## Conventions de code
- Couleurs : `theme.dart` centralise (`AppColors`). Pas de couleurs hardcodées dans les widgets
- Opacité : `withValues(alpha: x)` jamais `withOpacity(x)`
- Pas de `debugPrint` dans le code final → utiliser `logger.dart`
- Commentaires en français
- Provider pattern : `ChangeNotifierProvider.value` au niveau root, `Provider.of<X>(context, listen: false)` dans les actions, `Consumer<X>` dans le build

## Packages clés et contraintes
- `camera: ^0.10.5+9` : flux caméra en arrière-plan, switch front/back, pinch-zoom, exposition. **Sensible** — un changement de version peut casser le rendu
- `wakelock_plus` : empêche l'écran de s'éteindre pendant le prompteur
- `gal: ^1.1.0` : sauvegarde des vidéos dans la galerie système (album "Prompteur" via `Gal.putVideo(path, album: 'Prompteur')`)
- `dart:io` `HttpServer` direct (port 8080) — pas un package `shelf`. Choix volontaire pour minimiser les dépendances
- `Isolate` pour le MJPEG — **ne jamais** déplacer le streaming sur l'isolate principal (chute fps garantie)
- `dynamic_color` : utilise les couleurs du thème système Android 12+
- `dependency_overrides: package_info_plus '>=8.0.0 <9.0.0'` — override existant, ne pas retirer sans tester

## Règles métier critiques
- **Port 8080 = contrat WS public** : ne pas changer le port ni le format des messages (`script:...`, `play`, `pause`, `rewind2`, `forward2`, `home`, `speed+`, `speed-`, `rec`, `toggle`)
- **MJPEG fps cible : ~15** (throttle 65ms) — au-delà ça consomme trop de batterie sur Android
- **Orientations supportées** : portrait + paysage (gauche+droite). Pas de portrait inversé (caméra inversée)
- **Vidéo enregistrée** : 720p/1080p/4K à 30/60fps selon le device, sauvée dans l'album galerie "Prompteur"
- **Texte défilant** : scroll piloté par `Ticker` (Flutter SchedulerBinding) lié à la vitesse user
- **`_content` non persisté** : un nouveau lancement du prompteur démarre toujours avec un texte vide (workflow PC → tel volontaire)

## API WebSocket (port 8080)
- `GET /` : interface HTML de contrôle distant (assets/control.html)
- `GET /stream` : MJPEG stream caméra
- `WS /ws` : channel bidirectionnel
  - **Auth obligatoire** : 1er message du client doit être `auth:<token 6 chiffres>`. Le token s'affiche sur le prompteur et est persisté côté tel (`shared_preferences`).
  - PC → Phone : `script:<texte>` (push script), commandes (`play`, `pause`, `toggle`, `rewind2`, `forward2`, `home`, `speed+`, `speed-`, `rec`)
  - Phone → PC : `auth_required`, `auth_ok`, `auth_fail`, `pong`, `script:<texte>` (resync), JSON status `{playing, speed, progress, recording, duration}`

## Profil utilisateur
- TikTok content creator francophone
- Solide niveau Flutter, comprend Provider, isolates, dart:io
- Préfère solutions minimales (pas de packages superflus)
- Écrit ses scripts dans Google Docs, les colle dans l'app via la page de contrôle PC
- Valide explicitement avant qu'on code ("go", "on fait ça", "parfait")
- Réponses concises attendues, en français

## Comportement attendu
- Si demande de modif : créer une branche, jamais commit direct sur main
- Pour toute évolution : vérifier impact sur le contrat WebSocket
- Tester le build APK via `install_usb.bat` (rapide, local USB) ou via GitHub Actions (lent mais propre)
- Si ce fichier a plus de 3 mois sans mise à jour, signaler que certaines infos peuvent être obsolètes
