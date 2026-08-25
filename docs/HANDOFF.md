# HANDOFF — customer (app Flutter de livraison de repas)

Dernière mise à jour : 2026-08-25

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

**Sécurité** : une vraie clé de compte de service Firebase (`firebase-adminsdk-qn3oh@rapyogo-2bccd`) a été collée directement dans le chat par l'utilisateur pour débloquer l'import, utilisée une fois, puis supprimée du disque. **Cette clé doit être révoquée et régénérée** depuis la console Firebase (Paramètres du projet → Comptes de service) — jamais fait à ce jour.

**Pistes ouvertes issues de cet import :**
- Vérifier le panel admin web : `globalSettings` (nom d'app, logo, contact, couleurs) affiche-t-il des valeurs génériques "Foodie" au lieu de "Rapyogo"/"Viteat" ? Si oui, les reconfigurer manuellement (pas de backup pour restaurer automatiquement).
- Nettoyer les 5 comptes `@gromart.com` restants (Auth + toute donnée Firestore associée à leurs UID) — confirmé "reliquat" par l'utilisateur mais nettoyage pas encore exécuté.
- Réessayer l'import des comptes de démo (`import-user.js`) seulement après avoir libéré/choisi d'autres UID (les 5 UID cibles du script sont pris par les comptes Gromart).
- **Révoquer la clé de compte de service exposée dans le chat** et en générer une nouvelle si besoin futur.
