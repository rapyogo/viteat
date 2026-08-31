# HANDOFF — customer (app Flutter de livraison de repas)

Dernière mise à jour : 2026-10-04

## Session 2026-10-04 — G6 Android natif : build APK vert (branche `feat/app-client-deps-9.2`, NON fusionnée)

- **État : base technique compilée, test sur téléphone pas encore fait.** Il ne faut donc pas encore annoncer `CLIENT_APP_PHASE_1_TECH_BASE_READY`.
- **SDK Android** :
  - le 03/10, le SDK n'était pas « absent » : il se trouve sur le disque USB, dans `D:\Explorer\MAYUNDO\Dev\Android\Sdk` (et non dans `D:\Dev\Android\Sdk`) ;
  - avec l'accord de l'utilisateur, les composants utiles ont été copiés dans **`C:\Android\Sdk`** (platform-tools, cmdline-tools, cmake, android-36, build-tools 35 et 36.1, NDK 28.2 et 29). Gradle a ajouté lui-même android-31, 34 et 35 ;
  - la jonction `%LOCALAPPDATA%\Android\Sdk` pointe maintenant vers `C:\Android\Sdk`.
- **RAM du poste (6,9 Go)** : un build à `-Xmx4096m` saturait la machine (plus de 70 minutes sans fin). `~/.gradle/gradle.properties` (hors dépôt) fixe désormais Xmx 2560m, 2 workers et Kotlin in-process. Résultat : un build propre prend environ 95 minutes, un build incrémental de 3 à 16 minutes.
- **Build de référence sur `c49ef8d`, sans rien modifier : ÉCHEC attendu.** Flutter 3.47.5 refuse Gradle 8.13 (minimum 8.14), puis AGP 8.9.1 (minimum 8.11.1). Les dépendances G1 à G5 n'y sont pour rien : la branche ne pouvait pas compiler avec Flutter 3.47 sans G6. Il n'y a donc pas de checkpoint « base verte » avant G6.
- **Commits G6**, chacun suivi d'un `flutter build apk --debug --target-platform android-arm64` :
  - `701c608` : Gradle 8.13 → 8.14.3. Le build passe le contrôle Gradle, puis bute sur l'AGP ;
  - `ed45cee` : AGP 8.11.1 pour application et library. **Premier APK vert** (184 Mo) ;
  - `98c43d8` : NDK 28.2 → 29.0.14033849. Vert ;
  - `09875aa` : `android.newDsl=false` et `android.builtInKotlin=false`, ajouté par le migrateur Flutter dès le premier build. Ces drapeaux sont identiques à la 9.2 et répondent à la consigne « opt out of android.newDsl » du Flutter Fix. Vert.
- **Conservé** : namespace et applicationId `com.rapyogo.customer.android`, signature, targetSdk 36 (la 9.2 est à 34), `versionCode 5`, desugaring, Kotlin 2.3.0.
- **Vérifications** :
  - `flutter analyze` : 0 erreur, 22 avertissements (identiques à la référence), 281 infos (contre 277 avant G1 ; G6 ne touche aucun fichier Dart) ;
  - contrôle du contrat serveur : aucune nouvelle occurrence de `googleapis_auth|mailer|serviceJson|emailSetting|setWalletTransaction|updateUserWallet|wallet_amount|FirebaseEnv.staging` (les seules présentes sont des commentaires expliquant les suppressions) ;
  - branche poussée, `c49ef8d..09875aa`.
- **Avertissements de Flutter 3.47** : Gradle 8.14.3, AGP 8.11.1 et Kotlin 2.3.0 ne seront « bientôt plus pris en charge » (il recommande Gradle 9.1, AGP 9.0.1, Kotlin 2.3.20). Ce n'est pas bloquant. Monter au-delà de la 9.2 est une décision à part, à prendre plus tard (AGP 9 impose le nouveau DSL).
- **Prochaine opération** :
  1. brancher un téléphone Android avec le débogage USB ;
  2. `adb install -r build/app/outputs/flutter-apk/app-debug.apk` ;
  3. test rapide en lecture seule : splash, connexion, accueil, fiche restaurant, panier, écran FlexPay **sans valider**, scan QR, carte. Aucune commande, aucun paiement, aucune notification de test ;
  4. si le test passe, annoncer `CLIENT_APP_PHASE_1_TECH_BASE_READY`, puis seulement passer aux 6 améliorations fonctionnelles 9.2.

## Session 2026-10-03 — étape 1 : dépendances alignées sur Foodie 9.2 (branche `feat/app-client-deps-9.2`, NON fusionnée)

- **Base retenue : `customer-clean`** (et non une 9.2 vierge). Décision et comparaison détaillée : `~/.claude/plans/pasted-content-id-2fb8-audit-de-lucky-mango.md`. Raisons : la 9.2 apporte peu de fonctionnel ; une bonne part de son code contredit le contrat serveur en prod (écritures wallet, SMTP, FCM par compte de service, secrets, base `staging`) ; 62 écarts Viteat sont obligatoires ou passés côté serveur.
- **Référence 9.2 = l'archive d'origine** : `Downloads/codecanyon-cAUCZ4xu-…zip` → `Applications.zip` → `foodie-9.2.zip` → `customer/`.
  - La copie `MISE à jour templete/V9.2/customer` est **incomplète** : il lui manque 22 fichiers Dart, `AndroidManifest`, `MainActivity` et `res/`.
  - Le dossier `customer/` présente les mêmes suppressions.
  - L'archive passe `flutter analyze` sans erreur avec Flutter 3.47.5.
- **Commits** (`30b80e6..b868e20`), chacun suivi de `pub get` (seuls les paquets du groupe et leurs dépendances transitives ont bougé) et de `flutter analyze` à 0 erreur, avec 22 avertissements, comme la référence :
  - G1 `4aa9fce` : famille Firebase. Core 4.15, firestore 6.10, auth 6.7, messaging 16.7, storage 13.6, database 12.6, app_check 0.4.8, cloud_functions 6.5. Ces versions sont légèrement au-dessus du lockfile 9.2, sans changement de version majeure.
  - G2 `d417726` : correctifs mineurs (12 paquets).
  - G3 `f03a447` : flutter_local_notifications 22.3, flutter_easyloading 4. Aucun code modifié, canal `viteat-customer` inchangé.
  - G4a `b436469` : geocoding 5, location 10, map_launcher 6, latlong2 0.10.
    - `Utils.redirectMap` est reprise de la 9.2 (API MapApp/TravelMode, mêmes messages).
    - Les appels `placemarkFromCoordinates` / `locationFromAddress` passent par `Geocoding()` (LocationService, fire_store_utils, place_picker).
    - **Le repli 9.2 sur une position à Mumbai n'a pas été repris.**
  - G4b `0ca573d` : bottom_picker 4.2 (`headerBuilder`, `onSubmit` typé), qr_code_dart_scan 0.14 (`ScanResult`), syncfusion 34. Les `.tr` et `TranslatedText` sont conservés. Il reste 6 infos de dépréciation sur `bottom_picker`, identiques à la 9.2 (à reprendre en phase 5).
  - G5 `265d767` : flutter_stripe 14. Aucun code modifié ; la passerelle reste masquée.
  - iOS `b868e20` : `IPHONEOS_DEPLOYMENT_TARGET` 13.0 → 15.0, aligné sur le Podfile.
- **Volontairement non repris de la 9.2** :
  - `googleapis_auth` et `mailer` (supprimés pour la sécurité) ;
  - `flutter_email_sender` n'est pas monté : il n'est utilisé nulle part dans `lib/`, à supprimer au nettoyage.
- **⚠️ Non fait : G6 Android natif** (AGP 8.9.1/8.3.0 → 8.11.1, Gradle 8.13 → 8.14.3, NDK 28.2 → 29.0.14033849, drapeaux `android.newDsl` / `builtInKotlin` de la 9.2).
  - **Raison : aucun build APK n'est possible.** Le SDK Android (`%LOCALAPPDATA%\Android\Sdk`) est une jonction vers `D:\Dev\Android\Sdk`, et le disque D: n'était pas monté. Changer Gradle et le NDK sans build aurait poussé des modifications jamais vérifiées.
  - **Aucun build APK n'a été fait sur cette branche** : seule l'analyse statique valide G1 à G5.
  - **À faire dès que D: est branché** : `flutter build apk --debug --target-platform android-arm64` sur la branche telle quelle, puis G6, puis un test rapide sur appareil (plan, §« Vérification de bout en bout »).
- `analysis_options.yaml` : modification locale de l'utilisateur, non commitée, laissée telle quelle.

## Session 2026-09-27/28 — contrats restaurant, badge bleu, durcissement (branche NON fusionnée)

- Rapport complet : `Admin Panel/docs/superpowers/reports/2026-09-28-rapport-contrats-restaurant.md` (dépôt viteat_admin_web, branche `feat/contrats-restaurant`). Spec : `Admin Panel/docs/superpowers/specs/2026-09-27-contrats-restaurant-design.md`.
- Verdict `CONTRATS_RESTAURANT_STAGING_FIXES_REQUIRED` : 713/713 tests émulateurs, rien de déployé ni fusionné ; le code n'a jamais tourné en réel.
- Consigne utilisateur : push autorisé, AUCUN merge ni déploiement prod avant les tests réels (§9 du rapport).
- Ne pas déployer les déclencheurs wallet avant publication des nouvelles apps et des panels (sinon double crédit).
- App client : branche `feat/contrats-restaurant-clean` (worktree `customer-clean`, repartie de origin/master ; la branche `feat/contrats-restaurant` locale contient 35 commits étrangers, ne pas la fusionner). Filtre isLive, badge, mise à jour forcée (`settings/Version.minCustomerBuildNumber`), wallet/push par callables. Flutter 3.47.5 : `C:/src/flutter-3.47`. versionCode à incrémenter seulement à la publication.
Dernière mise à jour : 2026-08-29

## Contexte projet
- App Flutter cliente d'une plateforme de livraison de repas multi-vendeurs, marque "Rapyogo" (package Android `com.rapyogo.client`).
- Firebase project : **rapyogo-2bccd** (base Firestore par défaut, `currentEnv = FirebaseEnv.defaultDb` dans `lib/utils/fire_store_utils.dart`).
- Le repo fait partie d'un ensemble de projets sœurs dans `C:\Projet\AUTRE\Nouveau dossier\` : `Admin Panel`, `customer` (ce repo), `driver`, plus des dossiers d'outillage Firebase (`Firebase Indexing`, `Firebase Import Export Collections`, `Firestore Demo Authentication User Import`, `Order Tracking Firebase Function`) qui ne sont **pas** des dépôts git.
- Version app : **`1.0.0+4`** (`pubspec.yaml` ligne 19, vérifié le 2026-08-28). Ce fichier annonçait `7.0.0+25`, ce qui était faux — la valeur ne correspond à aucun état du dépôt. ⚠️ La session du 21/08 notait « versionCode 4 → 5 pour la prochaine mise à jour » : **le bump n'a jamais été fait**. Un envoi au Play Store avec le versionCode 4 sera rejeté si le 4 y est déjà publié — à incrémenter avant toute publication.

## État git
- Branche `master`, remote `origin` = **`https://github.com/rapyogo/viteat`** (le remote par défaut de la config globale, `rapyogo/rapycar`, ne correspond PAS à ce projet — ce dépôt-ci utilise `viteat`, poussé et confirmé le 2026-08-24).
- Historique : commit initial propre (491 fichiers), un commit de correctifs (duplicate-app Firebase, splash bloqué), puis un commit "Ajoute Mobile Money (FlexPay) comme methode de paiement" (2026-08-24, voir section dédiée ci-dessous) qui inclut aussi le label app renommé "Viteat" et les changements de build Android en attente depuis la session précédente.
- Branches locales additionnelles encore présentes mais fusionnées dans master : `build-aab-prod`, `feature/mobile-money-flexpay`.

## Ce qui a été fait cette session

### 1. Mise en route de l'app sur device physique
- Testé sur Infinix X693 (Android 11) connecté en USB.
- Deux blocages d'environnement résolus (pas des bugs de code) :
  - **Disque C: presque plein** (6,3 Go libres) → le compilateur Dart plantait à l'écriture. Nettoyage des caches `.gradle`, `.m2`, `.cache`, `Temp` → 24 Go libérés.
  - **ProtonVPN actif** provoquait des coupures TLS pendant les téléchargements Gradle (`Connection reset`, cache Gradle corrompu). Résolu en désactivant le VPN le temps du build.

### 2. Bug Firebase corrigé : `[core/duplicate-app]`
- Cause : le plugin `google-services` initialise Firebase nativement au démarrage (`FirebaseInitProvider`), en conflit avec l'appel explicite `Firebase.initializeApp(options: ...)` dans `lib/main.dart` (nécessaire pour choisir entre base par défaut et "staging").
- Fix : `android/app/src/main/AndroidManifest.xml` — `<provider tools:node="remove">` sur `FirebaseInitProvider`.

### 3. Bug corrigé : écran de démarrage bloqué silencieusement
- Cause : `SplashController.redirectScreen()` (`lib/controllers/splash_controller.dart`) appelait `FireStoreUtils.isMaintenanceMode()` sans `try/catch`, dans un `Timer` non surveillé. Toute erreur Firestore transitoire (ex: juste après reconnexion réseau) plantait silencieusement et bloquait l'app sur le splash indéfiniment.
- Fix : `redirectScreen()` retente une fois après 2s puis se replie sur `LoginScreen` ; `isMaintenanceMode()` logue et relance l'erreur proprement.
- **Confirmé fonctionnel** : après le fix, l'app passe bien le splash (vu en conditions réelles avec coupure réseau).

### 4. Bugs identifiés mais NON corrigés (hors scope de la session)
- Sur l'écran qui suit le splash : `NetworkImage("")` (URL vide, `No host specified in URI file:///`) + `RenderFlex overflowed by 5.1 pixels`. Pas d'investigation plus poussée — écran non identifié avec certitude (probablement lié à une image de config/bannière absente en Firestore).

### 5. Configuration backend Firebase (projet rapyogo-2bccd)
Déployé depuis les dossiers sœurs (hors du repo git customer) :
- **Firebase Indexing** → 192 index composites Firestore déployés (`firestore_indexes.json`).
- **Order Tracking Firebase Function** → fonctions `deliveryDispatch` (répartition auto des commandes aux chauffeurs, trigger sur `restaurant_orders`) et `deleteUser` (callable HTTPS) déployées.
  - Dépendances obsolètes (`firebase-admin@8.6`, `firebase-functions@3.3`, ~2019) incompatibles avec le CLI Firebase actuel (timeout de découverte des fonctions). Mis à jour : `firebase-functions` → dernière version via l'import `firebase-functions/v1` (API v1 préservée), `firebase-admin` → **fixé sur `^11.11.1`** (dernière version avec l'ancienne API namespacée `admin.credential.cert()` / `admin.firestore()` / `admin.auth()` — la v12+ les a supprimées).
  - ⚠️ Le projet avait déjà 2 fonctions déployées non liées à ce dossier : `helloWorld` et `sendNewOrderNotification`. **Volontairement non touchées** (déploiement ciblé avec `--only functions:deliveryDispatch,functions:deleteUser`) — origine inconnue, `sendNewOrderNotification` fait peut-être doublon avec la logique de notification de `deliveryDispatch`, à vérifier.
  - `npm audit` : 22 vulnérabilités dont 1 critique dans les dépendances (`apn`, `axios@0.19`...) — héritées du template, non corrigées.
- **Firebase Import Export Collections** (données de démo) et **Firestore Demo Authentication User Import** (5 comptes de test) : **volontairement sautés** — choix explicite de l'utilisateur de ne pas importer de données de démo dans rapyogo-2bccd (pas un projet "staging" séparé).
- Clé de compte de service Firebase Admin utilisée uniquement en local (`Order Tracking Firebase Function/functions/serviceAccountKey.json`, gitignored) — **jamais committée**, ces dossiers ne sont de toute façon pas des dépôts git.

### 6. Nettoyage incohérence de package name
- Le build Gradle a lui-même unifié le nom de package (`com.rapyogo.client`) entre `build.gradle`, `MainActivity.kt` et `google-services.json`, qui divergeaient depuis le commit initial (`com.foodies.customer.android` / `com.rapyogo.customer.android` / `com.rapyogo.client`). `google-services.json` a aussi été nettoyé des entrées d'autres apps du même projet Firebase (`com.example.rapyogo`, `com.exemple.rapyogo`...).

### 7. Marque : renommage en "Viteat"
- L'app était déjà publiée sous le package Android `com.rapyogo.customer.android` (confirmé par l'utilisateur — à ne pas reconfondre avec `com.rapyogo.client` mentionné section 6, qui semble être un état intermédiaire d'une session antérieure ; **à revérifier** le nom de package réellement actif dans `android/app/build.gradle` avant toute prochaine publication).
- `versionCode` : 4 → 5 pour la prochaine mise à jour (confirmé correct par l'utilisateur, pas de conflit avec le Play Store).
- `android:label` dans `AndroidManifest.xml` changé de "Rapyogo" à **"Viteat"** — cohérent avec tous les textes in-app (titre, splash, reçus de paiement) qui utilisaient déjà "Viteat".

### 8. Mobile Money (FlexPay) — nouvelle méthode de paiement, pilotée par l'admin
Objectif de la session : ajouter Mobile Money (Airtel Money, Orange Money, M-Pesa, AfriMoney via l'agrégateur FlexPay.cd) comme moyen de paiement, entièrement contrôlable depuis le panel admin, en suivant le pattern des gateways existantes (MTN Momo, Orange Pay, etc.) découvert dans `Admin Panel` + `customer`.

**Architecture retenue** (différente du pattern PHP/Next.js par défaut du skill `flexpay-mobile-money`, adaptée à cette plateforme Firestore-native) :
- Réglages non-secrets (`enable`, `merchantCode`, `name`, `currency`, `image`) dans Firestore `settings/flexpay_settings` — lus par le panel admin (Blade + JS Firestore direct, comme toutes les autres gateways) et par l'app Flutter.
- **Le jeton API FlexPay et le secret de signature du callback ne sont JAMAIS dans Firestore** (contrairement à MTN Momo/Orange Pay existants qui exposent leurs clés au client — délibérément pas reproduit ici). Ils vivent en tant que **secrets Cloud Functions** (`FLEXPAY_API_TOKEN`, `FLEXPAY_CALLBACK_TOKEN`, configurés via `firebase functions:secrets:set`).
- 3 nouvelles Cloud Functions (`Order Tracking Firebase Function/functions/products/flexpay.js`, câblées dans `index.js`), déployées sur `rapyogo-2bccd` :
  - `initiateMobileMoneyPayment` (callable, authentifiée) — crée un document `mobile_money_payments/{reference}`, appelle l'API FlexPay.
  - `checkMobileMoneyStatus` (callable, authentifiée) — vérification manuelle de secours (polling côté app après timeout).
  - `flexPayCallback` (HTTPS publique, protégée par jeton en query param `?token=`) — webhook FlexPay, met à jour le document de paiement de façon atomique (protection anti-rejeu : ne traite que si `status == 'pending'`).
  - URL du callback : `https://us-central1-rapyogo-2bccd.cloudfunctions.net/flexPayCallback` (fixée dans `functions/.env`, non commité — voir note ci-dessous).
  - Toutes les interactions API sont journalisées dans `flexpay_transactions` (audit).
  - `.eslintrc.json` de `functions/` inchangé (ecmaVersion 2017, trop ancien pour `?.`/`??`) — le code évite volontairement l'optional chaining pour rester compatible.
- App Flutter (`customer`) : `lib/models/payment_model/flexpay_model.dart`, `lib/payment/flexpay_payment_screen.dart` (saisie numéro → écoute Firestore temps réel du statut → repli sur vérification manuelle après 2 min), câblé dans `cart_controller.dart` / `cart_screen.dart` / `select_payment_screen.dart`. Icône temporaire réutilisée (`assets/images/mtnmom.png`) — **pas de logo FlexPay/Mobile Money dédié pour l'instant**, à remplacer.
- Panel admin (`Admin Panel`, PAS un dépôt git) : nouvelle vue `resources/views/settings/app/flexpay.blade.php` + `SettingsController::flexpay()` + route `settings/payment/flexpay` + clés `lang.app_setting_flexpay*` (anglais seulement, pas de traduction arabe ajoutée). Onglet "Mobile Money (FlexPay)" ajouté par script à **19 autres vues** de réglages de paiement (barre d'onglets dupliquée dans chaque fichier — pattern existant de l'app, pas un choix de cette session).

**⚠️ État actuel en production (au 2026-08-24, fin de session) :**
- `settings/flexpay_settings` dans Firestore : **`enable: true`, `merchantCode: RAPYOGO_SARL`** (vrai code marchand, pas SIMULATED) — **le gateway est actuellement LIVE**, activé par l'utilisateur lui-même depuis le panel admin. Tout paiement Mobile Money côté client déclenchera une vraie transaction FlexPay.
- Backend testé de bout en bout **uniquement en mode simulé** (`merchantCode: SIMULATED` temporaire pendant le test, restauré après) — initiation, vérification de statut, journal d'audit : tout fonctionne. **Aucun test avec un vrai numéro de téléphone / vraie transaction FlexPay n'a été fait.**
- Les IPs `156.0.198.27` / `156.0.198.19` données par l'utilisateur (probablement les IPs sources de FlexPay pour leurs callbacks, ou les IPs à whitelister côté FlexPay pour les appels sortants — **ambiguïté non résolue**) ne sont pas encore utilisées dans le code. Le webhook `flexPayCallback` n'est protégé que par le jeton en query param, pas par whitelist IP.

### 9. Build Android bloqué en fin de session — cause non résolue
Trois causes d'échec de build diagnostiquées et corrigées cette session (disque plein, ProtonVPN, daemons Gradle zombies — voir mémoire `android-build-gotchas` mise à jour), mais la session s'est terminée avec un **second VPN actif** (activé par l'utilisateur après avoir coupé ProtonVPN) qui casse la résolution DNS vers `dl.google.com` / `repo.maven.apache.org` (`Hôte inconnu`). L'app n'a **pas encore été validée manuellement sur l'écran de paiement Mobile Money** — bloqué sur ce problème de build, pas un bug de code. Prochaine session : désactiver ce second VPN (ou le reconfigurer pour ne pas intercepter le DNS) avant de relancer `flutter run -d <device>`.

## Pistes ouvertes / à traiter (état au 2026-08-24, non revérifiées le 25)
- Décider si `settings/flexpay_settings.enable` doit rester `true` (live) ou repasser à `false` en attendant la validation manuelle complète.
- Clarifier le sens des IPs FlexPay fournies (156.0.198.27/.19) et éventuellement ajouter une whitelist IP en plus du jeton sur `flexPayCallback`.
- Remplacer l'icône temporaire Mobile Money (actuellement `mtnmom.png` réutilisé) par un vrai logo.
- Revérifier le nom de package Android réellement actif (`com.rapyogo.customer.android` vs `com.rapyogo.client` — voir section 7).
- Investiguer le doublon potentiel `sendNewOrderNotification` vs `deliveryDispatch`.
- `firebase.json` / `firebase_options.dart` (section iOS) référencent encore un projet obsolète `foodies-3c1d9` — config iOS jamais terminée (`YOUR_IOS_PROJECT_ID` en placeholder). Non bloquant pour Android.
- `npm audit fix` à envisager sur `Order Tracking Firebase Function/functions` (22 vulnérabilités, 1 critique).

---

## Session 2026-08-25 — corrections de bugs via test réel sur device + import de données de démo

### 1. Environnement de build (machine locale, pas des bugs de code)
- Cache Gradle (`~/.gradle/caches`, 7.3 Go) vidé à la demande de l'utilisateur → a cassé le build suivant (transform Gradle corrompu, fichiers `.jar` verrouillés par Android Studio en cours d'exécution). Résolu en supprimant le reste du cache et en laissant Gradle tout retélécharger.
- Le NDK `27.0.12077973` était mal téléchargé (dossier vide, `[CXX1101] did not have a source.properties file`) → supprimé pour retéléchargement propre.
- **Disque C: passé à 1,6 Go libres** après le rebuild complet du cache Gradle (9 Go) + re-téléchargement NDK. Cause identifiée : **4 versions de NDK installées** (27.x, 28.2.13676358, deux 29.x — 9,1 Go), alors qu'une seule est utilisée. Suppression des 3 inutiles → 9,4 Go libérés. Voir mémoire `android-build-gotchas` (mise à jour).
- `android/app/build.gradle` ne fixait pas `ndkVersion` → conflit avec les plugins `jni`/`speech_to_text` qui exigent `28.2.13676358`. Fixé explicitement (voir commit du jour).
- Suppression de `android/build.gradle.kts`, `android/app/build.gradle.kts`, `android/settings.gradle.kts` : reliquats du scaffold Flutter d'origine (package `com.foodies.customer.customer`, jamais utilisés par Gradle qui préfère les `.gradle` Groovy présents en parallèle) — Gradle signalait explicitement "likely a mistake".

### 2. Bugs applicatifs trouvés et corrigés en faisant tourner l'app sur device réel (Infinix X693, wifi adb)
Tous confirmés en conditions réelles (device physique, pas juste en lecture de code) :
- **`FireStoreUtils.getCurrentUid()`** (`fire_store_utils.dart:98`) plantait (`Null check operator used on a null value`) pour tout visiteur non connecté — appelé dans 97 endroits/28 fichiers. Corrigé pour retourner `''` au lieu de `!`.
- **Plats invisibles bien qu'en base** : `getProductByVendorId()` filtrait `where("takeawayOption", isEqualTo: false)` côté Firestore — exclut les documents où le champ n'existe pas du tout (vieux plats jamais mis à jour avec ce champ). Filtre déplacé côté client (`null`/absent traité comme disponible).
- **`Constant.adminCommission!`** (`constant.dart:212`) plantait l'affichage du prix de **tout** plat dès que ce document de settings n'était pas configuré — confirmé en direct via capture d'écran (erreur rouge Flutter à l'ouverture d'une catégorie de menu). Même correctif appliqué dans `cart_controller.dart` (aurait fait planter la création de commande).
- **Chargement de restaurant lent** : `getProduct()` faisait un appel Firestore séquentiel par plat pour récupérer sa catégorie (30 plats = 30 aller-retours l'un après l'autre). Remplacé par une résolution parallèle et dédupliquée des catégories uniques.
- **Nom de catégorie tronqué** sur l'écran d'accueil (`home_screen.dart`, liste horizontale de catégories) : `TranslatedText` sans `overflow: TextOverflow.ellipsis` dans une largeur fixe de 78px. Corrigé.
- **Géolocalisation bloquée indéfiniment après autorisation** : `Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high)` sans `timeLimit` — attente GPS haute précision pouvant ne jamais aboutir en intérieur. Passé à `LocationAccuracy.medium` + `timeLimit: Duration(seconds: 10)` via `LocationSettings` (API non dépréciée). Confirmé : résolution en ~7s sur le device de test après correctif.
- **Placeholder image vide** (`Constant.placeholderImage = ""`) : le fallback d'erreur de `NetworkImageWidget` appelait `Image.network("")` en boucle, spammant `No host specified in URI file:///`. Remplacé par une icône locale (`Icons.image_not_supported_outlined`) quand le placeholder est vide.

**Non revérifié sur device** : la connexion adb sans-fil s'est coupée avant de pouvoir confirmer visuellement le correctif `adminCommission` + les autres correctifs de cette liste ensemble sur l'app relancée. À revérifier en priorité en prochaine session (reconnecter le débogage sans fil, relancer `flutter run`, retester l'ouverture d'une catégorie de menu jusqu'à la commande).

**Demandes UX non traitées** (mentionnées par l'utilisateur, pas encore scopées) :
- Messages de chargement interactifs/dynamiques pendant les opérations longues (ex. "Nous calculons votre position...") au lieu d'un loader générique "Please wait" (`ShowToastDialog.showLoader`).
- Écrans squelettes (skeleton loading) — périmètre à définir (quels écrans en priorité) avant de commencer.
- "Offline first" — changement d'architecture (cache local), pas un correctif ponctuel. Non scopé.

### 3. Import de données de démonstration dans Firestore (rapyogo-2bccd) — ⚠️ à lire avant toute prochaine action sur ce projet
**Revirement de décision** : la session du 2026-08-21 avait explicitement choisi de ne PAS importer les données de démo du template dans `rapyogo-2bccd` (projet de production, pas un sandbox). Le 2026-08-25, l'utilisateur a demandé l'import pour faciliter les tests — confirmé explicitement après relecture de cette décision passée.

**Ce qui a été fait :**
- `Firebase Import Export Collections/collections.json` importé via `npx node-firestore-import-export firestore-import -y` (43 collections, ~4.8 Mo) — **sans sauvegarde préalable** (erreur de ma part, à ne pas reproduire : toujours `firestore-export` un backup avant un import avec `-y`).
- `Firestore Demo Authentication User Import/import-user.js` : import des 5 comptes Auth de démo — **arrêté après le 1er compte** (`FirebaseAuthError: uid-already-exists`), voir découverte ci-dessous.

**Découverte importante** : `rapyogo-2bccd` n'est pas un projet vierge. Il contient **58 comptes Auth réels** (emails perso + `@rapyogo.com`, dont celui de l'utilisateur), et 5 comptes `@gromart.com` créés le même jour (01/09/2024) avec les UID exacts codés en dur dans `import-user.js` — reliquat d'un import de démo déjà fait une fois sur ce projet, sous une marque antérieure "Gromart", avant le renommage en Rapyogo/Viteat. **Confirmé par l'utilisateur : ce sont bien de vieux reliquats, à nettoyer** — mais le nettoyage n'a **pas encore été fait** (voir pistes ouvertes).

**Risque identifié** : l'import Firestore avec `-y` écrit un document par ID présent dans `collections.json`. Les documents de settings *personnalisés uniquement par l'utilisateur* (absents du jeu de démo stock, ex. `settings/flexpay_settings`) ont été épargnés — confirmé (`merchantCode: RAPYOGO_SARL` et `welcome_message: "Bienvenue sur Rapyogo !"` intacts après import). Mais les documents de settings **communs à toute installation du template** (`globalSettings`, `ContactUs`, `Version`, etc.) ont très probablement été écrasés par les valeurs génériques du template (`globalSettings.applicationName` affiche "Foodie" après import — incohérent avec tout le travail de renommage documenté dans ce fichier). **Non corrigé, pas de sauvegarde disponible pour restaurer les anciennes valeurs.**

**Vérification structurelle faite (rassurante)** : les 35 collections utilisées par le code Dart (`CollectionName`), les 7 Cloud Functions (dont tout le module FlexPay), et les index Firestore composites sont tous présents et intacts après l'import — l'import n'a rien cassé de structurel, seulement potentiellement des valeurs de config partagées.

**Sécurité** : une vraie clé de compte de service Firebase (`firebase-adminsdk-qn3oh@rapyogo-2bccd`) a été collée directement dans le chat par l'utilisateur pour débloquer l'import. **Cette clé doit être révoquée et régénérée** depuis la console Firebase (Paramètres du projet → Comptes de service) — jamais fait à ce jour.
> **Correction 2026-08-28** : cette section affirmait que la clé avait été « supprimée du disque ». C'est faux — le fichier `Order Tracking Firebase Function/functions/serviceAccountKey.json` est toujours présent (daté du 21/08). Il est gitignoré et ce dossier n'est pas un dépôt git, donc pas de fuite par le versionnage, mais **la clé exposée en chat reste à révoquer**. Elle a servi le 2026-08-28 pour lire et migrer des réglages Firestore.

**Pistes ouvertes issues de cet import :**
- ~~Vérifier si `globalSettings` affiche des valeurs génériques "Foodie"~~ → **VÉRIFIÉ LE 2026-08-28 : c'est faux, `applicationName = "Viteat"`, couleurs `#ff6a00`, `defaultCountryCode = CD`.** L'import de démo n'a pas écrasé ce document. Crainte levée, aucune reconfiguration nécessaire.
- Nettoyer les 5 comptes `@gromart.com` restants (Auth + toute donnée Firestore associée à leurs UID) — confirmé "reliquat" par l'utilisateur mais nettoyage pas encore exécuté.
- Réessayer l'import des comptes de démo (`import-user.js`) seulement après avoir libéré/choisi d'autres UID (les 5 UID cibles du script sont pris par les comptes Gromart).
- **Révoquer la clé de compte de service exposée dans le chat** et en générer une nouvelle si besoin futur.

---

## Session 2026-08-26 — Offline-first Phase 1 (P0) + corrections en marge

Branche `offline-first-perf-ux`. Plan complet écrit en amont (mode plan) : `C:\Users\RAPYOGO\.claude\plans\tu-es-un-lead-synthetic-brooks.md`. Périmètre validé avec l'utilisateur : **Phase 1 uniquement** (offline-first + performance + UX + recherche structurée classique + profil enrichi) — l'agent IA conversationnel (recherche en langage naturel, voix comprise) est documenté comme roadmap Phase 2 dans ce même plan, **non implémenté** (nécessite une clé Anthropic + touche le dossier Cloud Functions hors de ce repo, jamais validé budget par l'utilisateur).

### 1. P0 livré (offline-first + résilience réseau)
- `fire_store_utils.dart` : `Settings(persistenceEnabled: true, cacheSizeBytes: 100 Mo)` explicite sur l'instance Firestore — fallback cache automatique pour tous les `.get()` existants sans toucher un site d'appel.
- Nouveau `lib/services/connectivity_service.dart` (`connectivity_plus`) + `lib/widget/connectivity_banner.dart` — bannière non bloquante (offline/syncing/échec), posée dans `main.dart` avant `runApp`, affichée dans `dash_board_screen.dart`.
- `cart_controller.dart`/`cart_screen.dart` : fix race condition sur `productModel` (assigné async, lu sync) dans la liste du panier ; `getUserProfile()` n'est plus rappelé si `Constant.userModel` est déjà peuplé.
- `splash_controller.dart` : route un utilisateur hors-ligne mais déjà authentifié directement vers le dashboard au lieu du login ; parallélise `isMaintenanceMode()`/`isLogin()`.

### 2. Bug critique trouvé en testant le P0 sur device réel : réseau lent ≠ réseau absent
Le premier fallback offline (ci-dessus) ne se basait que sur l'état "hors ligne" détecté par `connectivity_plus` (signal radio absent). Sur le terrain, le cas réel est différent : réseau présent mais **backend Firestore injoignable** (`Could not reach Cloud Firestore backend. Backend didn't respond within 10 seconds`) — que `connectivity_plus` classe "en ligne". Le fallback détecte maintenant aussi les erreurs Firestore transitoires (`unavailable`, `deadline-exceeded`, `network-request-failed`, `cancelled`).

En creusant ce même symptôme ("l'appli se vide mais la nav reste visible"), root cause trouvée dans `FireStoreUtils.getSettings()` : ~10 lectures Firestore y sont lancées via `.then()` **jamais `await`-ées**. Sur réseau dégradé, une exception dans un de ces callbacks échappe au `try/catch` englobant (déjà terminé au moment où l'erreur arrive) et devient non gérée — plusieurs `Constant.*` (thème, wallet, images, clé carte...) restaient jamais peuplés. Les 10 lectures ont reçu un `.catchError()` local.

### 3. Crash bloquant au cold start sans localisation ni réseau
`FireStoreUtils.getTaxList()` faisait `Constant.selectedLocation.location!.latitude!` sans garde — plantait toute la construction de `HomeController` (et `FavouriteScreen`, et 26 autres sites dans ~15 fichiers utilisant le même pattern `.location!`) dès que la localisation n'était pas encore résolue.

**Décision importante, corrigée en cours de session sur demande explicite de l'utilisateur** : la première tentative de fix donnait une valeur par défaut factice `(0.0, 0.0)` à `Constant.selectedLocation.location`. **L'utilisateur a explicitement rejeté cette approche** : le `null` de `location` est une donnée significative pour le système ("localisation non définie" doit rester détectable, pas être remplacée par une fausse coordonnée qui fausserait silencieusement les calculs de distance/zone). Revenu à `location: null` par défaut. Fix propre :
- `Constant.getDistanceFromUser({lat1, lng1})` (nouveau, `constant.dart`) — retourne `''` tant que la localisation n'est pas résolue, utilisé dans 11 sites d'affichage de distance (home_screen.dart x4, dine_in_screen.dart x3, search_screen.dart, favourite_screen.dart, category_restaurant_screen.dart, restaurant_list_screen.dart, dine_in_restaurant_list_screen.dart, home_screen_two.dart).
- 3 sites de requête (zone/proximité) passés de `.location!` à `.location?` avec fallback `?? 0.0` déjà existant pour la valeur.
- Checkout (`cart_screen.dart`, bouton "Pay Now") : bloque désormais avec le message "Veuillez ajouter votre localisation avant de commander." si aucune localisation n'est définie, au lieu de planter au moment de vérifier la zone de livraison.

**Piste ouverte** : ce pattern `.location!` répété dans ~15 fichiers est un signal que la Phase 1 (section "Localisation" du plan, `LocationService` unifié + persistance locale) reste à faire — ce correctif traite les symptômes, pas l'architecture sous-jacente (localisation encore stockée en static en mémoire, jamais persistée localement).

### 4. Bugs Mobile Money / FlexPay signalés par l'utilisateur, tous corrigés
- Loader "Please wait" jamais fermé avant navigation vers l'écran FlexPay (`cart_controller.dart` + `wallet_controller.dart`, ce dernier nouvellement câblé).
- Libellé "FlexPay" (nom brut de l'enum Dart) affiché après sélection du moyen de paiement → nouveau `Constant.paymentMethodLabel()` : "flexPay" → **"Mobile"**, "cod" → **"Cash"**, appliqué dans `select_payment_screen.dart`, `cart_screen.dart` (résumé compact), `payment_list_screen.dart`.
- **Mobile Money ajouté au top-up wallet** (`wallet_controller.dart` : `flexPayModel` + `flexPayMakePayment()` ; `payment_list_screen.dart` : option + dispatch bouton "Top-up") — n'existait qu'au checkout jusqu'ici.
- `RenderFlex overflow` sur les cartes catégories (`view_all_category_screen.dart`) — image 60→56px, padding vertical réduit.
- `RenderFlex overflow` sur le résumé "Pay Via [Wallet] (Change)" (`cart_screen.dart`) — libellé sans `Flexible`, dépassait dès qu'il était un peu long ("Wallet" vs "Cash"). Fix : `Flexible` + ellipsis.
- **Redesign complet de `flexpay_payment_screen.dart`** : ne respectait pas le design system (couleurs codées en dur, pas de thème sombre) → migré vers `AppThemeData` + `DarkThemeProvider`. Messages d'erreur différenciés par code (`_friendlyErrorMessage`) au lieu d'un message générique. Nom de l'app ("Viteat") + footer avec liens Confidentialité/CGU (réutilise `TermsAndConditionScreen` existant). Le loading au clic sur "Continuer" existait déjà.

### 5. Backend FlexPay optimisé et déployé (hors repo git)
`Order Tracking Firebase Function/functions/products/flexpay.js` — les 3 fonctions (`initiateMobileMoneyPayment`, `checkMobileMoneyStatus`, `flexPayCallback`) enchaînaient des appels Firestore indépendants en séquentiel avant de répondre à l'app (latence perçue élevée, signalée par l'utilisateur). Restructuré avec `Promise.all` partout où c'était sûr (lecture réglages + création doc en parallèle ; log d'audit + mise à jour du statut en parallèle). Comportement inchangé, ~300-500ms gagnés sur notre propre overhead (le délai FlexPay/opérateur lui-même n'est pas compressible). **Déployé en production** sur `rapyogo-2bccd` avec l'accord explicite de l'utilisateur (gateway LIVE, marchand `RAPYOGO_SARL`). Un déploiement a échoué une fois sur une erreur transitoire GCP (Cloud Run 500) sur `checkMobileMoneyStatus` seul — redéployé avec succès au second essai.

### 6. Bug identifié mais NON corrigé (refusé explicitement par l'utilisateur pour cette session)
**Admin Panel** (`resources/views/settings/app/global.blade.php`, PHP/Blade, pas un dépôt git) : les 6 sélecteurs `<input type="color">` (`customer_app_color`, `driver_app_color`, `restaurant_app_color`, `admin_color`, `store_color`, `website_color`) n'ont pas de `value` par défaut → le navigateur les initialise à `#000000` tant que le chargement Firestore asynchrone qui doit les remplir n'est pas terminé. Le handler "Enregistrer" lit `.val()` sur ces inputs indépendamment, sans attendre ce chargement. **Si l'admin enregistre la page (même pour un tout autre champ) avant la fin du chargement, la vraie couleur est silencieusement écrasée par du noir dans Firestore.** C'est la cause du signalement "la couleur ne suit plus". Fix proposé (bloquer le bouton Enregistrer tant que le chargement n'est pas terminé) — **refusé pour cette session**, à reprendre plus tard si demandé. Note : le fix côté Flutter (`fire_store_utils.dart`, section suivante) protège contre le crash/cascade que cette valeur invalide pouvait provoquer, mais ne corrige pas la couleur déjà écrasée en base — à reconfigurer manuellement une fois l'Admin Panel corrigé.

En lien : `fire_store_utils.dart` — le parsing de `app_customer_color` (`int.parse(...)`) n'était pas protégé et pouvait, à lui seul, planter et faire échouer silencieusement le chargement d'une quinzaine d'autres réglages qui le suivent dans le même bloc `try` de `getSettings()` (DineinForRestaurant, googleMapKey, walletSettings, Version, story, adminSettings, AdminCommission...). Isolé dans son propre `try/catch` local.

### 7. Gotchas machine (voir mémoire `android-build-gotchas`, mise à jour)
- Nouveau record de vide sur C: pendant la session (144 Mo libres, 100% plein) — `.gradle/caches` vidé deux fois (la deuxième fois après un daemon Gradle zombie ayant corrompu `metadata.bin` lors d'un build tué en plein milieu — `gradlew --stop` avant de reclean).
- `INSTALL_FAILED_INSUFFICIENT_STORAGE` lors d'un `adb install` peut venir du **téléphone**, pas du PC — confirmé sur l'Infinix X693 de test (~852 Mo libres / 113 Go, 100% plein), séparément du problème PC. Ne pas gérer le stockage du téléphone automatiquement (photos/apps personnelles) — toujours demander à l'utilisateur.

### État en fin de session
- Tous les commits ci-dessus sont sur `offline-first-perf-ux`, `flutter analyze` propre (0 erreur) à chaque étape.
- L'utilisateur était en train de retester `flutter run` après le dernier nettoyage de cache — **résultat non confirmé** au moment du "fin" (dernier message reçu : le build avait échoué sur cache corrompu, cache re-nettoyé, pas encore reconfirmé bon après ce nettoyage).
- **P1 du plan offline-first non commencé** : cache Firestore Tier A (`shared_preferences`)/Tier B (`sqflite`, nouvelles tables `cached_vendors`/`cached_products`), `LocationService` unifié + persistance locale (unifierait la piste ouverte de la section 3 ci-dessus), refonte recherche (debounce + requêtes structurées). Voir le plan complet pour le détail des sections 3, 5, 6.
- **P2 non commencé** : profil `DietaryPreferences`, skeleton loading.
- Backend FlexPay (hors repo) : code optimisé et déployé, comportement à confirmer par l'utilisateur en conditions réelles.

---

## Session 2026-08-27 — corrections checkout/paiement, App Check, i18n, perf listes

Branche `fix/checkout-ui-dropdown-i18n` (le nom ne couvre plus tout le périmètre réel de la session, mais fusionnée telle quelle dans master en fin de session). Session dense, sans plan écrit unique — enchaînement de bugs signalés par l'utilisateur en testant sur device réel, plus deux audits proactifs (perf, puis textes non traduits) menés en mode plan avec agents d'exploration.

### 1. Bug crash dropdown "TakeAway" (home_screen.dart)
`items: ['Delivery', 'TakeAway'.tr]` utilisait la valeur **traduite** comme identité du `DropdownButton`, alors que la valeur stockée/sélectionnée restait la clé anglaise brute — mismatch dès que la langue n'est pas l'anglais → crash `DropdownButton` ("exactly one item"). Revenu à des clés brutes pour l'identité (`home_controller.dart` aussi, `RxString selectedOrderTypeValue = "Delivery".obs` sans `.tr`), le libellé affiché reste traduit via `TranslatedText`.

### 2. Checkout — moyen de paiement et localisation (cart_screen.dart)
- **Le libellé "Pay Via" ne s'affichait pas après sélection** : `RenderFlex` avec contraintes non bornées — un `Flexible` avait été ajouté dans une chaîne `Row`→`Column`→`Row` toute en `mainAxisSize.min`, incompatible avec `Flexible`/`Expanded`. Restructuré (l'`Expanded` racine du bloc redevient dimensionné normalement) pour que le libellé s'affiche réellement.
- **Le choix de paiement ne survivait pas à un changement d'onglet** : `CartController` est recréé à chaque fois que l'onglet Panier redevient actif (pas d'`IndexedStack` dans `dash_board_screen.dart`), donc `selectedPaymentMethod` repartait sur le gateway par défaut. Persisté dans `Preferences.selectedPaymentMethod`, relu en priorité dans `getPaymentSettings()` avant la logique de choix par défaut.
- **Label "Localisation" ajouté** à côté de l'icône sur la carte d'adresse ("Delivery Address", clé déjà traduite) ; si aucune localisation n'est définie, affiche "Add Location" au lieu de "null" et masque l'adresse complète vide.
- **Workflow post-paiement Mobile Money vérifié par lecture de code** (pas un bug — confirmation demandée par l'utilisateur) : `flexPayMakePayment()` suit exactement le même chemin `Get.to → .then(placeOrder()) → setOrder() → OrderPlacingScreen` que toutes les autres gateways.

### 3. Écran de succès FlexPay (rechargement wallet)
Redirection auto à 2s trop courte pour lire l'écran, aucun bouton manuel. Ajout d'un `Timer` annulable (`_successRedirectTimer`), bouton "Back" visible immédiatement, redirection auto étendue à 30s **uniquement en contexte rechargement wallet** (`isWalletTopUp: true` — en checkout, la commande n'est passée qu'au retour de cet écran donc le délai court est intentionnel), message "Cela peut prendre jusqu'à une minute avant d'apparaître sur votre portefeuille." affiché dans ce même contexte.

### 4. Audit perf #1 : fuites de listeners, requêtes N+1, limites Firestore
- **Fuites de listeners** (`onClose()` manquant ou `StreamSubscription` jamais stockée/annulée) : `live_tracking_controller.dart` (le pire — un nouveau listener driver était rattaché à chaque mise à jour de commande sans annuler le précédent, ils s'empilaient pendant tout le suivi de livraison), `restaurant_details_controller.dart`, `category_restaurant_controller.dart`, `dine_in_controller.dart`.
- **N+1 → parallélisées** : `favourite_controller.dart` (jusqu'à 3×N requêtes séquentielles), `restaurant_details_controller.dart` (produits + favoris/coupons en parallèle au lieu de séquentiel), `order_controller.dart`/`order_details_controller.dart` (vérification stock produit par produit).
- **Limites Firestore ajoutées** : `getStory`, `getAllOrder` (200, généreux), `getVendorReviews`, `getAllCashbak` ; `getVendorCuisines` ne télécharge plus la collection entière des catégories (seulement celles utilisées par le vendeur, par lots de 30).

### 5. Bug offline + démarrage lent (splash_controller.dart, main.dart)
- **Déconnexion en offline** : `isLogin()`/`getUserProfile()` (`fire_store_utils.dart`) avalaient les erreurs réseau et renvoyaient `false`/`null`, confondant "profil absent" et "lecture impossible hors-ligne" → déconnexion ou blocage indéfini sur le splash. `isLogin()` réécrit pour laisser l'erreur remonter jusqu'au fallback existant (garde l'utilisateur sur le dashboard en cache) ; branche `else` ajoutée pour `getUserProfile() == null` (auparavant : aucune action, splash bloqué à vie).
- **`NotificationService.getToken()` non protégé** dans le même flux : un échec (hors-ligne) faisait échouer toute la redirection au lieu d'être ignoré — enveloppé dans `try/catch`.
- **Splash bloqué au démarrage à froid** : `onInit()` appelait `redirectScreen()` de façon synchrone avant que le `Navigator` soit monté (`Get.offAll` échouait silencieusement quand le cache Firestore répondait très vite). Différé via `WidgetsBinding.instance.addPostFrameCallback`.
- **Démarrage lent** : délai artificiel fixe de 3s supprimé (`Timer(Duration(seconds:3), ...)` remplacé par le postFrameCallback ci-dessus) ; rafraîchissement du token FCM (`updateUser`) rendu non-bloquant (`await` retiré).
- **Cause principale du "tout est lent" (connexion Google, paiement...)** : `FirebaseAppCheck` utilisait `AndroidProvider.playIntegrity` même en build debug/sideload — Play Integrity échoue systématiquement hors Play Store (`Integrity API error -17`, `403 App attestation failed`, visible dans les logs device), donc **chaque appel Firebase tentait une vraie attestation avec retry/backoff avant de répondre**. `main.dart` : provider `debug` en mode `kDebugMode`, `playIntegrity` conservé en release. **Nécessite un arrêt complet + relance `flutter run` pour prendre effet** (pas un simple hot restart — le provider natif reste initialisé côté Android tant que le process tourne).
- Ajout "by Rapyogo Ltd" en bas de l'écran de bienvenue (`splash_screen.dart`), ancré via `Expanded` + `Padding` bottom.

### 6. Crash Stripe trouvé en marge (3 sites)
`Stripe.publishableKey = stripeModel.value.clientpublishableKey.toString()` s'exécutait sans garde à chaque init de `cart_controller.dart`/`wallet_controller.dart`/`gift_card_controller.dart` — si la clé est vide/absente (gateway Stripe non configurée pour ce déploiement), le SDK natif Stripe plantait (`IllegalArgumentException: Invalid Publishable Key`) à répétition, visible dans les logs. Gardé derrière `stripeModel.value.isEnabled == true && clientpublishableKey non vide` dans les 3 fichiers.

### 7. UX paiement Mobile Money (flexpay_payment_screen.dart)
- Validation du numéro resserrée : format RDC réel (`0XXXXXXXXX` ou `+243XXXXXXXXX`) au lieu d'accepter 8-15 chiffres quelconques.
- **Numéros récents cliquables** : mémorisés (max 3, `Preferences.recentMobileMoneyNumbers`) après une initiation de paiement réussie, affichés en puces au-dessus du bouton "Continuer".
- **Messages dynamiques pendant l'attente** : 5 messages tournent toutes les 5s (fondu) au lieu d'un texte fixe, expliquant le processus étape par étape.
- Tous les textes de cet écran (précédemment codés en dur en français) basculés sur `.tr`/`TranslatedText`, clés ajoutées en en/fr/ar/hi.

### 8. Bug FlexPay callback corrigé et déployé en production
`flexPayCallback` (`Order Tracking Firebase Function/functions/products/flexpay.js`, hors repo git) ne cherchait le paiement à mettre à jour QUE par `reference` — si ce champ manquait dans le callback envoyé par FlexPay (constaté en pratique, malgré la doc officielle qui promet de l'inclure), la fonction rejetait silencieusement (400, aucune écriture Firestore) et le document restait bloqué sur `pending` indéfiniment. C'était **la cause du symptôme signalé** : le résultat du paiement n'apparaissait jamais en temps réel côté app, seule la vérification manuelle (qui interroge FlexPay par `orderNumber`) révélait le vrai statut. Corrigé pour chercher par `reference` puis, en repli, par une requête sur `orderNumber` (pattern documenté dans le skill `flexpay-mobile-money`, où la recherche par `orderNumber` est justement la voie primaire). **Déployé sur `rapyogo-2bccd`** (gateway toujours LIVE, marchand `RAPYOGO_SARL`) — comportement en temps réel à reconfirmer par l'utilisateur avec un vrai paiement.

### 9. Audit textes non traduits — beaucoup de faux positifs, corrigés uniquement les vrais
Audit mené via 2 agents d'exploration puis 1 agent de planification qui a **détecté et corrigé un biais méthodologique** des deux premiers : l'extraction des clés dans `lib/lang/*.dart` ne matchait que les guillemets doubles, alors que ~165 clés sur 389 dans `app_fr.dart` utilisent des guillemets simples → ~78% de "clés manquantes" rapportées étaient déjà présentes. Autre faux positif découvert en vérifiant le code directement : `CustomDialogBox` et `TextFieldWidget` (32 sites "hintText non traduit" signalés) appliquent déjà `.tr` **en interne** — zéro correctif nécessaire sur ces deux catégories entières.

**Corrigé réellement** :
- Bug typo `TranslatedText('Cancel.tr')` (`address_list_screen.dart`) → `'Cancel'` (le `.tr` avait été tapé dans la chaîne au lieu d'être chaîné).
- Variante incohérente `"CancelPayment?"` (`xenditScreen.dart`) alignée sur les 6 autres écrans de paiement (`"Cancel Payment?"`) ; la clé elle-même (avec point d'interrogation) était en fait absente des 4 fichiers de langue malgré son usage à 7 endroits — ajoutée.
- ~34 clés réellement manquantes ajoutées aux 4 fichiers de langue actifs (en/fr/ar/hi) — essentiellement l'écran `mtn_momo_payment_screen.dart` (jamais localisé du tout) et une quinzaine de fragments interpolés (`${'Tax:'}`, `${'Ratings'}`, `${'Buy'}`, etc.) jamais passés par `.tr` malgré une clé déjà existante.
- ~250 appels `ShowToastDialog.showToast(...)` analysés (335 sites, dédupliqués à 112 messages uniques) → 31 réellement absents des fichiers de langue, ajoutés. `showToast()` applique déjà `.tr` en interne, aucun changement de code nécessaire pour cette catégorie.
- Typo `"Did't receive any code?"` → `"Didn't receive any code?"` (`otp_screen.dart`), et normalisation d'un doublon de clé à guillemet typographique différent (`you'll` vs `you'll` avec apostrophe courbe) dans `refer_friend_screen.dart`.
- Un doublon `.tr.tr` trouvé et corrigé en marge dans `mtn_momo_payment_screen.dart`.
- Aucun doublon de clé restant sur les 4 fichiers de langue (vérifié par script, 612-616 clés chacun).

### 10. Audit perf #2 : cache par item de liste + portée des rebuilds GetX
Suite de l'audit #1 (deux points plus lourds, laissés de côté initialement). Mené en mode plan avec agents d'exploration qui ont **corrigé le périmètre annoncé par l'audit original** avant implémentation (voir ci-dessous).

**Cache par item (vendeur/produit refetché à chaque rebuild au lieu d'être mis en cache)** — pattern de référence repris de `cart_controller.dart` (`RxMap` rempli une fois par `Future.wait`) :
- `order_screen.dart`/`order_details_screen.dart` : le fetch vendeur (vérification du statut d'abonnement pour le bouton "Reorder") est **légitime** (pas une simple redondance comme supposé initialement — le vendeur embarqué dans la commande peut être périmé), mais refetché à chaque rebuild → mis en cache (`OrderController.vendorCache`, `OrderDetailsController.reorderVendor`).
- `search_screen.dart` : le vendeur était déjà en mémoire (`vendorList`) — plus aucun fetch réseau du tout, recherche synchrone.
- `home_screen.dart`/`home_screen_two.dart` (pubs + stories, `HomeController.vendorById()`) et `all_advertisement_screen.dart` (nouveau `AdvertisementListController.vendorById()`) : même chose, le vendeur est déjà dans `allNearestRestaurant` — zéro nouveau fetch, juste une recherche synchrone dans les données déjà chargées.
- `favourite_screen.dart` : nouveau cache `foodVendorCache` (les plats favoris peuvent appartenir à des vendeurs non favoris, donc pas de liste existante à réutiliser ici).
- `review_list_screen.dart` : l'audit avait mal identifié la cible (décrit comme "fetch vendeur", en réalité un nom de produit + un titre d'attribut d'avis) — deux caches ajoutés une fois la vraie cible identifiée.
- `story_view.dart` (site optionnel, priorité basse) : cache par index — le swipe déclenchait 2 `setState()` donc 2 refetch du même vendeur à chaque swipe.
- Fuite de listener corrigée en marge dans `advertisement_list_controller.dart` (même bug que l'audit #1, pas encore vu à ce moment-là).

**Portée des `Obx`/`GetX`** (écrans entiers reconstruits au moindre changement d'état) : seul `search_screen.dart` avait un vrai problème facilement isolable (AppBar/champ de recherche reconstruits à chaque frappe) — corrigé en isolant `body:` dans son propre `Obx`. **`home_screen.dart`, `home_screen_two.dart` et `dine_in_screen.dart` vérifiés et laissés intacts** : les carrousels de bannières et les listes de restaurants sont déjà des widgets séparés avec leur propre `Obx` (déjà bien architecturés) ; les champs `isVag`/`isNonVag` que l'audit visait sur `dine_in_screen.dart` **n'existent pas** dans le contrôleur. Le seul point encore dans la portée large du `GetX` global (toggle Populaire/Tout, Liste/Carte) est déclenché uniquement par un tap utilisateur, pas en continu — corriger ça demanderait de restructurer plusieurs centaines de lignes pour un gain quasi nul, non fait.

**Toujours reporté (risque réel, pas retenté cette session)** : `cart_screen.dart` et `restaurant_details_screen.dart` — lectures réactives éparpillées sur la quasi-totalité du fichier plutôt que regroupées, correction = quasi-réécriture.

### État en fin de session
- `flutter analyze` propre (0 erreur) sur chaque fichier modifié, vérifié au fur et à mesure.
- **Rien de tout ça n'a encore été retesté sur device réel dans son ensemble** par l'utilisateur (App Check nécessite un arrêt complet + relance pour être pris en compte — pas encore confirmé fait) : à valider en priorité en prochaine session — connexion Google, paiement Mobile Money bout en bout (temps réel), écrans recherche/accueil/favoris/commandes/pubs/avis, mode hors-ligne, redémarrage à froid.
- Backend FlexPay (`flexPayCallback`) déployé et corrigé en production — comportement temps réel à confirmer avec un vrai paiement.
- Pistes ouvertes des sessions précédentes (clé de service compte à révoquer, comptes `@gromart.com` à nettoyer, IPs FlexPay à clarifier, logo Mobile Money à remplacer, config iOS jamais terminée) — **toujours pas traitées**, non touchées cette session.

---

## Session 2026-08-28 — LocationService (offline-first P1), mise en page adaptative, audit tarification

Branche `feat/location-service`, **fusionnée et poussée sur `master`** (`3e1a372..31de21c`, 14 commits). Plan écrit en mode plan : `C:\Users\RAPYOGO\.claude\plans\bonjour-shiny-pelican.md`.

> ⚠️ Le plan offline-first de la session du 26 était censé vivre dans
> `tu-es-un-lead-synthetic-brooks.md` — **ce fichier a été écrasé** par le plan perf du 27.
> Le contenu du P1 a dû être reconstruit par exploration du code. Les fichiers de plan
> portent un nom généré et se réécrivent : ne pas s'y fier comme archive.

### 1. LocationService — le P1 « localisation » du plan offline-first est livré

Nouveau `lib/services/location_service.dart`, service GetX permanent posé dans `main.dart` **avant `runApp`** (donc la localisation est restaurée avant que `SplashController` s'exécute, hors-ligne compris).

**Décision de conception structurante** : `Constant.selectedLocation` devient une **façade getter/setter** vers le service, au lieu de migrer les 19 sites d'écriture. Vérifié par grep : aucun site ne mute l'objet en place, tous font une assignation complète — le setter les intercepte donc tous. Conséquence : la persistance est effective partout sans toucher une ligne des 6 parcours d'authentification (splash, 3 logins, signup ×2, OTP), les plus coûteux à retester. Effet de bord voulu : le getter lit un `Rxn`, donc tout `Obx`/`GetX` lisant `selectedLocation` devient réactif.

L'état est un `Rxn<ShippingAddress>` **statique** (le null fait partie du type, l'analyseur refuse une lecture non gardée). `setLocation()` refuse toute adresse sans coordonnées : une `ShippingAddress()` vide ne peut jamais écraser une localisation valide.

Persistance en SharedPreferences (`selectedLocationKey`, `selectedLocationSourceKey`). `Preferences` n'ayant ni `containsKey` ni sentinelle, trois règles rendent l'état « défini mais vide » inatteignable : ne jamais écrire `""`, traiter `""` comme jamais défini, revalider les coordonnées après décodage. Priorité en cas de conflit : **le profil Firestore gagne** sur le cache local (choix explicite et cross-device de l'utilisateur), le cache servant d'hydratation instantanée.

`UserLocation.fromJson` castait `json['latitude']` brut sur un `double?` → `TypeError` dès que Firestore rend un `int`. Passé en `(json['latitude'] as num?)?.toDouble()` — prérequis de la persistance.

`LocationService.clear()` ajouté aux **12 `signOut()`** de l'app : sans purge, la localisation du compte A fuitait dans la session du compte B (`clearSharPreference()` n'est appelé nulle part).

### 2. Les 5 coordonnées de Mumbai codées en dur, supprimées

`19.228825, 72.854118` était écrit dans 5 blocs `catch` quand le GPS échouait — la donnée factice explicitement rejetée le 2026-08-26 pour `(0,0)`. `grep 19.228825 lib/` → **0 occurrence**.

Nouveau `lib/widget/location_failure_sheet.dart` : la cause est nommée (service désactivé, permission refusée, permission bloquée, signal trop faible) et chaque cas propose l'action qui la résout. En échec, **aucune localisation n'est renseignée et l'écran ne navigue pas**.

Le site le plus dangereux était `address_list_screen.dart:71` : il ne s'assignait pas la fausse adresse, il la renvoyait par `Get.back(result:)` à ses 3 appelants **plus le panier** — le seul des cinq qui contaminait le checkout. Il avait été manqué par la première exploration justement parce qu'il n'assignait pas `selectedLocation` directement.

**Gain fonctionnel non prévu** : le géocodage inverse (qui a besoin du réseau) faisait tomber tout l'appel GPS dans le `catch`, jetant une position parfaitement valide pour lui substituer Mumbai. Il a désormais son propre `try/catch` — les coordonnées survivent, seul le libellé manque.

Le flux de sélection sur carte, dupliqué dans 3 écrans, est extrait dans `lib/widget/location_picker_flow.dart`. Au passage, 3 sites appelaient `getCurrentPosition()` **et jetaient le résultat**, uniquement pour déclencher la permission avant d'ouvrir le picker — supprimé, un picker manuel n'a pas besoin du GPS.

### 3. « Localisation non résolue » ≠ « zone non couverte »

Les deux requêtes géo construisaient leur centre avec `?? 0.0` : sans localisation, l'app cherchait les restaurants autour de **(0,0)**, au large de l'Afrique. Elles ramenaient une liste vide, que les écrans interprétaient comme « aucun restaurant dans votre zone » — message trompeur, et le bouton « Change Zone » n'y changeait rien.

Garde ajoutée en tête des deux `async*`, `?? 0.0` supprimé. Nouveau `lib/widget/location_prompt_view.dart` (« Où livrer ? » + 3 CTA) affiché dans ce cas sur `home_screen`, `home_screen_two` et `dine_in_screen`.

`LocationService.refreshZone()` remplace **3 implémentations divergentes** du calcul de zone. Celle de `home_controller` affectait `selectedZone` à **chaque itération** : sans zone correspondante, l'app repartait avec la dernière zone de la liste et `isZoneAvailable = false`.

> **Dette assumée** : `Constant.selectedZone` **n'est pas remis à `null`** quand aucune zone ne correspond. Il est lu avec un bang `!` sur ~11 sites (`home_screen.dart:1956,1968,2057,2069`, `home_screen_two.dart:898,910`, `dine_in_screen.dart:1083,1095`, `favourite_screen.dart:207,498`, `fire_store_utils.dart:237`), dont deux dans `favourite_screen` qui s'affiche indépendamment de `isZoneAvailable`. Passe dédiée nécessaire ; `isZoneAvailable` reste la seule source de vérité sur la couverture.

### 4. Gardes null et piège du checkout

`getFullAddress()` ne gardait pas `locality` → affichait littéralement `" null "` dans le header d'accueil. Les deux headers passent à `LocationService.displayLabel`.

`Constant.getDistance` faisait `double.parse` sur ses 4 arguments. Les appelants passent `vendorModel.latitude.toString()` : quand la latitude est null, la chaîne vaut `"null"` — non-null, donc aucune garde amont ne l'attrape — et le parse levait une `FormatException` en plein build. Passé en `double.tryParse`, rend `''`.

> **Contrepartie traitée dans le même commit** : `cart_controller.dart:239` est le seul appelant vivant qui parse le retour de `getDistance`. Sa garde ne couvrait que l'adresse client, pas le vendeur — **un vendeur sans coordonnées y plantait déjà le checkout avant cette session**. Sans distance, les frais de livraison restent à 0 au lieu de lever.

### 5. Mise en page : boutons adaptatifs aux traductions longues

**Cause structurelle** : dans `RoundedButtonFill` et `RoundedButtonBorder`, le libellé était posé directement dans le `Row` sans `Flexible` — il prenait sa largeur naturelle et débordait dès qu'une traduction dépassait l'anglais (le français est régulièrement 30 % plus long).

Correction en deux temps, après retour utilisateur :
1. `Flexible` + `FittedBox` — le texte rétrécissait, mais le fond gardait sa taille figée.
2. **La largeur/hauteur demandée devient un minimum** (`BoxConstraints` au lieu de `width`/`height`) et le `Row` passe en `mainAxisSize.min` : **le fond s'élargit avec le libellé**. Défaut à 100 % inchangé (plein écran), seuls les boutons compacts grandissent.

Garde ajoutée : `Flexible` n'est licite que sous une largeur bornée. Le bouton n'ayant plus de largeur fixe, il pourrait se trouver dans un parent à largeur infinie (liste horizontale) où `Flexible` lèverait une exception. Un `LayoutBuilder` ne l'applique que si les contraintes sont finies.

Corrigé aussi : la ligne « Ouvert • Voir les horaires • X pour deux » (`restaurant_details_screen` **et** `dine_in_details_screen`, bloc dupliqué) débordait de 26 px — passée en `Wrap`. Ses trois textes déclaraient pourtant `overflow: ellipsis`, mais **dans leur `TextStyle`**, où la propriété reste sans effet tant que la largeur n'est pas contrainte : le code avait l'air de gérer le cas sans le gérer. Et le `Row` du livreur (`order_details_screen`) n'avait de flex sur aucun de ses deux textes — il débordait dès qu'un nom était un peu long, dans n'importe quelle langue.

> **Erreur commise et corrigée dans la session** : des traductions françaises volontairement raccourcies par l'utilisateur (pour supprimer ces mêmes débordements) ont été prises pour une corruption et rallongées, réintroduisant un overflow. Voir la mémoire `user-edits-in-working-tree`. Une fois la cause structurelle traitée, **toutes les valeurs longues ont été rétablies** — `app_fr.dart` est identique à l'état d'avant session, aux 19 clés ajoutées près.

### 6. Migration des fichiers hébergés sur l'ancien projet `foodies-3c1d9`

6 champs de `settings` référençaient le bucket Storage du projet du template : son de notification (`globalSettings.order_ringtone_url`), drapeaux anglais et arabe (`languages.list`), logos midtrans / orange money / xendit. Les fichiers ont été téléchargés et téléversés dans `rapyogo-2bccd.appspot.com`, les URLs mises à jour dans Firestore. Sauvegarde des valeurs d'origine : `migration_backup.txt` (dossier temporaire de session, non pérenne).

**Un septième n'a pas pu l'être** : `googleMapKey.placeHolderImage` renvoie **HTTP 404** — le fichier a déjà été supprimé de l'ancien projet. Le risque n'était donc pas théorique. À re-téléverser depuis le panel admin (le correctif Flutter du 25/08 affiche une icône locale en attendant).

### 7. Audit de tarification (Firestore lu en direct, aucune modification de code)

- `settings/adminSettings` (= **frais de plateforme**, pas la commission) portait `enable: true, amount: 16` → **16 $ facturés sur chaque commande, emporter compris**. L'utilisateur l'avait activé sans le savoir ; il l'a désactivé en séance (`enable: false, amount: 0`). Ce n'était pas un bug de calcul.
- `settings/freeDeliveryFeature` : **le document n'existe pas**.
- Devise active : **USD**.
- `settings/DeliveryCharge` ajusté par l'utilisateur en séance : `per_km 20 → 1`, `minimum 10 → 2`, seuil 5 km. Envisageait ensuite `minimum 3, seuil 10 km`.

**Défaut de formule (code du template, aucun réglage ne le corrige)** : au-delà du seuil, `cart_controller` applique le tarif kilométrique à la **distance totale**, pas aux kilomètres excédentaires. D'où une marche au franchissement, de montant `seuil × tarif − forfait` :

| Config | 5 km | 5,1 km | 10 km | 10,1 km | Marche |
|---|---|---|---|---|---|
| Avant (20/10/5) | 10 $ | **102 $** | 200 $ | 202 $ | 90 $ |
| Actuelle (1/2/5) | 2 $ | 5,10 $ | 10 $ | 10,10 $ | 3 $ |
| Envisagée (1/3/10) | 3 $ | 3 $ | 3 $ | **10,10 $** | 7 $ |

Noter le contre-intuitif : **augmenter le seuil aggrave la marche**.

**Recommandation documentée pour le terrain** (à appliquer quand les données réelles seront collectées) — formule continue, alignée sur les pratiques Uber Eats / Deliveroo :
```
frais = forfait                                    si distance ≤ seuil
frais = forfait + (distance − seuil) × tarif_km    au-delà
```
Avec forfait 2 $, seuil 3 km, tarif 0,50 $/km : 3 km → 2 $, 5 km → 3 $, 10 km → 5,50 $, 20 km → 10,50 $. Aucune marche. **Ne demande aucun changement du panel admin**, les 3 champs existants suffisent — uniquement `cart_controller.calculatePrice()`.

Existent chez les grandes plateformes mais **absents du modèle de données** (chacun = champ Firestore + panel admin) : plafond de frais, frais « petite commande » sous un panier minimum, tarification dynamique.

### 8. Livraison gratuite : deux mécanismes distincts, ne pas les confondre

- **Fonctionnel** : `vendorModel.isSelfDelivery == true && Constant.isSelfDeliveryFeature == true` → frais à 0. `globalSettings.isSelfDelivery = true`, donc **actif**. C'est la livraison gratuite quand le restaurant a ses propres livreurs.
- **Dormant** : la promotion pilotée par l'admin (gratuit en deçà de X km, ou au-delà de Y de panier). Le drapeau `isEnableFreeDeliveryByAdmin` est lu à 9 endroits et enregistré dans la commande, mais **n'est mis à `true` nulle part en code actif**. La logique existe en commentaire (`cart_controller.dart:506-512`). Vérifié : **elle était déjà commentée dans le commit initial** — ça vient du template, personne dans cet historique ne l'a cassée.
- **Défaut latent si on la rebranche** : la taxe de livraison est calculée sur `deliveryCharges` sans consulter le drapeau, alors que le total l'exclut → le client serait taxé sur des frais qu'il ne paie pas. Les deux corrections vont ensemble.

### 9. Environnement — fermetures brutales de l'app expliquées

L'utilisateur signalait que l'app « se ferme brusquement presque à chaque fois ». **Ce n'est pas un bug applicatif.** Capture logcat : le `lowmemorykiller` tue WhatsApp 3 fois et 4 autres processus en 25 secondes, avec pour motif `low watermark is breached and swap is low (0kB)` et même `device is not responding`. Viteat n'apparaît pas dans la liste **uniquement parce qu'elle est au premier plan** — Android tue l'app active en dernier.

Téléphone de test (Infinix X693) : **65 Mo de RAM libre** sur 3,8 Go, **1,4 Go de stockage libre sur 109 Go (99 %)**, zéro swap. Le build debug (VM Dart + hot reload) aggrave nettement. Recommandé : tester en `--release`, fermer WhatsApp/Facebook, libérer du stockage. Voir mémoire `android-build-gotchas`.

PC : disque à 100 % (363 Mo libres), un build a échoué après 35 min sur `java.io.IOException: Espace insuffisant sur le disque`. Résolu par `flutter clean` + purge de `Temp` + **`powercfg /h off`** (supprime `hiberfil.sys`, 2,8 Go) → 12 Go libres. `pagefile.sys` pèse 21 Go et reste le plus gros levier si besoin.

adb s'est déconnecté 3 fois ; l'interface « Android ADB Interface » est passée en statut `Error` côté Windows. Le cycle `adb kill-server` + `adb start-server` la fait réapparaître.

### État en fin de session
- `flutter analyze` : **0 erreur**, 312 problèmes contre 318 en baseline (tous `info` préexistants ; les avertissements sont passés de plusieurs à un seul, dans `test/widget_test.dart`).
- **Checkout validé sur device réel par l'utilisateur.** Persistance de la localisation prouvée objectivement : `flutter.selectedLocationKey` contient une position GPS réelle à Goma (`-1.665755, 29.2202079`), source `gps`, géocodage inverse rempli, survivant au redémarrage de l'app.
- `master` poussé sur `github.com/rapyogo/viteat`.

### Pistes ouvertes (mises à jour)
- **Formule de tarification de livraison** — correction documentée en section 7, à appliquer quand les données terrain seront collectées. Décision utilisateur explicite : attendre.
- **P1 offline-first, suite** — l'utilisateur a observé que **l'app est plus rapide hors-ligne qu'en ligne**. Diagnostic confirmé : la persistance Firestore est active (100 Mo) mais **aucun appel n'utilise `GetOptions(source: Source.cache)`** (0 occurrence). Tous les `.get()` sont en `serverAndCache`, donc en ligne Firestore attend le serveur avant de rendre la main, même quand le cache contient la donnée. Correction = lecture *cache-first* puis rafraîchissement en arrière-plan (*stale-while-revalidate*). **Le plus gros gain ressenti pour le moins d'effort — à traiter en premier.** Ensuite seulement : cache Tier A/B (`shared_preferences` / `sqflite`), puis refonte de la recherche (aujourd'hui : une requête Firestore **par restaurant, en séquence, sans limite** à l'ouverture de l'écran).
- **`Constant.selectedZone` avec bang `!`** sur ~11 sites — passe « zone » dédiée (section 3).
- **Livraison gratuite admin** — rebrancher le bloc + corriger la taxe associée, ensemble (section 8).
- `placeHolderImage` à re-téléverser (section 6).
- Non traitées, héritées : clé de service à révoquer, comptes `@gromart.com` à nettoyer, IPs FlexPay à clarifier, logo Mobile Money à remplacer, config iOS (`firebase_options.dart` référence encore `foodies-3c1d9`).
- **Mises à jour du fournisseur du template** : demande explicite de l'utilisateur — en extraire ce qui est utile **sans écraser les personnalisations**. Voir mémoire `template-updates-never-overwrite`.

---

## Session 2026-08-29 — app **driver** (livreur) : mise sous git, alignement Firebase, diagnostic terrain

Première session consacrée au dossier `driver/`. L'app cliente n'a pas été touchée.

### 1. Le dossier `driver/` est désormais sous git

Il n'avait aucun historique. Commit initial `e5158fa` fige l'état antérieur **avant** toute
modification, comme point de retour. Remote : **`github.com/rapyogo/viteat_drive`** (dépôt **privé**,
préexistant et vide) — à ne pas confondre avec `rapyogo/viteat`, qui est **public**.

`.gitignore` complété : il laissait passer `android/build/`, `android/app/build/`,
`android/app/.cxx/` (3 Mo) et `.firebase/`. 408 fichiers versionnés, aucun artefact.

Un `CLAUDE.md` a été créé à la racine du driver (architecture GetX, `FireStoreUtils`, cycle de vie
des commandes, cartes Google/OSM, pièges du dépôt).

### 2. Alignement complet sur `rapyogo-2bccd` (commit `faf2021`)

Deux valeurs de `lib/firebase_options.dart` étaient **invalides**, pas seulement périmées :

- `apiKey` contenait en réalité le **`certificate_hash` SHA-1** recopié depuis `google-services.json` ;
- `messagingSenderId` était préfixé `1:`.

**Pourquoi personne ne l'avait vu** : sur Android le SDK natif s'auto-initialise depuis
`google-services.json` **avant** Flutter, et `Firebase.initializeApp(options:)` récupère alors l'app
déjà créée **en ignorant les options Dart**. Elles n'étaient donc jamais exercées — mais auraient fait
foi sur toute autre plateforme. Vérifié à l'exécution en fin de session : les options effectives sont
bien `projectId=rapyogo-2bccd`, `apiKey=AIzaSyACw_…`.

`firebase.json` pointait intégralement sur `foodies-3c1d9` → réécrit. Restes du template corrigés :
`userAgentPackageName` des tuiles OSM, `applicationId` du `build.gradle.kts` dormant.

**Audit Firestore** : sur les 53 documents de `settings`, **une seule** valeur pointe encore vers
l'ancien projet — `settings/googleMapKey.placeHolderImage` → `foodies-3c1d9.appspot.com`. Elle est
**morte** (le code lit `settings/placeHolderImage`, correct). Sa correction a été **refusée par le
garde-fou du mode auto** et reste à faire. Aucun résidu dans `dynamic_notification`,
`email_templates`, `on_boarding`, `currencies`. `senderId` = `1041336319516` (bon projet).

**Clé Google Maps** `AIzaSyDQIaQ…` : vérifiée par triple recoupement (manifest driver, manifest
customer, `settings/googleMapKey.key`) — c'est bien la clé de la plateforme. Son absence de
`google-services.json` est normale : c'est une clé GCP, pas Firebase.

### 3. Fichiers morts supprimés (commit `8be4875`)

`android/{build,settings}.gradle.kts`, `android/app/build.gradle.kts` et un second `MainActivity.kt`
(`package com.foodies.driver.driver`). **Preuve qu'ils étaient inertes** : `build.gradle.kts` contenait
de la syntaxe Groovy (`url "..."`), invalide en Kotlin DSL — s'il avait été évalué, le script n'aurait
pas compilé. Validé par `flutter build apk --debug` (succès) : le plugin `google-services` échoue si
l'`applicationId` n'est pas dans `google-services.json`, ce qui confirme le passage par le Groovy.

**iOS volontairement laissé de côté** (décision utilisateur) : `ios/` est le seul endroit du dépôt qui
référence encore l'ancien projet (bundle `com.foodies.driver.ios`, client IDs `275231286183-…`,
`GoogleService-Info.plist` réduit à un gabarit). Rien n'y est corrigeable tant que l'app iOS
`com.rapyogo.livrheur` n'existe pas sur `rapyogo-2bccd`.

### 4. Diagnostic du blocage au splash — cause racine trouvée

L'app restait figée sur le splash. Branche **`diagnostic-splash-bloque`** (commit `1ac6170`, poussée,
**non mergée** : l'instrumentation est temporaire).

**Le `runZonedGuarded` de `main.dart` avait un handler vide** — toute exception au démarrage
disparaissait sans trace. C'est ce qui rendait le diagnostic aveugle. Une fois qu'il journalise :

```
PlatformException(PERMISSION_DENIED, Background location permission denied)
```

levée par `dash_board_controller.dart:94` (`location.enableBackgroundMode`), la permission
`ACCESS_BACKGROUND_LOCATION` étant refusée (`granted=false` ; `FINE_LOCATION` est en `ONE_TIME`).
**C'est aussi pourquoi la carte reste bleue** : sans position, elle est centrée sur des coordonnées
nulles — l'océan. Le SDK Maps fonctionne (contrôles et logo présents).

**Hypothèse App Check : fausse.** La trace `.get() exists=true, fromCache=false` prouve que Firestore
dialoguait avec le serveur. Le blocage initial venait du **DNS** (`EAI_NODATA`), transitoire. La
bascule `kDebugMode ? AndroidProvider.debug : playIntegrity` reste défendable en soi (Play Integrity
ne peut pas attester un APK debug) mais **n'a pas résolu ce bug**. Jeton de debug de cette
installation, autorisé par l'utilisateur : `90c8e112-ad57-4122-a8ba-4a474315d3fa`.

**Leçon de méthode** : `dart:developer log()` ne sort **ni** sur la console de `flutter run` **ni**
dans logcat — seulement vers le VM Service. Trois lancements perdus. Utiliser `debugPrint`.

### 5. Les deux types de livreurs, et pourquoi les notifications manquent

Confirmé par l'utilisateur et par le code : **livreur plateforme** (`vendorID` vide) → dispatch
automatique par `delivery.js` ; **livreur de restaurant** (`vendorID` renseigné) → **affectation
manuelle** par le restaurant. `delivery.js` écarte explicitement les seconds (`continue`, ligne 110).
Le compte de test « Interne Rosty » porte un `vendorID` : ne rien recevoir du dispatch est **normal**.

**Cause racine des notifications absentes — prouvée par comparaison avec l'Admin Panel :**

| | Admin Panel | Restaurant Panel |
|---|---|---|
| `storage/app/firebase/credentials.json` | existe | **dossier absent** |
| `FIREBASE_PROJECT_ID` | `rapyogo-2bccd` | ~~**vide**~~ → **faux, voir ci-dessous** |

⚠️ **Rectifié le 29/08/2026 (session 2)** : `FIREBASE_PROJECT_ID` n'était **pas** vide dans le
Restaurant Panel — il vaut `"rapyogo-2bccd"`, entre guillemets. Seul `credentials.json` manquait.
Le champ réellement vide était ailleurs : `settings/notification_setting.projectId` **en base**,
dont dérive `Constant.senderId` des deux apps Flutter.

`OrderController::sendnotification()` sort immédiatement si le fichier manque
(`'Firebase credentials file not found.'`), et le JavaScript fait `await $.ajax(...)` **sans jamais
lire la réponse**. Le restaurant croit avoir prévenu son livreur ; personne n'apprend l'échec. Le
template `assign_order` existe pourtant et `isSelfDelivery` vaut `true` (global **et** restaurant).

⚠️ Le `.env` inspecté porte `APP_ENV=local` / `APP_URL=http://localhost` : **si la production tourne
ailleurs, c'est sur ce serveur-là qu'il faut corriger.** À clarifier avant d'agir.

**Anomalie de données** : sur ce compte, `zoneId` contient un **ID de restaurant**
(`LJz6PoVCZLD36mpWcmTb`, la zone de ce nom n'existe pas). Sans effet tant que le livreur est rattaché
à un restaurant, mais bloquant le jour où on viderait son `vendorID`.

### Pistes ouvertes — app driver (par impact décroissant)

1. **Notifications** — copier `credentials.json` de l'Admin Panel vers
   `Restaurant Panel/storage/app/firebase/` et renseigner ses `FIREBASE_*`. Dossier **non versionné** :
   sauvegarder le `.env` avant. Vérifier d'abord **où tourne la production**.
2. **Preuve de livraison — inexistante.** `completedOrder()` passe à `Order Completed` sans aucune
   vérification : ni code, ni signature, ni photo. Un livreur peut clôturer sans avoir rien remis.
   Recommandation : **code PIN à 4 chiffres** (fonctionne sans réseau à la remise, aucun matériel),
   validé par Cloud Function et non par l'app seule. D'autant plus nécessaire que les commandes en
   self-delivery arrivent directement en `In Transit`, **sans acceptation par le livreur**.
3. **Restauration d'état** — l'app repart de zéro au retour. Suspects classiques écartés
   (`always_finish_activities=0`, `launchMode=singleTop`). Restent : APK debug de 192 Mo qu'Android tue
   vite (tester en release), et **aucun `RestorationMixin`** — le splash relance tout depuis zéro.
4. **Localisation en arrière-plan** — accorder la permission, entourer `enableBackgroundMode` d'un
   `try/catch`, et **donner un vrai handler au `runZonedGuarded`** (seul ajout de la branche de
   diagnostic que je recommande de conserver).
5. **Marque** — l'app affiche « Welcome to Foodie Driver » avec le logo « D » du template. Chaînes en
   dur, hors système de traduction : `splash_screen.dart:35`, `auth_screen/splash_screen.dart:30`,
   login, signup, et `merchantDisplayName` Stripe. Le manifest affiche « Livrheur ».
6. **Débordement UI** — `RenderFlex overflowed by 22 pixels`, `on_boarding_screen.dart:76`.
7. **`settings/googleMapKey.placeHolderImage`** — dernière valeur `foodies` en base (inerte).
8. **Sécurité, héritée du template** : `settings/notification_setting.serviceJson` expose l'URL
   publique du **compte de service Admin SDK**. Qui a l'URL a les pleins pouvoirs sur `rapyogo-2bccd`.
   Changer cela impose de revoir le chemin d'envoi FCM des quatre applications à la fois.

**Environnement** : `adb` s'est déconnecté 5 fois. Un `adb tcpip 5555` de ma part a aggravé les choses
(le démon passe en TCP et ignore l'USB) ; `adb kill-server` + `start-server` répare. `adb connect` en
WiFi est **bloqué par le pare-feu Windows** (erreur 10013). `Get-PnpDevice` dit en trois secondes si
Windows voit le téléphone — à faire **avant** de suspecter le câble.

---

## Session 2026-08-29 (2) — app **driver** : réparation des notifications d'affectation, et le son

Suite directe de la session précédente, dont la piste n°1 était « notifications ». Objectif révisé
en cours de route par l'utilisateur : l'affectation étant manuelle, la notification est un **confort**
— la vraie demande est **que ça sonne**, longuement pour une livraison, deux coups pour une annonce.

### 1. Cause racine, et une correction au HANDOFF

`Restaurant Panel/storage/app/firebase/credentials.json` **n'existait pas**. La garde de
`OrderController.php:47` échouait donc toujours et la méthode renvoyait
`{"success":false,"message":"Firebase credentials file not found."}` **en HTTP 200** — que le JS
jetait, n'ayant ni `success:` ni `error:` sur l'appel livreur.

⚠️ **Le HANDOFF affirmait que `FIREBASE_PROJECT_ID` était vide dans le Restaurant Panel. C'était
faux** : il vaut `"rapyogo-2bccd"`. Seul le fichier manquait.

Pourquoi il manquait : le bootstrap automatique (`HomeController::storeFirebaseService`) exige une
session authentifiée (`$this->middleware('auth')` ligne 10-13), impossible ici — `.env` a
`DB_USERNAME=` et `DB_PASSWORD=` vides, d'où les 7 `SQLSTATE[HY000] [1045]` qui composent tout
`laravel.log`. Le bootstrap n'a jamais **pu** s'exécuter.

### 2. Découverte majeure, hors périmètre initial

**`settings/notification_setting.projectId` était VIDE** (`""`) en production. Or `Constant.senderId`
en dérive dans **les deux apps Flutter**, qui bâtissent leur URL FCM v1 avec (6 points d'appel entre
`customer` et `driver`). **Toutes les notifications émises par les apps mobiles partaient donc vers
une URL invalide depuis l'origine**, silencieusement (`catch` qui renvoie `false`).

Corrigé à `rapyogo-2bccd` par écriture ciblée (`update()`, `serviceJson` et `senderId` intacts).
Le champ est alimenté par le formulaire « Firebase Project ID » de l'Admin Panel.

### 3. Restaurant Panel — corrigé (sauvegardes dans `_backup_restaurant_panel_20260829/`)

- `credentials.json` copié depuis l'Admin Panel (même projet, même compte de service).
- `OrderController::sendnotification` réécrit : chemin absolu au lieu du disque abstrait, `try/catch`
  sur `refreshTokenWithAssertion()`, `die()` supprimé, **lecture du vrai code retour**
  (`$httpCode === 200 && isset($result->name)` — l'ancien renvoyait `success:true` sur un
  `404 UNREGISTERED`), `Log::error('[FCM] …')` avec un code par cause, garde sur `FIREBASE_PROJECT_ID`.
  **La route reste en HTTP 200 en toutes circonstances** : les 4 autres appels de cette route portent
  dans leur `success:` des redirections *et* le remboursement du wallet client.
- `edit.blade.php` : `await callAjax()` puis une **seule** redirection chez l'appelant (le
  `window.location.href` suivait un appel non attendu — le navigateur annulait la requête au
  `unload`) ; `timeout: 8000` ; avertissement à l'écran si l'envoi échoue ; bloc `data`
  (`type: order_assigned`, `orderId`) et `android.notification` (`channel_id`, `PRIORITY_MAX`,
  `vibrate_timings`, `sticky`).
- Clé `lang.driver_not_notified` ajoutée à `resources/lang/en/lang.php`.

### 4. App driver — commits `16e0fdf` et `a76db45`, mergés et poussés sur `master`

**Deux canaux Android distincts**, créés explicitement au démarrage (un canal n'est plus modifiable
après création — les définir avant publication était la seule fenêtre) :

| | `viteat_orders` (Livraisons) | `viteat_announcements` (Annonces) |
|---|---|---|
| Importance | 5 (MAX) | 4 (HIGH) |
| Son | `res/raw/new_order.mp3` | système |
| Vibration | `[0,800,400,800,400,800,400,800]` (~5 s) | `[0,400,250,400]` |

Plus : `default_notification_channel_id` déclaré au manifest (sans quoi tout tombait sur
`fcm_fallback_notification_channel`, **constaté dans `dumpsys`**) ; routage du type `order_assigned` ;
`onTokenRefresh` (absent jusque-là) avec écriture **ciblée** `.update({'fcmToken': …})` et non
`updateUser`, qui fait un `set()` sans merge et pourrait effacer `orderRequestData`.

**Décision utilisateur** : une livraison sonne **jusqu'à ce que le livreur réagisse**
(`FLAG_INSISTENT`), notification `ongoing` non balayable. ⚠️ **Ces deux drapeaux n'existent pas dans
l'API FCM** : ils ne s'appliquent qu'au **premier plan**. App fermée, le système dessine — canal
dédié, son et vibration longue oui, mais une seule fois et balayable. Ne pas promettre mieux sans
passer en data-only, ce qui est **déconseillé** (voir norme N2.7).

### 5. Ce qui n'a **pas** été fait, et pourquoi

**Le son in-app n'a pas été réactivé pour les livreurs internes.** Le plan le prévoyait ;
la vérification a inversé la conclusion. `AudioPlayerService` est en `ReleaseMode.loop` et ne
s'arrête que quand `orderRequestData` se vide — ce qui suppose une acceptation, **étape qui n'existe
pas en self-delivery** (la commande arrive directement en `In Transit`). Le verrou
`vendorID?.isEmpty` de `home_screen_multiple_order_controller.dart:45` est **protecteur**. De plus
`singleOrderReceive` vaut `true` en base : c'est `home_controller.dart` qui est actif, pas ce
contrôleur-là.

### 6. La panne d'origine expliquée — et ce n'était pas le code

L'app **n'était pas exemptée du Doze**. Son *standby bucket* se dégrade quand le téléphone dort
(`ACTIVE` → … → `RESTRICTED`) et Android finit par abandonner les livraisons FCM. Piège vicieux :
**se servir de l'app la remet en bucket `ACTIVE`, donc le problème disparaît dès qu'on teste.**

Corrigé sur le téléphone de test par `adb shell dumpsys deviceidle whitelist +com.rapyogo.livrheur`.

**Vérifié en conditions contrôlées** : `dumpsys battery unplug` + `deviceidle step` jusqu'à `IDLE`,
écran éteint → la notification **arrive**, sur `channel=viteat_orders`, `importance=5`. État batterie
restauré ensuite.

Le journal a aussi montré XOS bloquer en direct le service FCM d'arrière-plan d'une autre app Flutter
(`AutoStart Limit`) : la couche Transsion est réelle et **hors de portée d'adb**.

### 7. Normes consignées

À la demande explicite de l'utilisateur, tout ce qui est validé part désormais dans
`~/.claude/skills/viteat/SKILL.md`, section **« Normes Viteat »** — 17 règles, chacune avec sa
commande de vérification. N1 (échecs silencieux), N2 (perception du livreur), N3 (hors code).
Le skill a aussi été corrigé : `driver/` **est** sous git, sur le remote **privé** `viteat_drive`.

### Pistes ouvertes — par impact

1. **Le parcours depuis le panel n'a jamais été exercé.** Le mécanisme de notification est prouvé ;
   cliquer « Assigner » dans le Restaurant Panel ne l'est pas. Bloqué par `DB_USERNAME`/`DB_PASSWORD`
   vides et la base `monsite2` absente. `migrate` ne suffira pas : il manque `users.isSubscribed` et
   la table `vendor_users`. Aucun compte à créer à la main (`AjaxController::setToken` les crée à la
   volée à la première connexion Firebase).
2. **8 livreurs internes sur 9 n'ont pas de `fcmToken`** — jamais connectés, ou déconnectés (le
   logout vide le champ, `dash_board_screen.dart:700`). Ils ne recevront rien.
3. **Réglages XOS à faire à la main** sur chaque téléphone : verrouillage dans les récents,
   démarrage automatique. Non scriptable (norme N3.1b).
4. **Le même travail reste à faire sur `customer`** : elle a les mêmes canaux par défaut absents et
   le même `updateUser` sans merge.
5. `BookTableController::sendnotification` est un copié-collé de l'ancien code, non corrigé
   (hors périmètre retenu) : le prochain incident dine-in reproduira le même silence.
6. **Disque saturé** : 238 Go dont 232 occupés. Un build de release a consommé les 12 Go restants et
   a saturé la machine. `flutter clean` sur `driver` + `customer` a rendu 9 Go. Troisième session
   d'affilée bloquée là-dessus — la correction durable appartient à l'utilisateur.

---

## Session 2026-08-29 (3) — la base de production était grande ouverte

Session d'investigation et de conception. **Aucune ligne de code applicatif modifiée** : le dépôt
`driver` est resté propre du début à la fin. Ce qui a changé, ce sont les réglages de la base
Firestore de production.

Point de départ : reprendre les trois chantiers ouverts (notifications — fait le 29/08 (2) ;
**preuve de livraison** ; **app qui repart de zéro**). L'utilisateur a choisi la preuve de livraison.

### 1. Ce que l'état du code disait vraiment

`DeliverOrderController.completedOrder()` (`driver/lib/controllers/deliver_order_controller.dart:37`)
écrit `Order Completed`, débite le wallet, verse le cashback et notifie le client — **sans aucune
vérification**. Le seul garde-fou est une **case à cocher que le livreur coche lui-même**
(`deliver_order_screen.dart:377`, « Give N Items to the customer »).

Aucun mécanisme d'OTP de livraison n'existe dans les deux apps : les `otp_screen` du livreur ne
servent qu'à la connexion par téléphone.

### 2. Un volet du travail supprimé : le cash est déjà couvert

Le risque « le livreur garde l'argent du COD » **n'est pas un trou dans le code**.
`FireStoreUtils.updateWallateAmount()` (`fire_store_utils.dart:645`) **débite** le wallet du livreur
du montant encaissé à la clôture : il devient débiteur envers la plateforme, et
`minimumDepositToRideAccept` l'empêche de reprendre des courses sous un seuil. S'il garde le cash,
il l'a déjà payé. Ce qui reste est un problème de **recouvrement d'un wallet négatif**, pas de code.

### 3. Découverte qui a fait dérailler le chantier — les règles Firestore

Les règles publiées sur `rapyogo-2bccd` sont **`allow read, write: if true`** sur `/{document=**}`.
Release `cloud.firestore` du **2025-05-29**, jamais refermée depuis. Le commentaire du template
(« non sécurisé - à utiliser uniquement en test ») est toujours dedans.

La clé API est dans l'APK et dans le JS des panels. **N'importe qui peut lire et écrire toute la
base** : coordonnées de tous les clients, wallets, payouts, `settings` des quatre apps, et le passage
d'une commande à `Order Completed`.

**Conséquence directe sur le chantier initial :** la preuve de livraison serait décorative. Le code
de remise serait lisible par le livreur dans le document de commande, et son app pourrait écrire
`Order Completed` sans passer par la vérification. Une Cloud Function de validation ne verrouille
rien tant que le chemin d'écriture directe reste ouvert.

### 4. Cartographie des accès (nécessaire à toute fermeture des règles)

| Client | Identité Firebase | Détail |
|---|---|---|
| App cliente | ✅ | rôle `customer` |
| App livreur | ✅ | rôle `driver` |
| Restaurant Panel | ⚠️ partielle | `signInWithEmailAndPassword` à la connexion (`auth/login.blade.php:355`) |
| Admin Panel | ❌ **aucune** | 161 vues écrivent en **anonyme** |

**210 vues Blade** parlent à Firestore depuis le navigateur (161 Admin, 49 Restaurant) — toutes
soumises aux règles. Fermer les règles sans donner d'identité à l'Admin Panel le casse intégralement.

Points d'injection trouvés, qui rendent le chantier réaliste **sans toucher les 210 vues** :

- L'init Firebase de l'Admin Panel est planquée dans **`public/js/jquery.validate.js` lignes 1-13**
  (un fichier portant le nom de la librairie jQuery Validate). La config arrive par des cookies
  `XSRF-TOKEN-*` posés dans `app/Providers/AppServiceProvider.php:19` via `bin2hex()` — de
  l'hexadécimal, pas du chiffrement. **Un canal Laravel → JS existe donc déjà**, et
  `firebase-auth-compat.js` est déjà chargé (`layouts/app.blade.php:300`).
- `kreait/firebase-php ^7.15` est présent dans les deux panels : il sait émettre des custom tokens
  porteurs d'un claim de rôle.

### 5. Sauvegardes activées sur la production (à la demande de l'utilisateur)

La base n'avait **aucune protection**. Créée le 17/06/2024, jamais reconfigurée.

| Réglage | Avant | Après |
|---|---|---|
| Sauvegarde planifiée | aucune | **quotidienne**, rétention 7 jours |
| Point-in-time recovery | 3600 s (1 h) | **604800 s (7 jours)**, à la minute près |
| Protection contre la suppression | désactivée | **activée** |

Vérifié par `firebase firestore:databases:get "(default)"`. Le ruleset d'origine est sauvegardé dans
`_backup_firestore_20260829/firestore.rules.original-20260829.txt` — **c'est le fichier dont dépend
tout retour arrière** sur les règles.

Un export hors ligne complet a abouti dans le même dossier : **9 797 documents, 47 collections**,
un JSON par collection plus un `_resume.json`. Les sous-collections ne sont pas incluses (voir
ci-dessous) — la sauvegarde Google, elle, est complète.
⚠️ **Erreur de ma part à ne pas reproduire** : un premier export a été tué par un `taskkill` alors
qu'il progressait normalement — sa sortie était bufferisée et je l'ai cru bloqué. Il écrivait tout à
la fin : **tout a été perdu**. La v2 écrit collection par collection au fil de l'eau.

### 6. Conception écrite, implémentation reportée

Spec complet : **`customer/docs/superpowers/specs/2026-08-29-securisation-regles-firestore-design.md`**
(non commité — il vit dans `customer`, dont les commits appartiennent à ses propres sessions).

Approche retenue et validée par l'utilisateur : **donner une identité Firebase aux panels, puis
refermer les règles en deux paliers** — palier 1 « il faut être connecté » (ferme l'accès anonyme,
ne casse rien), palier 2 règles par rôle sur les collections sensibles. Le catalogue public reste en
lecture large.

**Décision de l'utilisateur en fin de session : ce chantier passe en DERNIER.** Il sera repris après
les autres travaux. La conception est prête et n'a plus qu'à être relue puis planifiée.

**Deux inconnues à lever avant d'implémenter :**
1. Les administrateurs ont-ils un compte Firebase Auth ? Le custom token doit porter un `uid`.
2. Le Restaurant Panel tourne-t-il en production ailleurs ? Son `.env` porte `APP_ENV=local` /
   `APP_URL=http://localhost`. Si oui, tout le travail doit être fait sur ce serveur-là.

### Pistes ouvertes après cette session — par ordre décidé par l'utilisateur

1. **App qui repart de zéro** (jamais traitée). Suspects classiques déjà écartés
   (`always_finish_activities=0`, `launchMode=singleTop`). Restent : APK debug de 192 Mo qu'Android
   tue vite — **à retester en release** — et l'absence totale de `RestorationMixin`.
2. **Preuve de livraison** — conception commencée, à reprendre. Recommandation : code PIN à
   4 chiffres validé par Cloud Function, pas une signature (une signature au doigt prouve surtout
   qu'un doigt a touché l'écran). Le volet cash est inutile, voir §2. **Dépend du chantier règles**
   pour ne pas être décorative.
3. **Sécurisation des règles Firestore** — en dernier, sur décision de l'utilisateur. Spec prêt.
4. **Disque à 99 %** (3,4 Go libres) — **quatrième** session d'affilée bloquée là-dessus. Piste
   trouvée cette fois : un dossier temporaire oublié
   `Admin Panel/.petmpF2C3B8/Admin Panel - Restaurant Panel - Website Panel - Landing Panel/`
   contenant des copies complètes des quatre panels. Il pèse **297 Mo**, daté du 21/08 — utile
   à récupérer mais pas suffisant à lui seul. **Rien n’a été supprimé** — décision de l’utilisateur.

---

## Session 2026-08-29 → 31 — Viteat Driver OS, chantier 1A : noyau backend du programme livreur

### Ce qui existe maintenant, et qui n'existait pas

Un programme Partenaires Livreurs complet côté backend, **déployé sur `rapyogo-2bccd`** :
13 Cloud Functions, 12 collections Firestore neuves, 82 tests verts.

- **`Order Tracking Firebase Function/` est désormais un dépôt git** (branche `master`, 26 commits).
  Il n'en avait aucun. `serviceAccountKey.json` et `node_modules/` sont exclus.
- `functions/products/driver_program/` : `rules.js` (fonctions **pures**, aucune importation
  Firebase — c'est ce qui rend le métier testable sans émulateur), `store.js` (accès Firestore),
  `callables.js` (7 fonctions livreur), `admin_callables.js` (6 fonctions d'administration).
- `firestore.rules` : règles strictes sur les 12 collections `driver_*`. **Écrit, testé, NON déployé.**

Documents : `docs/superpowers/specs/2026-08-29-viteat-driver-os-audit.md` (audit + matrice des 73
sections du brief), `.../2026-08-29-portail-livreur-activation-design.md` (spec du chantier),
`docs/superpowers/plans/2026-08-29-portail-livreur-noyau-backend.md` (plan, 16 tâches).

### Les trois choses à savoir avant de toucher à ce chantier

**1. Le programme ne peut activer personne aujourd'hui.** Les 6 fonctions d'administration
exigent `request.auth.token.role === 'admin'`. **Personne ne porte ce claim** — l'Admin Panel n'a
aucune identité Firebase. Or la validation d'une pièce est le seul chemin qui pose `APPROVED`, et
la note de simulation le seul qui pose `certifiedAt`. Un candidat plafonne donc à
`DOSSIER_A_VERIFIER`. Le défaut est fermé (accès refusé, jamais accordé par erreur) mais c'est le
**premier problème à résoudre** du chantier suivant.

**2. Les règles Firestore ne sont pas déployées, et ce n'est plus un statu quo neutre.** Avant ce
chantier, écrire dans une collection `driver_*` n'avait aucune conséquence. Maintenant, tout
utilisateur authentifié peut forger ses documents « approuvés », sa certification et sa signature,
écrire `users.userBankDetails`, puis appeler `v1_updateProfile` (qui n'exige qu'une connexion) pour
déclencher `recomputeStatus` → `users.isActive = true`. Il reçoit alors de vraies courses.
Le fichier de règles corrige exactement cela et attend un feu vert.

**3. L'accord de partenariat en production porte un texte provisoire** — littéralement
« À REMPLACER par le texte juridique validé », `hash: 'v1-provisoire'`. À publier en `version: 2`
avant qu'un seul livreur soit invité à signer.

### Faits de terrain relevés, qui invalident des hypothèses courantes

- **383 comptes `role: "driver"` en base, dont 8 seulement `isActive`.** L'objectif de 30 livreurs
  est un objectif d'**activation**, pas un effectif. **341 comptes n'ont aucun `zoneId`** et ne
  peuvent structurellement recevoir aucune course, `deliveryDispatch` exigeant l'égalité des zones.
- **Les trois bases MySQL (`monsite1` site web, `monsite2` restaurant, `monsite3` admin) ne
  contiennent aucune donnée métier** — uniquement la plomberie Laravel, les comptes de connexion et
  les rôles. Tout le métier est dans Firestore.
- **Firestore évalue les règles en OU logique**, pas « la plus spécifique gagne ». Un joker
  `allow read, write: if true` rend décorative toute règle restrictive écrite à côté. Le joker de
  `firestore.rules` **exclut donc nommément** les 12 collections `driver_*` ; un test de
  synchronisation (`driver_program.wildcard_sync.test.js`) échoue si l'on ajoute une collection
  sans l'inscrire dans cette liste.
- **`documents_verify.documents[].documentId` contient les auto-ids Firestore réels** de la
  collection `documents` (`wNsq0pdDbbmjXkHKwtNv` = ID Proof, `tsTemfO52potrI6knLeO` = Driving
  License), et son `status` est une **chaîne minuscule**. Y écrire un nom symbolique ou un booléen
  casse l'app livreur. `rebuildMirror` fusionne pièce par pièce et ne remplace jamais le tableau.
- **firebase-tools 15.27 exige Java ≥ 21.** Java 17 ne suffit pas pour l'émulateur. Un JDK 21
  portable a servi pour cette session ; **installer un JDK 21+ durable** avant de relancer les tests.
- `node --test test/` **ne fonctionne pas** — le lanceur charge le dossier comme un module. La forme
  correcte est `node --test` sans argument.
- Le déploiement échoue parfois avec « An unexpected error has occurred » à l'étape de découverte.
  **C'est transitoire** : relancer suffit, aucun changement de code nécessaire.

### Ce qui reste ouvert

- Tâches 14 et 15 du plan reportées : vérification publique du QR, expiration planifiée des
  documents. Ni câblées ni déployées.
- Le catalogue `documents` est celui du template indien (`RC Book`, `FSSAI Certificate`), sans
  aucune date d'expiration configurée. À redéfinir pour la RDC — décision d'exploitation.
- La collection `zone` porte un doublon `Worldwide` / `World Wide`.
- Constats de la revue finale non traités : `submitDocument` ne reconstruit pas le miroir ; les
  pièces des 383 livreurs existants sont invisibles du programme et réciproquement ; aucun test de
  règles ne prouve que le livreur ne peut pas écrire `driver_documents` / `driver_training` /
  `driver_signatures` — les trois écritures qui, forgées, donnent l'activation.
- La reprise des 383 comptes devra allouer les identifiants **un par un** : Firestore plafonne les
  écritures soutenues sur un document unique à environ une par seconde, et le compteur en est un.

### Ordre décidé pour la suite

Admin Panel **avant** portail livreur : rien ne sert d'ouvrir la candidature tant que personne ne
peut valider un dossier. Le plan 1C devra commencer par des **fonctions callable de lecture** —
le chantier 1A n'a produit que des fonctions d'écriture pour l'administration.
