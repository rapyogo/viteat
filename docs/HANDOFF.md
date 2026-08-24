# HANDOFF — customer (app Flutter de livraison de repas)

Dernière mise à jour : 2026-08-24

## Contexte projet
- App Flutter cliente d'une plateforme de livraison de repas multi-vendeurs, marque "Rapyogo" (package Android `com.rapyogo.client`).
- Firebase project : **rapyogo-2bccd** (base Firestore par défaut, `currentEnv = FirebaseEnv.defaultDb` dans `lib/utils/fire_store_utils.dart`).
- Le repo fait partie d'un ensemble de projets sœurs dans `C:\Projet\AUTRE\Nouveau dossier\` : `Admin Panel`, `customer` (ce repo), `driver`, plus des dossiers d'outillage Firebase (`Firebase Indexing`, `Firebase Import Export Collections`, `Firestore Demo Authentication User Import`, `Order Tracking Firebase Function`) qui ne sont **pas** des dépôts git.
- Version app : 7.0.0+25 (pubspec.yaml).

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

## Pistes ouvertes / à traiter
- **Relancer le build Android** une fois le second VPN désactivé/corrigé, puis valider manuellement l'écran de paiement Mobile Money de bout en bout (vrai numéro, vraie confirmation push).
- Décider si `settings/flexpay_settings.enable` doit rester `true` (live) ou repasser à `false` en attendant la validation manuelle complète.
- Clarifier le sens des IPs FlexPay fournies (156.0.198.27/.19) et éventuellement ajouter une whitelist IP en plus du jeton sur `flexPayCallback`.
- Remplacer l'icône temporaire Mobile Money (actuellement `mtnmom.png` réutilisé) par un vrai logo.
- Revérifier le nom de package Android réellement actif (`com.rapyogo.customer.android` vs `com.rapyogo.client` — voir section 7).
- Investiguer le doublon potentiel `sendNewOrderNotification` vs `deliveryDispatch`.
- Corriger `NetworkImage("")` + overflow sur l'écran post-splash.
- `firebase.json` / `firebase_options.dart` (section iOS) référencent encore un projet obsolète `foodies-3c1d9` — config iOS jamais terminée (`YOUR_IOS_PROJECT_ID` en placeholder). Non bloquant pour Android.
- `npm audit fix` à envisager sur `Order Tracking Firebase Function/functions` (22 vulnérabilités, 1 critique).
