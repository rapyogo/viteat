# Lectures Firestore cache-first — Plan d'implementation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Servir le catalogue et les reglages depuis le cache Firestore local avant la reponse du serveur, pour que l'app cesse d'etre plus rapide hors ligne qu'en ligne.

**Architecture:** Deux helpers prives dans `FireStoreUtils` encapsulent la lecture cache-first et la revalidation en arriere-plan. Les 22 methodes de catalogue et les ~14 lectures de reglages deleguent a ces helpers en gardant leur signature `Future<...>` actuelle, avec un parametre `onRefresh` optionnel. En parallele, `getPaymentSettingsData()` passe de 20 lectures en serie a une salve `Future.wait`, sans cache.

**Tech Stack:** Flutter, Dart, `cloud_firestore` (persistance locale deja active, 100 Mo), GetX.

**Spec:** `docs/superpowers/specs/2026-08-28-firestore-cache-first-design.md`

## Global Constraints

- **Langue :** commentaires de code et messages de commit en francais, **sans accents** (le reste du fichier suit cette convention — voir les commentaires existants de `getTaxList`).
- **Signatures preservees :** aucune methode publique de `FireStoreUtils` ne change de type de retour. Les nouveaux parametres sont **optionnels et nommes**. Aucun appelant ne doit etre modifie pour continuer a compiler.
- **Jamais de cache sur :** commandes, portefeuille, profil utilisateur, favoris, avis, cartes-cadeaux, chat, parrainage, `isMaintenanceMode`, et **les reglages de passerelles de paiement** (`getPaymentSettingsData`). FlexPay est LIVE en production.
- **Les 9 `snapshots().listen()` de `getSettings()` ne sont pas touches** — ils sont deja cache-first nativement.
- **Baseline `flutter analyze` :** 0 erreur, 312 infos. Ne pas depasser.
- `dart:async` est deja importe dans `fire_store_utils.dart:1` — `unawaited` est disponible sans nouvel import.

## Note sur le cycle de verification (lire avant de commencer)

**Ce plan n'est pas en TDD, et c'est delibere.** Le projet n'a qu'un
`test/widget_test.dart` et aucune dependance de test Firestore. `fake_cloud_firestore`
ne simule pas fidelement `Source.cache` : un test ecrit contre lui passerait au vert
sans rien prouver du comportement reel, ce qui est pire que pas de test.

Le cycle de chaque tache est donc :

1. `flutter analyze lib/utils/fire_store_utils.dart` — 0 erreur.
2. Commit.

Et la verification fonctionnelle reelle est concentree dans la **Tache 8**, sur device
physique. Ne pas merger avant que la Tache 8 soit passee.

---

### Task 1: Les deux helpers

**Files:**
- Modify: `lib/utils/fire_store_utils.dart` (inserer apres `getCurrentUid()`, vers la ligne 104)

**Interfaces:**
- Consumes: rien (premiere tache)
- Produces:
  - `static Future<T?> _cacheThenServer<T>(DocumentReference<Map<String, dynamic>> ref, T? Function(DocumentSnapshot<Map<String, dynamic>>) apply, {void Function(T?)? onRefresh, String? tag})`
  - `static Future<List<T>> _cacheFirstQuery<T>(Query<Map<String, dynamic>> query, T Function(Map<String, dynamic>) fromJson, {void Function(List<T>)? onRefresh, bool Function(T)? where, String? tag})`

- [ ] **Step 1: Inserer les deux helpers**

Dans `lib/utils/fire_store_utils.dart`, juste apres la fermeture de `getCurrentUid()` :

```dart
  // ---------------------------------------------------------------------------
  // Lectures cache-first (stale-while-revalidate)
  //
  // La persistance Firestore est active (init(), plus haut) mais aucune lecture
  // n'utilisait GetOptions : toutes etaient en serverAndCache, donc en ligne
  // Firestore attendait le serveur avant de rendre la main meme quand le cache
  // contenait deja la donnee. D'ou une app plus rapide hors ligne qu'en ligne.
  //
  // Piege central : un cache vide ne se signale pas de la meme facon selon la
  // cible. Sur une Query il rend un snapshot VIDE, indistinguable de « aucun
  // resultat » ; sur un DocumentReference il LEVE. Les deux helpers ci-dessous
  // sont le seul endroit ou cette difference est traitee.
  // ---------------------------------------------------------------------------

  /// Lit un document depuis le cache local, puis revalide depuis le serveur.
  ///
  /// [apply] est rejoue a l'identique sur la reponse serveur. Les handlers de
  /// reglages n'ecrivent que dans `Constant`, donc le rejeu est idempotent —
  /// c'est ce qui rend la double execution sure.
  ///
  /// Le Future se resout des que la valeur est disponible (cache s'il est
  /// present, serveur sinon), pas quand la revalidation est terminee.
  static Future<T?> _cacheThenServer<T>(
    DocumentReference<Map<String, dynamic>> ref,
    T? Function(DocumentSnapshot<Map<String, dynamic>>) apply, {
    void Function(T?)? onRefresh,
    String? tag,
  }) async {
    Future<T?> fromServer() async {
      try {
        final DocumentSnapshot<Map<String, dynamic>> snapshot = await ref.get(const GetOptions(source: Source.server));
        if (!snapshot.exists) {
          return null;
        }
        return apply(snapshot);
      } catch (e) {
        log("_cacheThenServer server ${tag ?? ref.path} :: $e");
        return null;
      }
    }

    T? cached;
    bool servedFromCache = false;
    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await ref.get(const GetOptions(source: Source.cache));
      // Un document jamais lu leve ; un document lu puis supprime revient avec
      // exists == false. On ne sert que ce qui existe reellement.
      if (snapshot.exists) {
        cached = apply(snapshot);
        servedFromCache = true;
      }
    } catch (e) {
      // Cache vide pour ce document : normal au premier lancement.
      log("_cacheThenServer cache miss ${tag ?? ref.path} :: $e");
    }

    if (!servedFromCache) {
      return fromServer();
    }

    unawaited(fromServer().then((T? fresh) {
      if (onRefresh != null) {
        onRefresh(fresh);
      }
    }));

    return cached;
  }

  /// Lit une requete depuis le cache local, puis revalide depuis le serveur.
  ///
  /// Si le cache rend une liste vide, elle n'est jamais servie telle quelle :
  /// impossible de distinguer « rien en cache » de « aucun resultat », et la
  /// servir afficherait « aucun restaurant dans votre zone » au premier
  /// lancement. Dans ce cas on attend le serveur, et [onRefresh] n'est pas
  /// appele — la valeur rendue est deja fraiche.
  ///
  /// [where] filtre cote client apres parsing (certaines requetes ne peuvent
  /// pas exprimer leur filtre cote Firestore sans exclure les documents ou le
  /// champ est absent).
  static Future<List<T>> _cacheFirstQuery<T>(
    Query<Map<String, dynamic>> query,
    T Function(Map<String, dynamic>) fromJson, {
    void Function(List<T>)? onRefresh,
    bool Function(T)? where,
    String? tag,
  }) async {
    List<T> parse(QuerySnapshot<Map<String, dynamic>> snapshot) {
      final List<T> list = <T>[];
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snapshot.docs) {
        try {
          final T item = fromJson(doc.data());
          if (where == null || where(item)) {
            list.add(item);
          }
        } catch (e) {
          // Un document mal forme cote admin ne doit pas vider la liste entiere.
          log("_cacheFirstQuery parse ${tag ?? ''} ${doc.id} :: $e");
        }
      }
      return list;
    }

    Future<List<T>> fromServer() async {
      try {
        return parse(await query.get(const GetOptions(source: Source.server)));
      } catch (e) {
        log("_cacheFirstQuery server ${tag ?? ''} :: $e");
        return <T>[];
      }
    }

    List<T> cached = <T>[];
    try {
      cached = parse(await query.get(const GetOptions(source: Source.cache)));
    } catch (e) {
      log("_cacheFirstQuery cache ${tag ?? ''} :: $e");
    }

    if (cached.isEmpty) {
      return fromServer();
    }

    unawaited(fromServer().then((List<T> fresh) {
      // Une reponse serveur vide alors que le cache avait du contenu est
      // indistinguable d'une erreur reseau (fromServer rend [] dans les deux
      // cas) : on ne l'impose pas a l'ecran. Consequence assumee : une
      // collection entierement videe cote admin ne se propage qu'au prochain
      // lancement.
      if (fresh.isNotEmpty && onRefresh != null) {
        onRefresh(fresh);
      }
    }));

    return cached;
  }
```

- [ ] **Step 2: Verifier que ca compile**

Run: `flutter analyze lib/utils/fire_store_utils.dart`
Expected: 0 erreur. Des `info` sur les helpers non utilises sont normales a ce stade.

- [ ] **Step 3: Commit**

```bash
git add lib/utils/fire_store_utils.dart
git commit -m "Ajoute les deux helpers de lecture cache-first"
```

---

### Task 2: Paralleliser les reglages de paiement

**Files:**
- Modify: `lib/utils/fire_store_utils.dart:508-633` (`getPaymentSettingsData`)

**Interfaces:**
- Consumes: rien des taches precedentes (volontairement : **pas de cache ici**)
- Produces: `getPaymentSettingsData()` garde sa signature `static Future getPaymentSettingsData()`

**Contexte :** 20 `await` strictement en serie, chacun un aller-retour serveur suivi
d'une ecriture SharedPreferences elle aussi awaitee. Appele a chaque ouverture du
panier (`cart_controller.dart:867`), du portefeuille (`wallet_controller.dart:99`) et
des cartes-cadeaux (`gift_card_controller.dart:204`).

- [ ] **Step 1: Envelopper chaque lecture dans une fonction et les lancer ensemble**

Transformer le corps de `getPaymentSettingsData()` : chaque bloc
`await fireStore.collection(...).doc("X").get().then(...)` devient un element
d'une liste passee a `Future.wait`. La forme cible, pour les deux premiers
(appliquer le meme traitement mecanique aux 20) :

```dart
  static Future getPaymentSettingsData() async {
    // Ces 20 lectures etaient enchainees en serie : 20 allers-retours serveur
    // l'un apres l'autre a chaque ouverture du panier. Elles sont independantes
    // — chacune ecrit sa propre cle Preferences — donc l'ordre n'importe pas.
    //
    // Volontairement PAS cache-first, contrairement au reste des reglages : ce
    // sont les cles et codes marchands des passerelles de paiement, et FlexPay
    // est actif en production. On ne paie jamais avec une valeur perimee.
    await Future.wait(<Future<void>>[
      fireStore.collection(CollectionName.settings).doc("payFastSettings").get().then((value) async {
        if (value.exists) {
          PayFastModel payFastModel = PayFastModel.fromJson(value.data()!);
          await Preferences.setString(Preferences.payFastSettings, jsonEncode(payFastModel.toJson()));
        }
      }),
      fireStore.collection(CollectionName.settings).doc("MercadoPago").get().then((value) async {
        if (value.exists) {
          MercadoPagoModel mercadoPagoModel = MercadoPagoModel.fromJson(value.data()!);
          await Preferences.setString(Preferences.mercadoPago, jsonEncode(mercadoPagoModel.toJson()));
        }
      }),
      // ... les 18 autres, a l'identique : retirer le `await` de tete,
      // ajouter une virgule a la fin.
    ]);
  }
```

La transformation est purement mecanique et se fait en trois gestes par bloc :
retirer le `await` initial, garder le `.then(...)` tel quel, remplacer le `;`
final par une `,`.

- [ ] **Step 2: Verifier qu'aucune lecture n'a ete perdue**

Run: `sed -n '/static Future getPaymentSettingsData/,/^  }$/p' lib/utils/fire_store_utils.dart | grep -c 'fireStore.collection'`
Expected: `20` — le meme compte qu'avant la modification.

- [ ] **Step 3: Verifier que ca compile**

Run: `flutter analyze lib/utils/fire_store_utils.dart`
Expected: 0 erreur.

- [ ] **Step 4: Commit**

```bash
git add lib/utils/fire_store_utils.dart
git commit -m "Parallelise les 20 lectures de reglages de paiement"
```

---

### Task 3: Reglages generaux en cache-first

**Files:**
- Modify: `lib/utils/fire_store_utils.dart:261-438` (`getSettings`)

**Interfaces:**
- Consumes: `_cacheThenServer<T>` et `_cacheFirstQuery<T>` (Tache 1)
- Produces: `getSettings()` garde `static Future<void> getSettings()`

**Contexte :** la methode melange 3 styles — 9 `snapshots().listen()` (**a ne pas
toucher**, deja cache-first), 10 `.get().then()` lancees sans `await`, et 4 `await`.
Les 10 non attendues font que `getSettings()` rend la main avant que la moitie des
`Constant` soient renseignees : c'est la fenetre de course a l'origine du crash
`Constant.adminCommission!` du 2026-08-25.

- [ ] **Step 1: Convertir les lectures `.get()` de document en `_cacheThenServer`**

Chaque bloc `fireStore.collection(CollectionName.settings).doc("X").get().then((value) { ... })`
devient un appel a `_cacheThenServer` dont le `apply` contient le meme corps et
rend `null`. Exemple exact, pour `adminSettings` :

```dart
      // Avant :
      // fireStore.collection(CollectionName.settings).doc('adminSettings').get().then((value) {
      //   if (value.data() != null) {
      //     Constant.platformFeeModel = PlatformFeeModel.fromJson(value.data()!);
      //   }
      // }).catchError((e) { log("getSettings adminSettings error :: $e"); });

      _cacheThenServer<Object>(
        fireStore.collection(CollectionName.settings).doc('adminSettings'),
        (value) {
          if (value.data() != null) {
            Constant.platformFeeModel = PlatformFeeModel.fromJson(value.data()!);
          }
          return null;
        },
        tag: 'adminSettings',
      ),
```

Les documents concernes : `restaurant`, `globalSettings`, `DineinForRestaurant`
(x2 — voir Step 2), `cashbackOffer`, `DriverNearBy`, `story`, `adminSettings`,
`referral_amount`, `placeHolderImage`, `emailSetting`, `specialDiscountOffer`,
`AdminCommission`. La requete `currencies` est traitee au Step 3.

- [ ] **Step 2: Fusionner la double lecture de `DineinForRestaurant`**

Le document est lu deux fois (`:311` pour `isDineInEnable`, `:412` pour
`isEnabledForCustomer`). Une seule lecture, un seul `apply` :

```dart
      _cacheThenServer<Object>(
        fireStore.collection(CollectionName.settings).doc("DineinForRestaurant"),
        (value) {
          if (value.exists) {
            Constant.isDineInEnable = value.data()!["isEnabled"];
            Constant.isEnabledForCustomer = value.data()?['isEnabledForCustomer'] ?? false;
          }
          return null;
        },
        tag: 'DineinForRestaurant',
      ),
```

Note : l'ancien code ligne 412 faisait `value['isEnabledForCustomer']` sans garder
`exists` — il levait sur un document absent. La forme ci-dessus corrige ca au passage.

- [ ] **Step 3: Traiter la requete `currencies` avec l'autre helper**

C'est une requete, pas un document — elle passe par `_cacheFirstQuery` :

```dart
      final List<CurrencyModel> currencies = await _cacheFirstQuery<CurrencyModel>(
        FireStoreUtils.fireStore.collection(CollectionName.currencies).where("isActive", isEqualTo: true),
        CurrencyModel.fromJson,
        onRefresh: (List<CurrencyModel> fresh) {
          if (fresh.isNotEmpty) {
            Constant.currencyModel = fresh.first;
          }
        },
        tag: 'currencies',
      );
      Constant.currencyModel = currencies.isNotEmpty
          ? currencies.first
          : CurrencyModel(id: "", code: "USD", decimalDigits: 2, isActive: true, name: "US Dollar", symbol: "\$", symbolAtRight: false);
```

- [ ] **Step 4: Attendre les lectures ensemble**

Rassembler les appels `_cacheThenServer` dans un unique
`await Future.wait(<Future<Object?>>[ ... ]);`.

Note de typage : le parametre de type est `Object`, pas `void`. Avec `T = void`,
le helper rendrait `Future<void?>` — `void?` n'est pas un type Dart valide et le
fichier ne compilerait pas. Les `apply` de reglages rendent `null` ; leur valeur
de retour est simplement ignoree. Les `snapshots().listen()` restent en
dehors, inchanges. Ainsi `getSettings()` ne rend plus la main avant que ses
`Constant` soient renseignees — servies par le cache, cela coute quelques
millisecondes au lieu de plusieurs centaines.

- [ ] **Step 5: Verifier que les 9 snapshots sont intacts**

Run: `sed -n '/static Future<void> getSettings/,/^  }$/p' lib/utils/fire_store_utils.dart | grep -c 'snapshots()'`
Expected: `9`

- [ ] **Step 6: Verifier que ca compile**

Run: `flutter analyze lib/utils/fire_store_utils.dart`
Expected: 0 erreur.

- [ ] **Step 7: Commit**

```bash
git add lib/utils/fire_store_utils.dart
git commit -m "Sert les reglages generaux depuis le cache et fusionne la double lecture DineinForRestaurant"
```

---

### Task 4: Listes du catalogue d'accueil

**Files:**
- Modify: `lib/utils/fire_store_utils.dart` — `getOnBoardingList` (:223), `getVendors` (:236), `getZone` (:481), `getStory` (:753), `getHomeCoupon` (:766), `getHomeVendorCategory` (:785), `getVendorCategory` (:798), `getHomeTopBanner` (:811), `getHomeBottomBanner` (:824), `getAllAdvertisement` (:1517)

**Interfaces:**
- Consumes: `_cacheFirstQuery<T>` (Tache 1)
- Produces: chaque methode gagne un parametre optionnel `{void Function(List<X>)? onRefresh}` et garde son type de retour actuel.

- [ ] **Step 1: Migrer les 10 methodes**

Le corps de chacune se reduit a un appel au helper. Code exact :

```dart
  static Future<List<OnBoardingModel>> getOnBoardingList({void Function(List<OnBoardingModel>)? onRefresh}) async {
    return _cacheFirstQuery<OnBoardingModel>(
      fireStore.collection(CollectionName.onBoarding).where("type", isEqualTo: "customerApp"),
      OnBoardingModel.fromJson,
      onRefresh: onRefresh,
      tag: 'getOnBoardingList',
    );
  }

  static Future<List<VendorModel>> getVendors({void Function(List<VendorModel>)? onRefresh}) async {
    return _cacheFirstQuery<VendorModel>(
      fireStore.collection(CollectionName.vendors).where("zoneId", isEqualTo: Constant.selectedZone!.id.toString()),
      VendorModel.fromJson,
      onRefresh: onRefresh,
      tag: 'getVendors',
    );
  }

  static Future<List<ZoneModel>?> getZone({void Function(List<ZoneModel>)? onRefresh}) async {
    return _cacheFirstQuery<ZoneModel>(
      fireStore.collection(CollectionName.zone).where('publish', isEqualTo: true),
      ZoneModel.fromJson,
      onRefresh: onRefresh,
      tag: 'getZone',
    );
  }

  static Future<List<StoryModel>> getStory({void Function(List<StoryModel>)? onRefresh}) async {
    return _cacheFirstQuery<StoryModel>(
      fireStore.collection(CollectionName.story).limit(50),
      StoryModel.fromJson,
      onRefresh: onRefresh,
      tag: 'getStory',
    );
  }

  static Future<List<CouponModel>> getHomeCoupon({void Function(List<CouponModel>)? onRefresh}) async {
    return _cacheFirstQuery<CouponModel>(
      fireStore
          .collection(CollectionName.coupons)
          .where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now())
          .where("isEnabled", isEqualTo: true)
          .where("isPublic", isEqualTo: true),
      CouponModel.fromJson,
      onRefresh: onRefresh,
      tag: 'getHomeCoupon',
    );
  }

  static Future<List<VendorCategoryModel>> getHomeVendorCategory({void Function(List<VendorCategoryModel>)? onRefresh}) async {
    return _cacheFirstQuery<VendorCategoryModel>(
      fireStore.collection(CollectionName.vendorCategories).where("show_in_homepage", isEqualTo: true).where('publish', isEqualTo: true),
      VendorCategoryModel.fromJson,
      onRefresh: onRefresh,
      tag: 'getHomeVendorCategory',
    );
  }

  static Future<List<VendorCategoryModel>> getVendorCategory({void Function(List<VendorCategoryModel>)? onRefresh}) async {
    return _cacheFirstQuery<VendorCategoryModel>(
      fireStore.collection(CollectionName.vendorCategories).where('publish', isEqualTo: true),
      VendorCategoryModel.fromJson,
      onRefresh: onRefresh,
      tag: 'getVendorCategory',
    );
  }

  static Future<List<BannerModel>> getHomeTopBanner({void Function(List<BannerModel>)? onRefresh}) async {
    return _cacheFirstQuery<BannerModel>(
      fireStore.collection(CollectionName.menuItems).where("is_publish", isEqualTo: true).where("position", isEqualTo: "top").orderBy("set_order", descending: false),
      BannerModel.fromJson,
      onRefresh: onRefresh,
      tag: 'getHomeTopBanner',
    );
  }

  static Future<List<BannerModel>> getHomeBottomBanner({void Function(List<BannerModel>)? onRefresh}) async {
    return _cacheFirstQuery<BannerModel>(
      fireStore.collection(CollectionName.menuItems).where("is_publish", isEqualTo: true).where("position", isEqualTo: "middle").orderBy("set_order", descending: false),
      BannerModel.fromJson,
      onRefresh: onRefresh,
      tag: 'getHomeBottomBanner',
    );
  }
```

Pour `getAllAdvertisement` (:1517), lire d'abord le corps existant : il contient un
filtre ou un tri qui n'est pas visible dans cette liste. Conserver sa logique
post-requete telle quelle et ne remplacer que la partie lecture par
`_cacheFirstQuery`, en passant le filtre via le parametre `where:` s'il s'agit d'un
filtre client.

- [ ] **Step 2: Verifier que `getVendors` n'a pas perdu sa protection**

`getVendors` dereference `Constant.selectedZone!` — bang deja present avant cette
tache, connu et suivi comme dette (voir HANDOFF, section « selectedZone »). Ne pas
le corriger ici : c'est une passe dediee. Verifier seulement qu'il est toujours la
et que le comportement est inchange.

- [ ] **Step 3: Verifier que ca compile**

Run: `flutter analyze lib/utils/fire_store_utils.dart`
Expected: 0 erreur.

- [ ] **Step 4: Commit**

```bash
git add lib/utils/fire_store_utils.dart
git commit -m "Sert les listes du catalogue d'accueil depuis le cache"
```

---

### Task 5: Listes de la fiche restaurant

**Files:**
- Modify: `lib/utils/fire_store_utils.dart` — `getProductByVendorId` (:891), `getOfferByVendorId` (:955), `getAttributes` (:975), `getTaxList` (:1018), `getAllVendorPublicCoupons` (:1050), `getAllVendorCoupons` (:1071), `getVendorCuisines` (:1288)

**Interfaces:**
- Consumes: `_cacheFirstQuery<T>` (Tache 1)
- Produces: memes signatures, plus `{void Function(List<X>)? onRefresh}`

- [ ] **Step 1: Migrer `getProductByVendorId` en fusionnant ses deux branches**

Ses deux branches `if (selectedFoodType == "TakeAway")` / `else` executent
**exactement la meme requete** — la seule difference est le filtre client
`takeawayOption != true`. Le parametre `where:` du helper exprime ca directement :

```dart
  static Future<List<ProductModel>> getProductByVendorId(String vendorId, {void Function(List<ProductModel>)? onRefresh}) async {
    final String selectedFoodType = Preferences.getString(Preferences.foodDeliveryType, defaultValue: "Delivery");
    return _cacheFirstQuery<ProductModel>(
      fireStore.collection(CollectionName.vendorProducts).where("vendorID", isEqualTo: vendorId).where('publish', isEqualTo: true).orderBy("createdAt", descending: false),
      ProductModel.fromJson,
      // Le filtre reste cote client : `where("takeawayOption", isEqualTo: false)`
      // cote Firestore excluait les plats ou le champ est absent (bug corrige le
      // 2026-08-25). Ne pas le redeplacer cote serveur.
      where: selectedFoodType == "TakeAway" ? null : (ProductModel p) => p.takeawayOption != true,
      onRefresh: onRefresh,
      tag: 'getProductByVendorId',
    );
  }
```

- [ ] **Step 2: Migrer `getAttributes`**

```dart
  static Future<List<AttributesModel>?> getAttributes({void Function(List<AttributesModel>)? onRefresh}) async {
    return _cacheFirstQuery<AttributesModel>(
      fireStore.collection(CollectionName.vendorAttributes),
      AttributesModel.fromJson,
      onRefresh: onRefresh,
      tag: 'getAttributes',
    );
  }
```

- [ ] **Step 3: Migrer `getTaxList` en gardant sa garde de localisation**

La garde de tete et le geocodage restent **avant** la lecture, inchanges. Seule la
requete finale change :

```dart
  static Future<List<TaxModel>?> getTaxList({void Function(List<TaxModel>)? onRefresh}) async {
    try {
      final double? latitude = Constant.selectedLocation.location?.latitude;
      final double? longitude = Constant.selectedLocation.location?.longitude;
      // Localisation pas encore resolue (cold start hors-ligne, permission pas
      // encore accordee...) — pas de taxe applicable pour l'instant plutot que
      // de planter tout l'ecran d'accueil.
      if (latitude == null || longitude == null) {
        return <TaxModel>[];
      }
      final List<Placemark> placeMarks = await placemarkFromCoordinates(latitude, longitude);
      if (placeMarks.isEmpty) {
        return <TaxModel>[];
      }
      // Limite connue : placemarkFromCoordinates a besoin du reseau. Hors ligne
      // le pays reste inconnu et on sort ci-dessus — le cache-first ci-dessous
      // ne sert donc qu'en ligne, ou il evite quand meme l'aller-retour.
      return _cacheFirstQuery<TaxModel>(
        fireStore.collection(CollectionName.tax).where('country', isEqualTo: placeMarks.first.country).where('enable', isEqualTo: true),
        TaxModel.fromJson,
        onRefresh: onRefresh,
        tag: 'getTaxList',
      );
    } catch (e) {
      // Geocodage indisponible hors-ligne, ou toute autre erreur transitoire —
      // degrade proprement au lieu de faire planter HomeController.getData().
      log("getTaxList error :: $e");
      return <TaxModel>[];
    }
  }
```

- [ ] **Step 4: Migrer `getOfferByVendorId`, `getAllVendorPublicCoupons`, `getAllVendorCoupons`, `getVendorCuisines`**

Lire le corps actuel de chacune avant de la remplacer : elles ont des `where`
Firestore differents et `getVendorCuisines` fait un post-traitement (deduplication
des cuisines a partir des produits). Appliquer le meme patron que les precedentes :
la requete telle quelle en 1er argument, `X.fromJson` en 2e, `onRefresh:` et `tag:`.
Pour `getVendorCuisines`, garder le post-traitement **apres** l'appel au helper.

- [ ] **Step 5: Verifier que ca compile**

Run: `flutter analyze lib/utils/fire_store_utils.dart`
Expected: 0 erreur.

- [ ] **Step 6: Commit**

```bash
git add lib/utils/fire_store_utils.dart
git commit -m "Sert les listes de la fiche restaurant depuis le cache"
```

---

### Task 6: Documents du catalogue

**Files:**
- Modify: `lib/utils/fire_store_utils.dart` — `getVendorById` (:634), `getVendorCategoryById` (:925), `getProductById` (:940), `getDeliveryCharge` (:988), `getAdvertisementById` (:1540)

**Interfaces:**
- Consumes: `_cacheThenServer<T>` (Tache 1)
- Produces: memes signatures, plus `{void Function(X?)? onRefresh}`

- [ ] **Step 1: Migrer les 5 lectures de document**

Ce sont des documents uniques qui **rendent une valeur** — c'est l'usage generique
de `_cacheThenServer`, ou `apply` construit le modele au lieu d'ecrire dans
`Constant`. Code exact :

```dart
  static Future<VendorModel?> getVendorById(String vendorId, {void Function(VendorModel?)? onRefresh}) async {
    return _cacheThenServer<VendorModel>(
      fireStore.collection(CollectionName.vendors).doc(vendorId),
      (value) => value.exists ? VendorModel.fromJson(value.data()!) : null,
      onRefresh: onRefresh,
      tag: 'getVendorById',
    );
  }

  static Future<VendorCategoryModel?> getVendorCategoryById(String categoryId, {void Function(VendorCategoryModel?)? onRefresh}) async {
    return _cacheThenServer<VendorCategoryModel>(
      fireStore.collection(CollectionName.vendorCategories).doc(categoryId),
      (value) => value.exists ? VendorCategoryModel.fromJson(value.data()!) : null,
      onRefresh: onRefresh,
      tag: 'getVendorCategoryById',
    );
  }

  static Future<ProductModel?> getProductById(String productId, {void Function(ProductModel?)? onRefresh}) async {
    return _cacheThenServer<ProductModel>(
      fireStore.collection(CollectionName.vendorProducts).doc(productId),
      (value) => value.exists ? ProductModel.fromJson(value.data()!) : null,
      onRefresh: onRefresh,
      tag: 'getProductById',
    );
  }

  static Future<DeliveryCharge?> getDeliveryCharge({void Function(DeliveryCharge?)? onRefresh}) async {
    return _cacheThenServer<DeliveryCharge>(
      fireStore.collection(CollectionName.settings).doc("DeliveryCharge"),
      (value) => value.exists ? DeliveryCharge.fromJson(value.data()!) : null,
      onRefresh: onRefresh,
      tag: 'getDeliveryCharge',
    );
  }
```

Pour `getAdvertisementById` (:1540), noter que sa signature actuelle rend
`Future<AdvertisementModel>` **non nullable** : la conserver telle quelle en
fournissant le meme repli que le code existant, sinon tous ses appelants cassent.
Lire son corps avant de la modifier.

- [ ] **Step 2: Verifier que ca compile**

Run: `flutter analyze lib/utils/fire_store_utils.dart`
Expected: 0 erreur.

- [ ] **Step 3: Commit**

```bash
git add lib/utils/fire_store_utils.dart
git commit -m "Sert les documents du catalogue depuis le cache"
```

---

### Task 7: Brancher la revalidation sur l'ecran d'accueil

**Files:**
- Modify: `lib/controllers/home_controller.dart`

**Interfaces:**
- Consumes: les parametres `onRefresh` ajoutes aux Taches 4, 5 et 6
- Produces: rien de nouveau

**Contexte :** jusqu'ici la revalidation tourne mais son resultat est jete partout
ou `onRefresh` n'est pas fourni. `HomeController` possede deja les `RxList`
capables de l'absorber (`vendorCategoryModel`, `bannerModel`, `bannerBottomModel`,
`storyList`, `couponList`, `advertisementList`, declares
`home_controller.dart:36-47`) : une reaffectation suffit, l'UI est en `Obx`.

- [ ] **Step 1: Passer un `onRefresh` a chaque lecture de catalogue du controller**

Pour chaque appel du controller a une methode migree, ajouter le callback qui
reaffecte la `RxList` correspondante. Patron, sur `getVendorCategory` :

```dart
    final List<VendorCategoryModel> categories = await FireStoreUtils.getVendorCategory(
      onRefresh: (List<VendorCategoryModel> fresh) => vendorCategoryModel.value = fresh,
    );
    vendorCategoryModel.value = categories;
```

Appliquer le meme patron aux appels correspondant a `bannerModel`,
`bannerBottomModel`, `storyList`, `couponList` et `advertisementList`. Ne rien
brancher sur les listes issues de `getAllNearestRestaurant` : ce chemin passe par
`snapshots()` (`lib/widget/geoflutterfire/src/collection/base.dart:188`) et est
deja cache-first — y ajouter un `onRefresh` ferait doublon.

- [ ] **Step 2: Verifier que la revalidation ne relance pas de travail lourd**

`_listenForRestaurants()` trie et derive plusieurs listes a chaque emission. Si un
`onRefresh` alimente une liste consommee par ce tri, verifier que la reaffectation
ne redeclenche pas la chaine complete en boucle. Si c'est le cas, comparer
l'ancienne et la nouvelle liste avant d'affecter.

- [ ] **Step 3: Verifier que ca compile**

Run: `flutter analyze`
Expected: 0 erreur, au plus 312 infos.

- [ ] **Step 4: Commit**

```bash
git add lib/controllers/home_controller.dart
git commit -m "Applique les donnees revalidees sur l'ecran d'accueil"
```

---

### Task 8: Validation sur device reel

**Files:**
- Modify temporairement: `lib/utils/fire_store_utils.dart`, `lib/controllers/home_controller.dart`
- Aucun fichier livre par cette tache : les logs ajoutes sont **retires avant le commit final**.

**Interfaces:**
- Consumes: tout le travail des Taches 1 a 7
- Produces: la decision de merger ou non

- [ ] **Step 1: Ajouter des logs chronometres temporaires**

Autour de `getSettings()`, `getPaymentSettingsData()` et de `HomeController.getData()` :

```dart
    final Stopwatch sw = Stopwatch()..start();
    // ... l'appel mesure ...
    log("CHRONO getSettings :: ${sw.elapsedMilliseconds} ms");
```

- [ ] **Step 2: Premier lancement, cache vide — le scenario qui doit absolument passer**

```bash
adb uninstall com.rapyogo.customer.android
flutter run -d <device> --release
```

Attendu : comportement identique a aujourd'hui. **Aucune liste vide affichee a tort** —
en particulier pas de « aucun restaurant dans votre zone » ni de categorie de menu
vide. C'est le piege central du design : si ce scenario echoue, `_cacheFirstQuery`
sert un cache vide quelque part.

Note : verifier le nom de package reellement actif dans `android/app/build.gradle`
avant de lancer `adb uninstall` — le HANDOFF signale une ambiguite non resolue
entre `com.rapyogo.customer.android` et `com.rapyogo.client`.

- [ ] **Step 3: Second lancement — mesurer**

Relancer l'app sans desinstaller. Relever les trois CHRONO et les comparer au
premier lancement. Attendu : nette baisse sur `getSettings`.

- [ ] **Step 4: Ouvrir le panier — mesurer la parallelisation**

Ajouter un article, ouvrir le panier, relever `CHRONO getPaymentSettingsData`.
Attendu : de l'ordre d'un aller-retour au lieu de vingt. C'est le gain le plus
mesurable du plan, et il est independant du cache.

- [ ] **Step 5: Mode avion**

Activer le mode avion, relancer l'app. Attendu : le catalogue s'affiche depuis le
cache — restaurants, categories, bannieres. La localisation persiste (acquis de la
session du 2026-08-28).

- [ ] **Step 6: Verifier que la revalidation remonte bien**

Modifier une valeur visible depuis le panel admin (par exemple le nom d'une
categorie), puis rouvrir l'app **sans la reinstaller**. Attendu : l'ancienne valeur
s'affiche brievement puis est remplacee, ou la nouvelle valeur est deja la. Si elle
ne remonte jamais, `onRefresh` n'est pas branche sur ce chemin.

- [ ] **Step 7: Retirer les logs chronometres et verifier l'ensemble**

Run: `flutter analyze`
Expected: 0 erreur, au plus 312 infos.

Run: `grep -rn "CHRONO" lib/`
Expected: aucun resultat.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Retire les logs de mesure temporaires"
```

---

## Ce que ce plan ne fait pas

Signale dans le spec, volontairement hors perimetre — ne pas l'ajouter en cours de route :

- Les deux `Constant.placeHolderImage` / `Constant.placeholderImage` (deux champs a une majuscule pres, deux documents Firestore sources).
- Les `snapshots().listen()` de `getSettings()` jamais desabonnes.
- Le bang `!` sur `Constant.selectedZone`, present sur ~11 sites — passe dediee, deja au HANDOFF.
- La formule des frais de livraison.
