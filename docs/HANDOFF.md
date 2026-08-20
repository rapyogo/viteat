# HANDOFF — customer (app Flutter de livraison de repas)

Dernière mise à jour : 2026-08-21

## Contexte projet
- App Flutter cliente d'une plateforme de livraison de repas multi-vendeurs, marque "Rapyogo" (package Android `com.rapyogo.client`).
- Firebase project : **rapyogo-2bccd** (base Firestore par défaut, `currentEnv = FirebaseEnv.defaultDb` dans `lib/utils/fire_store_utils.dart`).
- Le repo fait partie d'un ensemble de projets sœurs dans `C:\Projet\AUTRE\Nouveau dossier\` : `Admin Panel`, `customer` (ce repo), `driver`, plus des dossiers d'outillage Firebase (`Firebase Indexing`, `Firebase Import Export Collections`, `Firestore Demo Authentication User Import`, `Order Tracking Firebase Function`) qui ne sont **pas** des dépôts git.
- Version app : 7.0.0+25 (pubspec.yaml).

## État git
- Dépôt initialisé cette session (n'existait pas avant). Branche `master`.
- **Aucun remote configuré** — l'utilisateur fournira l'URL GitHub plus tard (le remote par défaut de sa config globale, `rapyogo/rapycar`, ne correspond pas à ce projet).
- 2 commits : commit initial propre (491 fichiers, artefacts `.cxx` exclus, aucun secret), puis un commit de correctifs (voir ci-dessous).

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

## Pistes ouvertes / à traiter
- Configurer le remote git et pousser (`git push`) une fois l'URL GitHub fournie.
- Investiguer le doublon potentiel `sendNewOrderNotification` vs `deliveryDispatch`.
- Corriger `NetworkImage("")` + overflow sur l'écran post-splash.
- `firebase.json` / `firebase_options.dart` (section iOS) référencent encore un projet obsolète `foodies-3c1d9` — config iOS jamais terminée (`YOUR_IOS_PROJECT_ID` en placeholder). Non bloquant pour Android.
- `npm audit fix` à envisager sur `Order Tracking Firebase Function/functions` (22 vulnérabilités, 1 critique).
