# HANDOFF — customer (app Flutter de livraison de repas)

Dernière mise à jour : 2026-08-27

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
