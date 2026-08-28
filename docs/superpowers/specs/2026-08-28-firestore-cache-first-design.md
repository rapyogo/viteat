# Lectures Firestore cache-first (stale-while-revalidate)

Date : 2026-08-28
Branche : `perf/firestore-cache-first`

## Probleme

L'app est plus rapide hors ligne qu'en ligne. La persistance Firestore est
active (`persistenceEnabled: true`, 100 Mo, `fire_store_utils.dart:96-99`)
mais **aucune lecture n'utilise `GetOptions`** : `grep -c "GetOptions" lib/` = 0.
Tous les `.get()` sont donc en `serverAndCache`, ou Firestore attend la reponse
du serveur avant de rendre la main, meme quand le cache contient deja la donnee.
Hors ligne, il sert le cache immediatement : d'ou l'inversion observee.

93 lectures `.get()` dans `lib/`, dont **89 dans le seul
`lib/utils/fire_store_utils.dart`**. Le point d'entree est unique.

## Ce qui n'est PAS le probleme

Deux hypotheses ecartees par l'exploration, a ne pas re-explorer :

- **La liste des restaurants proches.** `geoflutterfire` est vendu dans le repo
  (`lib/widget/geoflutterfire/`) et `src/collection/base.dart:188` fait
  `ref.snapshots()`. Les snapshots servent deja le cache avant le serveur.
  Ce chemin est deja cache-first.
- **`getSettings()` comme bloc sequentiel.** Ses 23 lectures ne sont pas
  enchainees : **4 `await`**, **9 `snapshots()`** (deja cache-first),
  **10 `.get().then()` lancees sans etre attendues**. La parallelisation n'y
  gagne presque rien.

Le vrai bloc sequentiel est **`getPaymentSettingsData()`
(`fire_store_utils.dart:508-633`) : 20 `await` strictement en serie**, chacun un
aller-retour serveur suivi d'une ecriture SharedPreferences elle aussi awaitee.
Appele a chaque ouverture du panier, du portefeuille et des cartes-cadeaux
(`cart_controller.dart:867`, `wallet_controller.dart:99`,
`gift_card_controller.dart:204`).

## Le piege qui contraint tout le design

`get(GetOptions(source: Source.cache))` se comporte differemment selon la cible :

- Sur une **requete** (`Query`), un cache vide ne leve pas d'erreur : elle rend
  un `QuerySnapshot` **vide**, indistinguable de « aucun resultat ».
  Servi tel quel, le premier lancement afficherait « aucun restaurant dans votre
  zone ».
- Sur un **document** (`DocumentReference`), un cache vide **leve une exception**
  qu'il faut attraper.

D'ou la regle, encapsulee une seule fois et jamais reecrite sur les 91 sites :

> **Resultat cache non vide -> on le rend et on revalide en arriere-plan.
> Resultat cache vide -> on attend le serveur.**

## Decisions

| Arbitrage | Decision |
|---|---|
| Donnees eligibles au cache | Catalogue + reglages. Jamais : commandes, portefeuille, statut de paiement, panier. |
| Forme du rafraichissement | Revalidation silencieuse : l'ecran s'affiche depuis le cache et se met a jour seul a l'arrivee du serveur. |
| Passerelles de paiement | **Parallelisation seule, pas de cache.** FlexPay est LIVE en production : jamais de cle ni de code marchand perime. |
| Migration | Signatures `Future<...>` preservees, `onRefresh` optionnel. Site par site, aucun appelant casse. |

## Architecture

Deux helpers prives dans `FireStoreUtils`.

### `_cacheThenServer<T>` — document unique

```dart
static Future<T?> _cacheThenServer<T>(
  DocumentReference<Map<String, dynamic>> ref,
  T? Function(DocumentSnapshot<Map<String, dynamic>>) apply, {
  void Function(T?)? onRefresh,
  String? tag,
})
```

Generique parce que les lectures de document ont **deux usages distincts** dans
ce fichier, et qu'un helper `void` ne couvrirait que le premier :

- **Effet de bord** — les reglages de `getSettings()` : `apply` ecrit dans
  `Constant` et rend `null`. C'est le rejeu du handler qui porte la mise a jour.
- **Valeur de retour** — `getVendorById`, `getProductById`,
  `getVendorCategoryById`, `getAdvertisementById`, `getDeliveryCharge` :
  `apply` rend un modele, que l'appelant recoit. La revalidation passe par
  `onRefresh`.

1. `ref.get(const GetOptions(source: Source.cache))` dans un `try/catch`.
   Si le document existe, `apply(snap)` immediatement.
2. Lecture serveur relancee **sans `await`**, qui rejoue `apply`.
3. Si le cache etait absent, la lecture serveur est **attendue**.

Le `Future` se resout des que la valeur est disponible, pas quand la
revalidation est finie. Les handlers n'etant que des affectations a `Constant`,
les rejouer est idempotent — c'est ce qui rend la double execution sure.

### `_cacheFirstQuery` — liste

```dart
static Future<List<T>> _cacheFirstQuery<T>(
  Query<Map<String, dynamic>> query,
  T Function(Map<String, dynamic>) fromJson, {
  void Function(List<T>)? onRefresh,
  String? tag,
})
```

1. Lecture cache. Si `docs.isNotEmpty` : mapper, **retourner**, puis revalider en
   arriere-plan et appeler `onRefresh` avec la liste serveur.
2. Si vide : attendre le serveur, retourner ce resultat. `onRefresh` **n'est pas
   appele** — la valeur rendue est deja fraiche.

Le parsing est isole par document (`try/catch` autour de chaque `fromJson`) :
un document corrompu cote admin ne doit pas vider la liste entiere. Le code
actuel le fait deja par endroits (`getVendors`), pas partout.

## Perimetre

### Passent en cache-first

**Reglages** (`getSettings`, via `_cacheThenServer`) : les 10 lectures
non attendues et les 4 `await`. Les 9 `snapshots()` restent inchanges.

**Catalogue, requetes** (`_cacheFirstQuery`) : `getOnBoardingList`,
`getVendors`, `getZone`, `getStory`, `getHomeCoupon`, `getHomeVendorCategory`,
`getVendorCategory`, `getHomeTopBanner`, `getHomeBottomBanner`,
`getProductByVendorId`, `getOfferByVendorId`, `getAttributes`, `getTaxList`,
`getAllVendorPublicCoupons`, `getAllVendorCoupons`, `getVendorCuisines`,
`getAllAdvertisement`.

**Catalogue, documents** (`_cacheThenServer<T>` avec valeur de retour) :
`getVendorById`, `getVendorCategoryById`, `getProductById`,
`getAdvertisementById`, `getDeliveryCharge`.

`getTaxList` garde sa garde de localisation en tete : sans coordonnees resolues
elle rend une liste vide sans lire Firestore, et cette sortie precede le cache.

### Parallelisation seule, sans cache

`getPaymentSettingsData` : les 20 `await` deviennent un `Future.wait`.
L'ordre n'a pas d'importance, chaque lecture ecrit sa propre cle Preferences.

### Non touche

Commandes (`getAllOrder`, `getOrderByOrderId`, `getDineInBooking`),
portefeuille (`getWalletTransaction`, `updateUserWallet`), profil
(`getUserProfile`, `getUserByEmail`), favoris, avis, cartes-cadeaux, chat,
parrainage, `isMaintenanceMode`, et les `snapshots()` existants.

## Gain fonctionnel attendu, au-dela de la vitesse

`getSettings()` rend la main **avant** que 10 de ses lectures soient revenues :
les ecrans peuvent lire des `Constant` encore nulles. C'est la cause racine du
crash `Constant.adminCommission!` traite en defensif le 2026-08-25. Servir depuis
le cache reduit cette fenetre de course a quelques millisecondes. Ce n'est pas
une correction — la garde defensive reste necessaire — mais le symptome devient
beaucoup plus rare.

## Anomalies relevees, hors perimetre sans accord explicite

- `DineinForRestaurant` est lu **deux fois** dans `getSettings()`
  (`fire_store_utils.dart:311` et `:412`), pour deux champs differents.
- `Constant.placeHolderImage` et `Constant.placeholderImage` coexistent — deux
  champs distincts a une majuscule pres, alimentes par deux documents Firestore
  differents (`googleMapKey.placeHolderImage` et `placeHolderImage.image`).
- Les `snapshots().listen()` de `getSettings()` ne sont jamais desabonnes.

## Validation

Pas de `fake_cloud_firestore` au projet, et il ne simule pas fidelement
`Source.cache` : l'ajouter donnerait un faux sentiment de securite. La validation
est manuelle, sur device reel, avec des logs chronometres temporaires retires
avant le merge.

1. `flutter analyze` — 0 erreur, ne pas depasser la baseline de 312 infos.
2. **Premier lancement, cache vide** (`flutter clean` + reinstallation) :
   comportement identique a aujourd'hui, aucune liste vide affichee a tort.
3. **Second lancement** : mesurer le delai splash -> accueil utilisable.
4. **Ouverture du panier** : mesurer avant/apres la parallelisation des 20
   lectures de reglages de paiement.
5. **Mode avion** : le catalogue s'affiche depuis le cache.
6. **Revalidation** : modifier une valeur depuis le panel admin, verifier
   qu'elle remonte dans l'app sans reinstallation.
