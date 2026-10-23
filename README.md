# CAPWS — Change App Permissions with Shizuku

Application Android qui liste **toutes les permissions de toutes les apps installées** et
permet de les **accorder / révoquer directement**, via [Shizuku](https://shizuku.rikka.app/),
sans root complet.

Différence avec [Permission Pilot](https://github.com/d4rken-org/permission-pilot), dont
l'UX de consultation a inspiré ce projet : Permission Pilot ne peut que rediriger vers les
Settings Android (limite native pour les apps tierces). CAPWS passe par Shizuku pour faire
le vrai grant/revoke en un tap, et ne retombe sur les Settings que quand Shizuku est
indisponible ou que la permission n'est pas modifiable par API.

- `applicationId` : `com.atamsphrow.capws`
- `minSdk` 24, Flutter 3.44 / Dart 3.12, Material You (couleurs système via `dynamic_color`)

## État actuel

| Élément | État |
|---|---|
| `flutter analyze` | propre |
| Tests unitaires (`flutter test`) | 32 tests, tous verts |
| `flutter build apk --debug` | OK |
| `flutter build apk --release --split-per-abi` | OK, signé (18,1 / 20,6 / 22,0 Mo) |
| `flutter build appbundle --release` | OK, signé (49,9 Mo) |
| Signature vérifiée (`apksigner`, `keytool -printcert`) | v2 + v3, `CN=Atamsphrow` sur les 3 APK et l'AAB |
| Exécution sur appareil réel | **jamais lancée** — aucun appareil Android connecté au moment du build |

Tout le comportement runtime (connexion Shizuku, grant/revoke réel, lecture des app-ops)
est donc **non vérifié**. C'est la prochaine étape.

## Architecture

```
lib/
  main.dart                     CapwsApp (Material You) + HomeShell (3 onglets) + HomeNavigator
  app_identity.dart             nom, package, propriétaire — une seule source de vérité
  models/
    app_info.dart               AppInfo, AppPermission, installerLabel()
    permission_info.dart        PermissionInfo, PermissionProtection
    permission_catalog.dart     catégories, permissions spéciales, ToggleMode
  services/
    shizuku_bridge.dart         wrapper typé MethodChannel + EventChannel
    package_manager_service.dart Inventory (snapshot + index inverse permission -> apps)
    inventory_controller.dart   ChangeNotifier : snapshot, statut Shizuku, filtres, écritures
    error_reporter.dart         capture des erreurs Flutter / async / natives / métier
  screens/
    dashboard_screen.dart       compteurs cliquables -> listes filtrées
    apps_list_screen.dart
    app_detail_screen.dart      permissions d'une app, groupées, avec toggles
    permissions_list_screen.dart permissions groupées par catégorie
    permission_detail_screen.dart apps détenant une permission, avec toggles
    diagnostics_screen.dart     journal d'erreurs + rapport copiable
    about_screen.dart           propriétaire, photo agrandissable, infos app
  widgets/
    app_icon.dart               chargement paresseux + cache mémoire des icônes
    app_list_tile.dart
    permission_toggle_tile.dart switch + confirmation + rapport d'erreur
    shizuku_status_card.dart    les 4 états Shizuku, chacun avec son action
    filter_bar.dart             recherche + chips partagés entre les deux onglets

android/app/src/main/kotlin/com/atamsphrow/capws/
  MainActivity.kt               enregistre le plugin
  ShizukuPlugin.kt              handler MethodChannel/EventChannel, intents Settings
  ShizukuService.kt             grant/revoke (binder + fallback shell), app-ops
  PackageInspector.kt           lecture PackageManager, icônes
```

### Deux chemins pour écrire, volontairement

`ShizukuService` implémente les deux :

1. **Binder** — réflexion sur `IPermissionManager` (API 30+) ou `IPackageManager` (API < 30)
   à travers un `ShizukuBinderWrapper`. Rapide et renvoie un vrai résultat.
2. **Shell** — `pm grant` / `pm revoke`. Plus lent, sortie à parser, mais survit aux
   changements de signature.

Le binder est tenté d'abord, le shell sert de repli. Ce n'est pas de la redondance
gratuite : la signature de `grantRuntimePermission` a bougé entre Android 11 (déplacée vers
`IPermissionManager`) et Android 14 (ajout de `persistentDeviceId`). Toutes les surcharges
sont sondées à l'exécution plutôt que supposées, et le repli shell couvre le reste.

Les classes `IPermissionManager` / `IPackageManager` sont sur la liste noire des API non-SDK
depuis Android 9, d'où `hiddenapibypass`.

### Permissions spéciales

Overlay, accès aux stats d'usage, écriture des réglages, accès à tous les fichiers… ne sont
pas des permissions runtime mais des **app-ops** : elles passent par `appops set`, jamais par
le binder. L'écran de détail relit l'app-op réel (`appops get`) parce que le flag
`REQUESTED_PERMISSION_GRANTED` de PackageManager ne le reflète pas.

L'**accessibilité** est volontairement en lecture seule avec redirection : elle dépend d'un
secure setting (`enabled_accessibility_services`) qu'on corromprait facilement en le
réécrivant à la main.

Les permissions **normal** et **signature** n'ont pas de switch du tout — Android n'offre
aucun moyen de les révoquer, et un switch grisé laisserait croire le contraire.

## Lancer le projet

```bash
flutter pub get
flutter run                       # appareil Android branché requis
flutter build apk --debug
flutter test
flutter analyze
```

Sur cette machine, `JAVA_HOME` doit être posé explicitement :

```bash
JAVA_HOME='C:\Program Files\Android\Android Studio\jbr' flutter build apk --debug
```

## Capteur d'erreurs et rapport de diagnostic

L'icône coccinelle du tableau de bord porte un badge dès qu'une erreur est capturée, et
mène à l'écran **Diagnostic**. Ce qui y est intercepté :

| Source | Ce qui est capté |
|---|---|
| `FlutterError.onError` | erreurs dans l'arbre de widgets (build, layout, gestes) |
| `PlatformDispatcher.instance.onError` | erreurs asynchrones non rattrapées |
| `InventoryController.refresh` | échec de lecture de l'inventaire |
| `InventoryController.setPermission` | **écriture de permission refusée** — avec le package, la permission, le sens et le mode |

Le dernier point est celui qui compte : c'est la panne qu'un utilisateur ne peut pas
diagnostiquer seul, et le rapport dit si le refus vient de Shizuku, d'Android, ou d'un bug
de l'app.

`PlatformDispatcher.onError` renvoie `true`, donc l'app **survit** à l'erreur au lieu de
mourir avec elle — un capteur qui disparaît avec ce qu'il capture ne sert à rien.

L'action « Copier le rapport » met dans le presse-papiers un texte prêt à coller, avec en
en-tête la version de l'app, le SDK Android, l'état complet de Shizuku, les compteurs
d'inventaire, puis chaque erreur avec son contexte et sa trace. « Tester le capteur »
déclenche volontairement une erreur synchrone **et** une asynchrone, pour vérifier la chaîne
sur un vrai appareil plutôt que sur parole.

Le journal est **en mémoire uniquement**, plafonné à 200 entrées (les plus anciennes sont
supprimées, et le rapport le dit pour qu'un journal tronqué ne passe pas pour complet). Il
repart à zéro à chaque démarrage : la spec exclut l'écriture de fichiers, la sortie se fait
donc par le presse-papiers.

## Icône

Construite à partir de `D:\dev\icon.jpg` — une tuile carrée déjà composée : cadre en dégradé
violet, panneau intérieur sombre, bouclier cyan lumineux contenant un interrupteur.

Cette tuile n'est **pas** utilisée telle quelle pour l'icône adaptative. Elle aurait donné
un cadre à l'intérieur du cadre du launcher, et le masque aurait rogné les coins du visuel.
Les couches sont donc reconstruites :

| Couche | Contenu |
|---|---|
| `background` | dégradé diagonal échantillonné dans la tuile (`#5B5AC8` → `#1C2745`), bord à bord |
| `foreground` | uniquement le bouclier cyan, détouré de la tuile, en couleur |
| `monochrome` | le même détourage en blanc, pour les icônes thématiques Android 13+ |

Le détourage se base sur la « cyanité » — `(V+B)/2 − R` — et non sur la luminosité : le
bouclier marque ~163, le cadre violet ~55, le panneau navy ~21, ce qui sépare nettement, et
les valeurs intermédiaires reproduisent le halo en alpha partiel. La luminosité seule
échouait, la partie claire du cadre violet étant trop proche du halo. Le seuil bas est à 88
et non 60 : plus permissif, il laissait passer un fantôme de la bordure de la tuile.

Le bouclier occupe ~55 % de la tuile, donc il tient dans la zone de sécurité de 66 dp du
canevas adaptatif de 108 dp sans redimensionnement.

Les icônes **legacy** (Android 7, couvert par `minSdk 24`) gardent le visuel d'origine,
simplement découpé en carré arrondi ou en cercle pour que les coins blancs du JPEG
n'apparaissent jamais.

5 densités (mdpi → xxxhdpi). Le script de génération est dans l'historique de build, pas dans
le dépôt ; les PNG produits sont versionnés dans `android/app/src/main/res/mipmap-*/`.

Vérification dans l'APK : `aapt2 dump badging` renvoie `icon='res/BW.xml'` à toutes les
densités, c'est-à-dire l'XML adaptatif, et les 5 ressources `mipmap/ic_launcher*` sont
présentes.

La graine du thème Flutter (`#3F6DDA`) n'est **pas** alignée sur la palette de l'icône : sur
tout appareil récent, Material You fait suivre l'UI au fond d'écran, pas à cette valeur.

## Navigation retour

Aucune flèche « ← » dans les écrans : le retour du téléphone (bouton ou geste) est le seul
chemin de retour, par choix.

- Retour depuis **Apps** ou **Permissions** → revient sur **Résumé**.
- Retour depuis **Résumé** → demande confirmation avant de fermer l'app.

Implémenté avec `PopScope(canPop: false)` dans `HomeShell`. Contrepartie assumée :
l'animation de retour prédictif d'Android 14 est désactivée sur cette route.

## Release et signature

La clé de release est réelle, pas la clé de debug.

| | |
|---|---|
| Keystore | `D:\keys\capws-upload.jks` — **hors du dépôt**, format PKCS12 |
| Alias | `capws` |
| Clé | RSA 4096, SHA384withRSA, valide jusqu'au 06/01/2054 |
| Sujet | `CN=Atamsphrow, OU=CAPWS, O=CAPWS` |
| Empreinte SHA-256 | `52:32:56:EB:EE:E9:3D:60:DF:4D:75:03:82:98:27:62:57:F9:EC:DC:56:1F:D0:0D:DE:85:10:69:A2:FA:CD:96` |
| Identifiants | `android/key.properties` (gitignoré, mot de passe aléatoire de 48 caractères) |
| Schémas de signature | v2 + v3 (v1 inutile à partir de minSdk 24, v3 pour la rotation de clé) |

```bash
JAVA_HOME='C:\Program Files\Android\Android Studio\jbr' flutter build apk --release --split-per-abi
JAVA_HOME='C:\Program Files\Android\Android Studio\jbr' flutter build appbundle --release
```

Vérifier une sortie :

```bash
apksigner verify --print-certs --verbose build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
```

L'empreinte affichée doit correspondre à celle du tableau ci-dessus. Si elle vaut
`CN=Android Debug, O=Android, C=US`, c'est que `android/key.properties` était absent : le
build retombe alors volontairement sur la clé de debug avec un avertissement Gradle, plutôt
que d'échouer à la configuration.

> **À sauvegarder hors ligne, tous les deux :** `D:\keys\capws-upload.jks` et
> `android/key.properties`. Les perdre rend toute mise à jour d'une app déjà publiée sous
> cette clé définitivement impossible. `capws-upload.jks.old` est l'ancienne copie au format
> JKS d'avant la migration PKCS12 — même clé, même mot de passe ; supprimable si tu ne veux
> qu'un seul exemplaire.

### Minification

`isMinifyEnabled = false`, volontairement. Tout le code privilégié atteint
`IPermissionManager`, `IPackageManager` et `Shizuku.newProcess` **par réflexion** : R8 les
voit comme inutilisés et les supprimerait ou les renommerait. La panne n'apparaîtrait qu'à
l'exécution, seulement en release, sous la forme d'un toggle qui ne fait silencieusement
rien. `android/app/proguard-rules.pro` contient déjà les règles `-keep` nécessaires : passer
le drapeau à `true` une fois la release validée sur appareil.

## Particularités de cette machine

Deux obstacles rencontrés au premier build, tous deux hors du code :

1. **AVG Antivirus intercepte le HTTPS** avec son propre CA racine. Windows lui fait
   confiance, la JVM d'Android Studio non → toutes les dépendances Gradle échouaient en
   `PKIX path validation failed`. Le truststore corrigé vit dans
   `D:\gradle\certs\truststore.jks`, référencé par `D:\gradle\gradle.properties`
   (`GRADLE_USER_HOME=D:\gradle`). **AVG régénère ce certificat** lors d'une mise à jour :
   le 2026-08-21 il est passé de `0F5F90C6…` à `471091DB…`, et l'ancienne copie échouait
   silencieusement alors que l'alias était toujours là. Comparer les empreintes, pas les
   sujets.
2. **`kotlin.incremental=false`** dans `android/gradle.properties` : le compilateur
   incrémental de Kotlin 2.3.20 (Build Tools API) n'arrive pas à fermer ses propres caches
   en compilant les modules de plugins pub, et fait échouer chaque build.

## Hors scope (choix assumés)

Pas d'export de données, pas d'écriture de fichiers, pas de « Permission Watcher »
(notifications de changement après mise à jour), pas de visualiseur de manifest brut.

## Prochaines étapes

1. Lancer sur un appareil réel avec Shizuku actif et vérifier : détection des 4 états,
   grant/revoke runtime (quel chemin gagne, binder ou shell ?), app-ops, reconnexion après
   mort du binder.
2. Vérifier les performances de l'inventaire sur un téléphone chargé (400+ apps).
3. Une fois la release validée sur appareil, activer `isMinifyEnabled` (les règles
   ProGuard sont déjà écrites) et comparer le comportement avec la build non minifiée.
