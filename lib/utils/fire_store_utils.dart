import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart' hide Constant;
import 'package:customer/data/memo_cache.dart';
import 'package:customer/app/chat_screens/ChatVideoContainer.dart';
import 'package:customer/constant/collection_name.dart';
import 'package:customer/constant/constant.dart';
import 'package:customer/services/location_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:customer/constant/show_toast_dialog.dart';
import 'package:customer/controllers/gift_cards_model.dart';
import 'package:customer/firebase_options.dart';
import 'package:customer/models/AttributesModel.dart';
import 'package:customer/models/BannerModel.dart';
import 'package:customer/models/admin_commission.dart';
import 'package:customer/models/advertisement_model.dart';
import 'package:customer/models/cashbackModel.dart';
import 'package:customer/models/cashback_redeem_model.dart';
import 'package:customer/models/conversation_model.dart';
import 'package:customer/models/coupon_model.dart';
import 'package:customer/models/currency_model.dart';
import 'package:customer/models/dine_in_booking_model.dart';
import 'package:customer/models/favourite_item_model.dart';
import 'package:customer/models/favourite_model.dart';
import 'package:customer/models/free_delivery_model.dart';
import 'package:customer/models/gift_cards_order_model.dart';
import 'package:customer/models/inbox_model.dart';
import 'package:customer/models/notification_model.dart';
import 'package:customer/models/on_boarding_model.dart';
import 'package:customer/models/order_model.dart';
import 'package:customer/models/payment_model/cod_setting_model.dart';
import 'package:customer/models/payment_model/flexpay_model.dart';
import 'package:customer/models/payment_model/wallet_setting_model.dart';
import 'package:customer/models/platform_fee_model.dart';
import 'package:customer/models/product_model.dart';
import 'package:customer/models/rating_model.dart';
import 'package:customer/models/referral_model.dart';
import 'package:customer/models/review_attribute_model.dart';
import 'package:customer/models/story_model.dart';
import 'package:customer/models/tax_model.dart';
import 'package:customer/models/user_model.dart';
import 'package:customer/models/vendor_category_model.dart';
import 'package:customer/models/vendor_model.dart';
import 'package:customer/models/wallet_transaction_model.dart';
import 'package:customer/models/zone_model.dart';
import 'package:customer/themes/app_them_data.dart';
import 'package:customer/utils/notification_service.dart';
import 'package:customer/utils/preferences.dart';
import 'package:customer/widget/geoflutterfire/src/geoflutterfire.dart';
import 'package:customer/widget/geoflutterfire/src/models/point.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:video_compress/video_compress.dart';

enum FirebaseEnv { defaultDb, staging }

/// Change this to switch between default / staging
const FirebaseEnv currentEnv = FirebaseEnv.defaultDb;

class FireStoreUtils {
  FireStoreUtils._privateConstructor();

  static final FireStoreUtils instance = FireStoreUtils._privateConstructor();

  static late FirebaseFirestore fireStore;

  /// Initialize Firestore with a FirebaseApp and optional databaseId
  void init(FirebaseApp app, {String? databaseId}) {
    fireStore = FirebaseFirestore.instanceFor(app: app, databaseId: databaseId);
    fireStore.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: 100 * 1024 * 1024, // 100 Mo — app catalogue, pas illimité
    );
  }

  static String getCurrentUid() {
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  }

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

  static Future<bool> isLogin() async {
    if (FirebaseAuth.instance.currentUser == null) return false;
    // Ne pas passer par userExistOrNot() ici : celui-ci avale les erreurs réseau
    // et renvoie false, ce qui déconnecterait un utilisateur simplement hors-ligne
    // (pas de cache local) au démarrage. On laisse l'erreur remonter pour que
    // SplashController.redirectScreen() applique son fallback offline-aware.
    final DocumentSnapshot<Map<String, dynamic>> value = await fireStore.collection(CollectionName.users).doc(FirebaseAuth.instance.currentUser!.uid).get();
    if (!value.exists && value.metadata.isFromCache) {
      // Hors ligne, un document absent du cache revient avec exists == false
      // SANS lever : c'est indistinguable d'un compte reellement supprime. On ne
      // peut donc rien conclure, et la session Firebase Auth persistee localement
      // fait foi.
      //
      // Sans cette garde, rouvrir l'app hors ligne renvoyait au login alors que
      // la session etait intacte — et le repli hors-ligne de
      // SplashController.redirectScreen() ne s'armait jamais, puisqu'il vit dans
      // un catch et qu'aucune erreur n'etait levee.
      return true;
    }
    return value.exists;
  }

  /// Renvoie l'URL du store si la version installee est plus ancienne que
  /// `settings/Version.minCustomerBuildNumber`, sinon null. Ne bloque jamais
  /// sur une erreur : une lecture ratee laisse passer l'utilisateur.
  static Future<String?> requiredUpdateStoreUrl() async {
    try {
      final doc = await fireStore.collection(CollectionName.settings).doc('Version').get();
      final int minBuild = int.tryParse('${doc.data()?['minCustomerBuildNumber'] ?? ''}') ?? 0;
      if (minBuild <= 0) return null;
      final PackageInfo info = await PackageInfo.fromPlatform();
      final int currentBuild = int.tryParse(info.buildNumber) ?? 0;
      if (currentBuild >= minBuild) return null;
      final String url = '${doc.data()?['customerStoreUrl'] ?? ''}';
      return url.isNotEmpty ? url : 'https://play.google.com/store/apps/details?id=${info.packageName}';
    } catch (e) {
      log("requiredUpdateStoreUrl error :: $e");
      return null;
    }
  }

  static Future<bool> isMaintenanceMode() async {
    bool isMaintenance = false;
    try {
      await fireStore.collection(CollectionName.settings).doc('maintenance_mode_settings').get().then((value) async {
        isMaintenance = value.data()?['customerApp'] == true;
        log("isMaintenance :: $isMaintenance");
      });
    } catch (e) {
      log("isMaintenanceMode error :: $e");
      rethrow;
    }
    return isMaintenance;
  }

  static Future<bool> userExistOrNot(String uid) async {
    bool isExist = false;

    await fireStore.collection(CollectionName.users).doc(uid).get().then(
      (value) {
        if (value.exists) {
          isExist = true;
        } else {
          isExist = false;
        }
      },
    ).catchError((error) {
      log("Failed to check user exist: $error");
      isExist = false;
    });
    return isExist;
  }

  static Future<UserModel?> getUserProfile(String uuid) async {
    if (uuid.isEmpty) return null;
    UserModel? userModel;
    await fireStore.collection(CollectionName.users).doc(uuid).get().then((value) {
      if (value.exists) {
        userModel = UserModel.fromJson(value.data()!);
      }
    }).catchError((error) {
      log("Failed to update user: $error");
      debugPrint("getUserProfile($uuid) :: $error");
      userModel = null;
    });
    // Serveur injoignable (hors ligne, reseau lent) : le profil deja lu reste
    // dans le cache local de Firestore. Sans ce repli, une session valide
    // s'affichait comme un invite (pas de nom, pas de commandes).
    userModel ??= await getUserProfileFromCache(uuid);
    return userModel;
  }

  /// Enregistre le jeton FCM du telephone sur le profil, SEULEMENT s'il a
  /// change. Avant, le profil complet etait reecrit deux fois a chaque
  /// lancement (splash + GlobalSettingController), meme jeton identique.
  static Future<void> syncFcmToken(UserModel userModel) async {
    try {
      final String? token = await NotificationService.getToken();
      if (token == null || token.isEmpty || token == userModel.fcmToken || (userModel.id ?? '').isEmpty) return;
      await fireStore.collection(CollectionName.users).doc(userModel.id).update({'fcmToken': token});
      userModel.fcmToken = token;
      if (Constant.userModel?.id == userModel.id) Constant.userModel?.fcmToken = token;
    } catch (e) {
      debugPrint("syncFcmToken :: $e");
    }
  }

  /// Profil lu uniquement depuis le cache local de Firestore (aucun appel reseau).
  static Future<UserModel?> getUserProfileFromCache(String uuid) async {
    if (uuid.isEmpty) return null;
    try {
      final doc = await fireStore.collection(CollectionName.users).doc(uuid).get(const GetOptions(source: Source.cache));
      return doc.exists ? UserModel.fromJson(doc.data()!) : null;
    } catch (e) {
      debugPrint("getUserProfileFromCache :: $e");
      return null;
    }
  }

  static Future<UserModel?> getUserByEmail(String email) async {
    UserModel? userModel;
    try {
      QuerySnapshot snapshot = await fireStore.collection(CollectionName.users).where('email', isEqualTo: email).limit(1).get();

      if (snapshot.docs.isNotEmpty) {
        userModel = UserModel.fromJson(snapshot.docs.first.data() as Map<String, dynamic>);
      } else {
        userModel = null; // No user found
      }
    } catch (error) {
      log("Failed to get user by email: $error");
      userModel = null;
    }

    return userModel;
  }

  static Future<UserModel?> getUserByEmailRole(String email) async {
    UserModel? userModel;
    try {
      QuerySnapshot snapshot = await fireStore.collection(CollectionName.users).where('role', isEqualTo: Constant.userRoleCustomer).where('email', isEqualTo: email).limit(1).get();

      if (snapshot.docs.isNotEmpty) {
        userModel = UserModel.fromJson(snapshot.docs.first.data() as Map<String, dynamic>);
      } else {
        userModel = null; // No user found
      }
    } catch (error) {
      log("Failed to get user by email: $error");
      userModel = null;
    }

    return userModel;
  }

  /// Mise à jour du profil de l'utilisateur courant : `update()` des seuls
  /// champs de profil (les champs serveur role, vendorID, active,
  /// employeePermissionId, wallet_amount, isDocumentVerify ne sont jamais
  /// envoyés — règle `users` stricte).
  static Future<bool> updateUser(UserModel userModel) async {
    try {
      await fireStore.collection(CollectionName.users).doc(userModel.id).update(userModel.toProfileJson());
      Constant.userModel = userModel;
      return true;
    } catch (error) {
      log("Failed to update user: $error");
      return false;
    }
  }

  /// Création du document `users` d'un nouveau client (role customer,
  /// active true, sans champ serveur).
  static Future<bool> createUser(UserModel userModel) async {
    try {
      userModel.role = Constant.userRoleCustomer;
      userModel.active = true;
      await fireStore.collection(CollectionName.users).doc(userModel.id).set(userModel.toCreateJson());
      Constant.userModel = userModel;
      return true;
    } catch (error) {
      log("Failed to create user: $error");
      return false;
    }
  }

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

  static Future<void> getSettings() async {
    try {
      // --- Flux temps reel ---------------------------------------------------
      // Inchanges : snapshots() sert deja le cache avant le serveur.
      fireStore.collection(CollectionName.settings).doc("localisationSettings").snapshots().listen((event) async {
        if (event.exists) {
          Constant.apiKeyOfDeepl = event.data()?["apiKeyOfDeepl"] ?? '';
          Constant.localisationType = event.data()?["localisationType"] ?? '';
        }
      });

      fireStore.collection(CollectionName.settings).doc("RestaurantNearBy").snapshots().listen((event) {
        if (event.exists) {
          Constant.radius = event.data()!["radios"];
          Constant.driverRadios = event.data()!["driverRadios"];
          Constant.distanceType = event.data()!["distanceType"];
        }
      });

      fireStore.collection(CollectionName.settings).doc("googleMapKey").snapshots().listen((event) {
        if (event.exists) {
          Constant.mapAPIKey = event.data()!["key"];
          Constant.placeHolderImage = event.data()!["placeHolderImage"];
        }
      });

      fireStore.collection(CollectionName.settings).doc("home_page_theme").snapshots().listen((event) {
        if (event.exists) {
          Constant.theme = event.data()!["theme"];
        }
      });

      fireStore.collection(CollectionName.settings).doc("privacyPolicy").snapshots().listen((event) {
        if (event.exists) {
          Constant.privacyPolicy = event.data()!["privacy_policy"];
        }
      });

      fireStore.collection(CollectionName.settings).doc("termsAndConditions").snapshots().listen((event) {
        if (event.exists) {
          Constant.termsAndConditions = event.data()!["termsAndConditions"];
        }
      });

      fireStore.collection(CollectionName.settings).doc("walletSettings").snapshots().listen((event) {
        if (event.exists) {
          Constant.walletSetting = event.data()!["isEnabled"];
        }
      });

      fireStore.collection(CollectionName.settings).doc("Version").snapshots().listen((event) {
        if (event.exists) {
          Constant.googlePlayLink = event.data()!["googlePlayLink"] ?? '';
          Constant.appStoreLink = event.data()!["appStoreLink"] ?? '';
          Constant.appVersion = event.data()!["app_version"] ?? '';
          Constant.websiteUrl = event.data()!["websiteUrl"] ?? '';
        }
      });

      // Les notifications push sont envoyées par le serveur (v1_sendPush) :
      // plus de lecture de la clé de compte de service (serviceJson).

      // --- Devise : une requete, pas un document ------------------------------
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

      // --- Reglages : servis par le cache, revalides en arriere-plan ----------
      // Ces lectures etaient lancees sans etre attendues : getSettings() rendait
      // la main avant que la moitie des Constant soient renseignees, et les
      // ecrans pouvaient en lire de nulles (a l'origine du crash adminCommission
      // du 2026-08-25). Servies par le cache, les attendre coute quelques
      // millisecondes au lieu de plusieurs centaines.
      //
      // Le parametre de type est Object, pas void : avec T = void le helper
      // rendrait Future<void?>, qui n'est pas un type Dart valide. Les apply
      // rendent null, leur valeur de retour est ignoree.
      await Future.wait(<Future<Object?>>[
        _cacheThenServer<Object>(
          fireStore.collection(CollectionName.settings).doc('restaurant'),
          (value) {
            Constant.isSubscriptionModelApplied = value.data()!['subscription_model'];
            Constant.packagingChargeEnable = value.data()!['packagingChargeEnable'];
            return null;
          },
          tag: 'restaurant',
        ),
        _cacheThenServer<Object>(
          fireStore.collection(CollectionName.settings).doc("globalSettings"),
          (value) {
            Constant.defaultCountryCode = value.data()?["defaultCountryCode"] ?? '';
            Constant.isEnableAdsFeature = value.data()?['isEnableAdsFeature'] ?? false;
            Constant.isSelfDeliveryFeature = value.data()?['isSelfDelivery'] ?? false;
            Constant.taxScope = value.data()?['taxScope'] ?? "";
            // Isole le parsing de couleur : une valeur absente/mal formee cote
            // admin (ex. champ vide, pas de "#") ne doit pas faire planter cette
            // lecture et bloquer avec elle tous les autres reglages qui suivent
            // dans getSettings() (ils partageaient le meme try/catch englobant).
            final String? customerColorHex = value.data()?['app_customer_color'];
            if (customerColorHex != null && customerColorHex.isNotEmpty) {
              try {
                AppThemeData.primary300 = Color(int.parse(customerColorHex.replaceFirst("#", "0xff")));
              } catch (e) {
                log("getSettings app_customer_color invalide ($customerColorHex) :: $e");
              }
            }
            return null;
          },
          tag: 'globalSettings',
        ),
        // Le document etait lu deux fois, pour deux champs. Une seule lecture
        // desormais. L'ancienne seconde lecture faisait value['isEnabledForCustomer']
        // sans garder exists : elle levait sur un document absent.
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
        _cacheThenServer<Object>(
          fireStore.collection(CollectionName.settings).doc("cashbackOffer"),
          (event) {
            if (event.exists) {
              Constant.isCashbackActive = event.data()?["isEnable"] ?? false;
            }
            return null;
          },
          tag: 'cashbackOffer',
        ),
        _cacheThenServer<Object>(
          fireStore.collection(CollectionName.settings).doc("DriverNearBy"),
          (event) {
            if (event.exists) {
              Constant.selectedMapType = event.data()!["selectedMapType"];
              Constant.mapType = event.data()!["mapType"];
            }
            return null;
          },
          tag: 'DriverNearBy',
        ),
        _cacheThenServer<Object>(
          fireStore.collection(CollectionName.settings).doc('story'),
          (value) {
            Constant.storyEnable = value.data()?['isEnabled'] ?? false;
            return null;
          },
          tag: 'story',
        ),
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
        _cacheThenServer<Object>(
          fireStore.collection(CollectionName.settings).doc('referral_amount'),
          (value) {
            Constant.referralAmount = '${value.data()?['referralAmount'] ?? '0.0'}';
            return null;
          },
          tag: 'referral_amount',
        ),
        _cacheThenServer<Object>(
          fireStore.collection(CollectionName.settings).doc('placeHolderImage'),
          (value) {
            Constant.placeholderImage = value.data()?['image'] ?? '';
            return null;
          },
          tag: 'placeHolderImage',
        ),
        // E-mails transactionnels envoyés par le serveur (email_outbox) :
        // l'app ne lit plus settings/emailSetting (identifiants SMTP).
        _cacheThenServer<Object>(
          fireStore.collection(CollectionName.settings).doc("specialDiscountOffer"),
          (value) {
            if (value.exists) {
              Constant.specialDiscountOffer = value.data()?["isEnable"] ?? false;
            }
            return null;
          },
          tag: 'specialDiscountOffer',
        ),
        _cacheThenServer<Object>(
          fireStore.collection(CollectionName.settings).doc("AdminCommission"),
          (value) {
            if (value.data() != null) {
              Constant.adminCommission = AdminCommission.fromJson(value.data()!);
            }
            return null;
          },
          tag: 'AdminCommission',
        ),
      ]);
    } catch (e) {
      log(e.toString());
    }
  }

  static Future<bool?> checkReferralCodeValidOrNot(String referralCode) async {
    bool? isExit;
    try {
      await fireStore.collection(CollectionName.referral).where("referralCode", isEqualTo: referralCode).get().then((value) {
        if (value.size > 0) {
          isExit = true;
        } else {
          isExit = false;
        }
      });
    } catch (e, s) {
      print('FireStoreUtils.firebaseCreateNewUser $e $s');
      return false;
    }
    return isExit;
  }

  static Future<ReferralModel?> getReferralUserByCode(String referralCode) async {
    ReferralModel? referralModel;
    try {
      await fireStore.collection(CollectionName.referral).where("referralCode", isEqualTo: referralCode).get().then((value) {
        if (value.docs.isNotEmpty) {
          referralModel = ReferralModel.fromJson(value.docs.first.data());
        }
      });
    } catch (e, s) {
      log('FireStoreUtils.firebaseCreateNewUser $e $s');
      return null;
    }
    return referralModel;
  }

  static Future<String?> referralAdd(ReferralModel ratingModel) async {
    try {
      await fireStore.collection(CollectionName.referral).doc(ratingModel.id).set(ratingModel.toJson());
    } catch (e, s) {
      log('FireStoreUtils.firebaseCreateNewUser $e $s');
      return null;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Cache memoire (lot 2) : catalogue partage entre les ecrans, voir MemoCache.
  // Durees courtes pour ce qui bouge (menus, vendeurs), longues pour ce que
  // l'admin modifie rarement (zones, categories, attributs).
  // ---------------------------------------------------------------------------
  static final MemoCache<String, List<ZoneModel>> _zoneMemo = MemoCache<String, List<ZoneModel>>(const Duration(minutes: 10));
  static final MemoCache<String, List<VendorCategoryModel>> _categoryListMemo = MemoCache<String, List<VendorCategoryModel>>(const Duration(minutes: 10));
  static final MemoCache<String, VendorCategoryModel?> _categoryMemo = MemoCache<String, VendorCategoryModel?>(const Duration(minutes: 30));
  static final MemoCache<String, List<AttributesModel>> _attributesMemo = MemoCache<String, List<AttributesModel>>(const Duration(minutes: 30));
  static final MemoCache<String, List<ProductModel>> _menuMemo = MemoCache<String, List<ProductModel>>(const Duration(minutes: 2), maxEntries: 40);
  static final MemoCache<String, VendorModel?> _vendorMemo = MemoCache<String, VendorModel?>(const Duration(minutes: 2), maxEntries: 500);

  static Future<List<ZoneModel>?> getZone({void Function(List<ZoneModel>)? onRefresh}) async {
    return _zoneMemo.get(
      'zones',
      (onFresh) => _cacheFirstQuery<ZoneModel>(
        fireStore.collection(CollectionName.zone).where('publish', isEqualTo: true),
        ZoneModel.fromJson,
        onRefresh: onFresh,
        tag: 'getZone',
      ),
      onRefresh: onRefresh,
    );
  }

  static Future<List<WalletTransactionModel>?> getWalletTransaction() async {
    List<WalletTransactionModel> walletTransactionList = [];
    log("FireStoreUtils.getCurrentUid() :: ${FireStoreUtils.getCurrentUid()}");
    await fireStore.collection(CollectionName.wallet).where('user_id', isEqualTo: FireStoreUtils.getCurrentUid()).orderBy('date', descending: true).get().then((value) {
      for (var element in value.docs) {
        WalletTransactionModel walletTransactionModel = WalletTransactionModel.fromJson(element.data());
        walletTransactionList.add(walletTransactionModel);
      }
    }).catchError((error) {
      log(error.toString());
    });
    return walletTransactionList;
  }

  /// Réglages de paiement lus par l'app : uniquement les moyens vérifiés par
  /// le serveur (wallet, paiement à la livraison, FlexPay). Les documents des
  /// autres passerelles (Stripe, PayPal, Razorpay…) contenaient des secrets :
  /// ils ne sont plus lus, et le cache local éventuel est écrasé par '{}'
  /// (modèle vide => passerelle désactivée, jsonDecode reste valide).
  static Future getPaymentSettingsData() async {
    for (final String key in [
      Preferences.payFastSettings,
      Preferences.mercadoPago,
      Preferences.paypalSettings,
      Preferences.stripeSettings,
      Preferences.flutterWave,
      Preferences.payStack,
      Preferences.paytmSettings,
      Preferences.razorpaySettings,
      Preferences.midTransSettings,
      Preferences.orangeMoneySettings,
      Preferences.xenditSettings,
      Preferences.mtnMomoSettings,
      Preferences.phonePaySettings,
      Preferences.foloosiSettings,
      Preferences.cashFreeSettings,
      Preferences.payMongoSettings,
      Preferences.instamojoSettings,
    ]) {
      await Preferences.setString(key, '{}');
    }
    // Les trois lectures restantes sont independantes (chacune ecrit sa cle) :
    // en parallele plutot qu'en serie. Volontairement pas cache-first : FlexPay
    // est actif en production, on ne paie jamais avec une valeur perimee.
    await Future.wait(<Future<void>>[
      fireStore.collection(CollectionName.settings).doc("walletSettings").get().then((value) async {
        if (value.exists) {
          WalletSettingModel walletSettingModel = WalletSettingModel.fromJson(value.data()!);
          await Preferences.setString(Preferences.walletSettings, jsonEncode(walletSettingModel.toJson()));
        }
      }),
      fireStore.collection(CollectionName.settings).doc("CODSettings").get().then((value) async {
        if (value.exists) {
          CodSettingModel codSettingModel = CodSettingModel.fromJson(value.data()!);
          await Preferences.setString(Preferences.codSettings, jsonEncode(codSettingModel.toJson()));
        }
      }),
      fireStore.collection(CollectionName.settings).doc("flexpay_settings").get().then((value) async {
        if (value.exists) {
          FlexPay flexPay = FlexPay.fromJson(value.data()!);
          await Preferences.setString(Preferences.flexPaySettings, jsonEncode(flexPay.toJson()));
        }
      }),
    ]);
  }

  static Future<VendorModel?> getVendorById(String vendorId, {void Function(VendorModel?)? onRefresh}) async {
    return _cacheThenServer<VendorModel>(
      fireStore.collection(CollectionName.vendors).doc(vendorId),
      (value) => value.exists ? VendorModel.fromJson(value.data()!) : null,
      onRefresh: onRefresh,
      tag: 'getVendorById',
    );
  }

  /// getVendorById pour l'AFFICHAGE (accueil, stories, favoris, liste des
  /// commandes) : servi par la memoire si le vendeur est connu depuis moins de
  /// 2 min (le flux des restaurants proches l'y depose), sinon lu une seule
  /// fois meme demande en parallele. Le panier et le parcours de commande
  /// gardent getVendorById, toujours relu.
  static Future<VendorModel?> getVendorByIdCached(String vendorId) {
    if (vendorId.isEmpty) return Future<VendorModel?>.value(null);
    return _vendorMemo.get(vendorId, (onFresh) => getVendorById(vendorId, onRefresh: onFresh));
  }

  /// Le flux des restaurants proches depose ici les vendeurs qu'il recoit.
  static void rememberVendor(VendorModel vendor) => _vendorMemo.put(vendor.id ?? '', vendor);

  static Stream<List<VendorModel>> getAllNearestRestaurant({bool? isDining}) async* {
    // Sans localisation resolue, le centre geographique retombait sur (0,0) —
    // au large de l'Afrique — et la requete ramenait donc systematiquement une
    // liste vide, en donnant l'impression que la zone n'etait pas couverte.
    // On sort explicitement : aux ecrans d'inviter a definir une localisation.
    if (!LocationService.isResolved || Constant.selectedZone == null) {
      debugPrint("VENDORS: pas de requete (localisation=${LocationService.isResolved}, zone=${Constant.selectedZone?.id})");
      yield <VendorModel>[];
      return;
    }
    debugPrint("VENDORS: requete zone=${Constant.selectedZone?.id} centre=${LocationService.latitude},${LocationService.longitude} rayon=${Constant.radius}");
    try {
      Query<Map<String, dynamic>> query = isDining == true
          ? fireStore.collection(CollectionName.vendors).where('zoneId', isEqualTo: Constant.selectedZone?.id.toString()).where("enabledDiveInFuture", isEqualTo: true)
          : fireStore.collection(CollectionName.vendors).where('zoneId', isEqualTo: Constant.selectedZone?.id.toString());

      GeoFirePoint center = Geoflutterfire().point(latitude: LocationService.latitude!, longitude: LocationService.longitude!);
      String field = 'g';

      Stream<List<DocumentSnapshot>> stream = Geoflutterfire().collection(collectionRef: query).within(center: center, radius: double.parse(Constant.radius), field: field, strictMode: true);

      // Flux transforme directement (plus de StreamController statique ni de
      // listen interne) : quand l'ecran annule son abonnement, l'annulation
      // remonte jusqu'aux requetes Firestore. Avant, chaque ouverture d'ecran
      // laissait des ecouteurs actifs sur `vendors` (lectures facturees).
      yield* stream.map((List<DocumentSnapshot> documentList) {
        final List<VendorModel> vendorList = [];
        for (var document in documentList) {
          final data = document.data() as Map<String, dynamic>;
          VendorModel vendorModel = VendorModel.fromJson(data);
          if (!Constant.isVendorLive(vendorModel)) continue; // restaurant hors ligne
          if ((Constant.isSubscriptionModelApplied == true || Constant.adminCommission?.isEnabled == true) && vendorModel.subscriptionPlan != null) {
            if (vendorModel.subscriptionTotalOrders == "-1") {
              vendorList.add(vendorModel);
            } else {
              if ((vendorModel.subscriptionExpiryDate != null && vendorModel.subscriptionExpiryDate!.toDate().isBefore(DateTime.now()) == false) || vendorModel.subscriptionPlan?.expiryDay == "-1") {
                vendorList.add(vendorModel);
              }
            }
          } else {
            vendorList.add(vendorModel);
          }
        }
        debugPrint("VENDORS: ${documentList.length} documents recus, ${vendorList.length} retenus");
        return vendorList;
      }).handleError((Object e) {
        debugPrint("VENDORS: erreur du flux :: $e");
      });
    } catch (e) {
      print(e);
    }
  }

  static Stream<List<VendorModel>> getAllNearestRestaurantByCategoryId({bool? isDining, required String categoryId}) async* {
    // Sans localisation resolue, le centre geographique retombait sur (0,0) —
    // au large de l'Afrique — et la requete ramenait donc systematiquement une
    // liste vide, en donnant l'impression que la zone n'etait pas couverte.
    // On sort explicitement : aux ecrans d'inviter a definir une localisation.
    if (!LocationService.isResolved || Constant.selectedZone == null) {
      yield <VendorModel>[];
      return;
    }
    try {
      Query<Map<String, dynamic>> query = isDining == true
          ? fireStore
              .collection(CollectionName.vendors)
              .where('zoneId', isEqualTo: Constant.selectedZone!.id.toString())
              .where('categoryID', arrayContains: categoryId)
              .where("enabledDiveInFuture", isEqualTo: true)
          : fireStore.collection(CollectionName.vendors).where('zoneId', isEqualTo: Constant.selectedZone!.id.toString()).where('categoryID', arrayContains: categoryId);

      GeoFirePoint center = Geoflutterfire().point(latitude: LocationService.latitude!, longitude: LocationService.longitude!);
      String field = 'g';

      Stream<List<DocumentSnapshot>> stream = Geoflutterfire().collection(collectionRef: query).within(center: center, radius: double.parse(Constant.radius), field: field, strictMode: true);

      // Meme correctif que getAllNearestRestaurant : annulation propagee.
      yield* stream.map((List<DocumentSnapshot> documentList) {
        final List<VendorModel> vendorList = [];
        for (var document in documentList) {
          final data = document.data() as Map<String, dynamic>;
          VendorModel vendorModel = VendorModel.fromJson(data);
          if (!Constant.isVendorLive(vendorModel)) continue; // restaurant hors ligne
          if ((Constant.isSubscriptionModelApplied == true || Constant.adminCommission?.isEnabled == true) && vendorModel.subscriptionPlan != null) {
            if (vendorModel.subscriptionTotalOrders == "-1") {
              vendorList.add(vendorModel);
            } else {
              if ((vendorModel.subscriptionExpiryDate != null && vendorModel.subscriptionExpiryDate!.toDate().isBefore(DateTime.now()) == false) || vendorModel.subscriptionPlan?.expiryDay == '-1') {
                if (vendorModel.subscriptionTotalOrders != '0') {
                  vendorList.add(vendorModel);
                }
              }
            }
          } else {
            vendorList.add(vendorModel);
          }
        }
        return vendorList;
      });
    } catch (e) {
      print(e);
    }
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
    return _categoryListMemo.get(
      'home',
      (onFresh) => _cacheFirstQuery<VendorCategoryModel>(
        fireStore.collection(CollectionName.vendorCategories).where("show_in_homepage", isEqualTo: true).where('publish', isEqualTo: true),
        VendorCategoryModel.fromJson,
        onRefresh: onFresh,
        tag: 'getHomeVendorCategory',
      ),
      onRefresh: onRefresh,
    );
  }

  static Future<List<VendorCategoryModel>> getVendorCategory({void Function(List<VendorCategoryModel>)? onRefresh}) async {
    return _categoryListMemo.get(
      'all',
      (onFresh) => _cacheFirstQuery<VendorCategoryModel>(
        fireStore.collection(CollectionName.vendorCategories).where('publish', isEqualTo: true),
        VendorCategoryModel.fromJson,
        onRefresh: onFresh,
        tag: 'getVendorCategory',
      ),
      onRefresh: onRefresh,
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

  static Future<List<FavouriteModel>> getFavouriteRestaurant() async {
    List<FavouriteModel> favouriteList = [];
    await fireStore.collection(CollectionName.favoriteRestaurant).where('user_id', isEqualTo: getCurrentUid()).get().then(
      (value) {
        for (var element in value.docs) {
          FavouriteModel favouriteModel = FavouriteModel.fromJson(element.data());
          favouriteList.add(favouriteModel);
        }
      },
    );
    return favouriteList;
  }

  static Future<List<FavouriteItemModel>> getFavouriteItem() async {
    List<FavouriteItemModel> favouriteList = [];
    await fireStore.collection(CollectionName.favoriteItem).where('user_id', isEqualTo: getCurrentUid()).get().then(
      (value) {
        for (var element in value.docs) {
          FavouriteItemModel favouriteModel = FavouriteItemModel.fromJson(element.data());
          favouriteList.add(favouriteModel);
        }
      },
    );
    return favouriteList;
  }

  static Future removeFavouriteRestaurant(FavouriteModel favouriteModel) async {
    await fireStore.collection(CollectionName.favoriteRestaurant).where("restaurant_id", isEqualTo: favouriteModel.restaurantId).get().then((value) {
      value.docs.forEach((element) async {
        await fireStore.collection(CollectionName.favoriteRestaurant).doc(element.id).delete();
      });
    });
  }

  static Future<void> setFavouriteRestaurant(FavouriteModel favouriteModel) async {
    await fireStore.collection(CollectionName.favoriteRestaurant).add(favouriteModel.toJson());
  }

  static Future<void> removeFavouriteItem(FavouriteItemModel favouriteModel) async {
    try {
      final favoriteCollection = fireStore.collection(CollectionName.favoriteItem);
      final querySnapshot = await favoriteCollection.where("product_id", isEqualTo: favouriteModel.productId).get();
      for (final doc in querySnapshot.docs) {
        await favoriteCollection.doc(doc.id).delete();
      }
    } catch (e) {
      print("Error removing favourite item: $e");
    }
  }

  static Future<void> setFavouriteItem(FavouriteItemModel favouriteModel) async {
    await fireStore.collection(CollectionName.favoriteItem).add(favouriteModel.toJson());
  }

  static Future<List<ProductModel>> getProductByVendorId(String vendorId, {void Function(List<ProductModel>)? onRefresh}) async {
    final String selectedFoodType = Preferences.getString(Preferences.foodDeliveryType, defaultValue: "Delivery");
    // Les deux branches d'origine executaient exactement la meme requete : seul
    // le filtre client differait. Une seule requete, un filtre conditionnel.
    // Memoire de 2 min seulement : reouvrir un restaurant ou passer de la
    // recherche a sa fiche ne relit pas le menu, mais un plat retire par le
    // restaurant disparait vite (revalidation au-dela de 2 min).
    return _menuMemo.get(
      '$vendorId|$selectedFoodType',
      (onFresh) => _cacheFirstQuery<ProductModel>(
        fireStore.collection(CollectionName.vendorProducts).where("vendorID", isEqualTo: vendorId).where('publish', isEqualTo: true).orderBy("createdAt", descending: false),
        ProductModel.fromJson,
        // Le filtre reste cote client : where("takeawayOption", isEqualTo: false)
        // cote Firestore excluait les plats ou le champ est absent (bug corrige le
        // 2026-08-25). Ne pas le redeplacer cote serveur.
        where: selectedFoodType == "TakeAway" ? null : (ProductModel p) => p.takeawayOption != true,
        onRefresh: onFresh,
        tag: 'getProductByVendorId',
      ),
      onRefresh: onRefresh,
    );
  }

  static Future<VendorCategoryModel?> getVendorCategoryById(String categoryId, {void Function(VendorCategoryModel?)? onRefresh}) async {
    return _categoryMemo.get(
      categoryId,
      (onFresh) => _cacheThenServer<VendorCategoryModel>(
        fireStore.collection(CollectionName.vendorCategories).doc(categoryId),
        (value) => value.exists ? VendorCategoryModel.fromJson(value.data()!) : null,
        onRefresh: onFresh,
        tag: 'getVendorCategoryById',
      ),
      onRefresh: onRefresh,
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

  static Future<List<CouponModel>> getOfferByVendorId(String vendorId, {void Function(List<CouponModel>)? onRefresh}) async {
    return _cacheFirstQuery<CouponModel>(
      fireStore
          .collection(CollectionName.coupons)
          .where("resturant_id", isEqualTo: vendorId)
          .where("isEnabled", isEqualTo: true)
          .where("isPublic", isEqualTo: true)
          .where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now()),
      CouponModel.fromJson,
      onRefresh: onRefresh,
      tag: 'getOfferByVendorId',
    );
  }

  static Future<List<AttributesModel>?> getAttributes({void Function(List<AttributesModel>)? onRefresh}) async {
    return _attributesMemo.get(
      'all',
      (onFresh) => _cacheFirstQuery<AttributesModel>(
        fireStore.collection(CollectionName.vendorAttributes),
        AttributesModel.fromJson,
        onRefresh: onFresh,
        tag: 'getAttributes',
      ),
      onRefresh: onRefresh,
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

  static Future<FreeDeliveryByAdminModel?> getFreeDeliveryByAdminData() async {
    FreeDeliveryByAdminModel? freeDeliveryByAdminModel;
    try {
      await fireStore.collection(CollectionName.settings).doc("freeDeliveryFeature").get().then((value) {
        if (value.exists) {
          freeDeliveryByAdminModel = FreeDeliveryByAdminModel.fromJson(value.data()!);
        }
      });
    } catch (e, s) {
      log('FireStoreUtils.firebaseCreateNewUser $e $s');
      return null;
    }
    return freeDeliveryByAdminModel;
  }

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
      // Pays memorise par zone d'environ 1 km : le geocodage (appel reseau)
      // n'est refait que si l'on change de secteur, plus a chaque lancement.
      // Fonctionne aussi hors ligne une fois le pays connu.
      final String areaKey = '${latitude.toStringAsFixed(2)},${longitude.toStringAsFixed(2)}';
      String country = Preferences.getString('taxCountryArea') == areaKey ? Preferences.getString('taxCountry') : '';
      if (country.isEmpty) {
        final List<Placemark> placeMarks = await Geocoding().placemarkFromCoordinates(latitude, longitude);
        if (placeMarks.isEmpty || (placeMarks.first.country ?? '').isEmpty) {
          return <TaxModel>[];
        }
        country = placeMarks.first.country!;
        await Preferences.setString('taxCountryArea', areaKey);
        await Preferences.setString('taxCountry', country);
      }
      return await _cacheFirstQuery<TaxModel>(
        fireStore.collection(CollectionName.tax).where('country', isEqualTo: country).where('enable', isEqualTo: true),
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

  static Future<List<CouponModel>> getAllVendorPublicCoupons(String vendorId, {void Function(List<CouponModel>)? onRefresh}) async {
    return _cacheFirstQuery<CouponModel>(
      fireStore
          .collection(CollectionName.coupons)
          .where("resturant_id", isEqualTo: vendorId)
          .where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now())
          .where("isEnabled", isEqualTo: true)
          .where("isPublic", isEqualTo: true),
      CouponModel.fromJson,
      onRefresh: onRefresh,
      tag: 'getAllVendorPublicCoupons',
    );
  }

  static Future<List<CouponModel>> getAllVendorCoupons(String vendorId, {void Function(List<CouponModel>)? onRefresh}) async {
    return _cacheFirstQuery<CouponModel>(
      fireStore
          .collection(CollectionName.coupons)
          .where("resturant_id", isEqualTo: vendorId)
          .where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now())
          .where("isEnabled", isEqualTo: true),
      CouponModel.fromJson,
      onRefresh: onRefresh,
      tag: 'getAllVendorCoupons',
    );
  }

  static Future<bool?> setOrder(OrderModel orderModel) async {
    bool isAdded = false;
    await fireStore.collection(CollectionName.restaurantOrders).doc(orderModel.id).set(orderModel.toJson()).then((value) {
      isAdded = true;
    }).catchError((error) {
      log("Failed to update user: $error");
      isAdded = false;
    });
    return isAdded;
  }

  /// Suppression d'une commande dont le paiement wallet a échoué.
  static Future<bool> deleteOrder(String orderId) async {
    try {
      await fireStore.collection(CollectionName.restaurantOrders).doc(orderId).delete();
      return true;
    } catch (error) {
      log("Failed to delete order: $error");
      return false;
    }
  }

  static Future<bool?> setCashbackRedeemModel(CashbackRedeemModel cashbackRedeemModel) async {
    bool isAdded = false;
    await fireStore.collection(CollectionName.cashbackRedeem).doc(cashbackRedeemModel.id).set(cashbackRedeemModel.toJson()).then((value) {
      isAdded = true;
    }).catchError((error) {
      log("Failed to update user: $error");
      isAdded = false;
    });
    return isAdded;
  }

  static Future<bool?> setProduct(ProductModel orderModel) async {
    bool isAdded = false;
    await fireStore.collection(CollectionName.vendorProducts).doc(orderModel.id).set(orderModel.toJson()).then((value) {
      isAdded = true;
    }).catchError((error) {
      log("Failed to update user: $error");
      isAdded = false;
    });
    return isAdded;
  }

  static Future<bool?> setBookedOrder(DineInBookingModel orderModel) async {
    bool isAdded = false;
    await fireStore.collection(CollectionName.bookedTable).doc(orderModel.id).set(orderModel.toJson()).then((value) {
      isAdded = true;
    }).catchError((error) {
      log("Failed to update user: $error");
      isAdded = false;
    });
    return isAdded;
  }

  static Future<List<OrderModel>> getAllOrder() async {
    List<OrderModel> list = [];

    // Limite large (200) : protège contre une croissance illimitée pour un client
    // très fidèle sans affecter l'historique visible d'un utilisateur normal.
    // Une vraie pagination serait nécessaire pour aller au-delà proprement.
    await fireStore.collection(CollectionName.restaurantOrders).where("authorID", isEqualTo: FireStoreUtils.getCurrentUid()).orderBy("createdAt", descending: true).limit(200).get().then((value) {
      log("FireStoreUtils.getCurrentUid() :: ${FireStoreUtils.getCurrentUid()}");
      for (var element in value.docs) {
        OrderModel taxModel = OrderModel.fromJson(element.data());
        list.add(taxModel);
      }
    }).catchError((e) {
      log("FireStoreUtils.getCurrentUid() :: getAllOrder :: $e");
    });
    return list;
  }

  static Future<OrderModel?> getOrderByOrderId(String orderId) async {
    OrderModel? orderModel;
    try {
      await fireStore.collection(CollectionName.restaurantOrders).doc(orderId).get().then((value) {
        if (value.data() != null) {
          orderModel = OrderModel.fromJson(value.data()!);
        }
      });
    } catch (e, s) {
      print('FireStoreUtils.firebaseCreateNewUser $e $s');
      return null;
    }
    return orderModel;
  }

  static Future<List<DineInBookingModel>> getDineInBooking(bool isUpcoming) async {
    List<DineInBookingModel> list = [];

    if (isUpcoming) {
      await fireStore
          .collection(CollectionName.bookedTable)
          .where('author.id', isEqualTo: getCurrentUid())
          .where('date', isGreaterThan: Timestamp.now())
          .orderBy('date', descending: true)
          .orderBy('createdAt', descending: true)
          .get()
          .then((value) {
        for (var element in value.docs) {
          DineInBookingModel taxModel = DineInBookingModel.fromJson(element.data());
          list.add(taxModel);
        }
      }).catchError((error) {
        log(error.toString());
      });
    } else {
      await fireStore
          .collection(CollectionName.bookedTable)
          .where('author.id', isEqualTo: getCurrentUid())
          .where('date', isLessThan: Timestamp.now())
          .orderBy('date', descending: true)
          .orderBy('createdAt', descending: true)
          .get()
          .then((value) {
        for (var element in value.docs) {
          DineInBookingModel taxModel = DineInBookingModel.fromJson(element.data());
          list.add(taxModel);
        }
      }).catchError((error) {
        log(error.toString());
      });
    }

    return list;
  }

  static Future<ReferralModel?> getReferralUserBy() async {
    ReferralModel? referralModel;
    try {
      await fireStore.collection(CollectionName.referral).doc(getCurrentUid()).get().then((value) {
        referralModel = ReferralModel.fromJson(value.data()!);
      });
    } catch (e, s) {
      print('FireStoreUtils.firebaseCreateNewUser $e $s');
      return null;
    }
    return referralModel;
  }

  static Future<List<GiftCardsModel>> getGiftCard() async {
    List<GiftCardsModel> giftCardModelList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await fireStore.collection(CollectionName.giftCards).where("isEnable", isEqualTo: true).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        log(document.data().toString());
        giftCardModelList.add(GiftCardsModel.fromJson(document.data()));
      } catch (e) {
        debugPrint('FireStoreUtils.get Currency Parse error $e');
      }
    });
    return giftCardModelList;
  }

  // placeGiftCardOrder / checkRedeemCode supprimés : l'achat et le rachat
  // de cartes cadeaux passent par v1_walletBuyGiftCard / v1_walletRedeemGiftCard
  // (écriture client interdite sur gift_purchases).

  static Future<List<GiftCardsOrderModel>> getGiftHistory() async {
    List<GiftCardsOrderModel> giftCardsOrderList = [];
    await fireStore.collection(CollectionName.giftPurchases).where("userid", isEqualTo: FireStoreUtils.getCurrentUid()).get().then((value) {
      for (var element in value.docs) {
        GiftCardsOrderModel giftCardsOrderModel = GiftCardsOrderModel.fromJson(element.data());
        giftCardsOrderList.add(giftCardsOrderModel);
      }
    });
    return giftCardsOrderList;
  }

  static Future<List> getVendorCuisines(String id) async {
    List tagList = [];
    // Les deux requetes passent par le cache : identite comme fromJson, le
    // post-traitement travaille sur les documents bruts comme avant.
    final List<Map<String, dynamic>> products = await _cacheFirstQuery<Map<String, dynamic>>(
      fireStore.collection(CollectionName.vendorProducts).where('vendorID', isEqualTo: id),
      (Map<String, dynamic> data) => data,
      tag: 'getVendorCuisines products',
    );
    final Set<String> categoryIds = {};
    for (var data in products) {
      if (data.containsKey("categoryID") && data['categoryID'].toString().isNotEmpty) {
        categoryIds.add(data['categoryID'].toString());
      }
    }
    if (categoryIds.isEmpty) return tagList;

    // Avant : on tirait TOUTE la collection vendorCategories (publish==true) puis
    // on filtrait cote client sur les IDs du menu de ce vendeur. Desormais on ne
    // demande que les categories reellement utilisees par ses produits, par lots
    // de 30 (limite de whereIn) — un seul .where('id', ...) reste indexable
    // simplement, le filtre publish se fait ensuite sur ce petit lot.
    final List<String> idList = categoryIds.toList();
    for (int i = 0; i < idList.length; i += 30) {
      final int end = i + 30 > idList.length ? idList.length : i + 30;
      final List<String> chunk = idList.sublist(i, end);
      final List<Map<String, dynamic>> categories = await _cacheFirstQuery<Map<String, dynamic>>(
        fireStore.collection(CollectionName.vendorCategories).where('id', whereIn: chunk),
        (Map<String, dynamic> data) => data,
        tag: 'getVendorCuisines categories',
      );
      for (var catDoc in categories) {
        if (catDoc['publish'] == true && catDoc.containsKey("title") && catDoc['title'].toString().isNotEmpty) {
          tagList.add(catDoc['title']);
        }
      }
    }
    return tagList;
  }

  static Future<NotificationModel?> getNotificationContent(String type) async {
    NotificationModel? notificationModel;
    await fireStore.collection(CollectionName.dynamicNotification).where('type', isEqualTo: type).get().then((value) {
      print("------>");
      if (value.docs.isNotEmpty) {
        print(value.docs.first.data());

        notificationModel = NotificationModel.fromJson(value.docs.first.data());
      } else {
        notificationModel = NotificationModel(id: "", message: "Notification setup is pending", subject: "setup notification", type: "");
      }
    });
    return notificationModel;
  }

  static Future<bool?> deleteUser() async {
    bool? isDelete;
    try {
      await fireStore.collection(CollectionName.users).doc(FireStoreUtils.getCurrentUid()).delete();

      // delete user  from firebase auth
      await deleteAuthUser(FireStoreUtils.getCurrentUid()).then((value) {
        isDelete = true;
      });
    } catch (e, s) {
      log('FireStoreUtils.firebaseCreateNewUser $e $s');
      return false;
    }
    return isDelete;
  }

  static Future<bool> deleteAuthUser(String uid) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print("❌ No user is logged in.");
        return false;
      }

      final idToken = await user.getIdToken();
      final projectId = DefaultFirebaseOptions.currentPlatform.projectId;
      final url = Uri.parse('https://us-central1-$projectId.cloudfunctions.net/deleteUser');

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'data': {'uid': uid}, // 👈 matches your Cloud Function structure
        }),
      );

      print("Response [${response.statusCode}]: ${response.body}");

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return decoded['result']?['success'] == true || decoded['success'] == true;
      } else {
        print("⚠️ Cloud Function failed: ${response.body}");
        return false;
      }
    } catch (e) {
      print("❌ Error deleting driver: $e");
      return false;
    }
  }

  static Future<Url> uploadChatImageToFireStorage(File image, BuildContext context) async {
    ShowToastDialog.showLoader("Please wait");
    var uniqueID = const Uuid().v4();
    Reference upload = FirebaseStorage.instance.ref().child('images/$uniqueID.png');
    UploadTask uploadTask = upload.putFile(image);
    var storageRef = (await uploadTask.whenComplete(() {})).ref;
    var downloadUrl = await storageRef.getDownloadURL();
    var metaData = await storageRef.getMetadata();
    ShowToastDialog.closeLoader();
    return Url(mime: metaData.contentType ?? 'image', url: downloadUrl.toString());
  }

  static Future<ChatVideoContainer?> uploadChatVideoToFireStorage(BuildContext context, File video) async {
    try {
      ShowToastDialog.showLoader("Uploading video...");
      final String uniqueID = const Uuid().v4();
      final Reference videoRef = FirebaseStorage.instance.ref('videos/$uniqueID.mp4');
      final UploadTask uploadTask = videoRef.putFile(
        video,
        SettableMetadata(contentType: 'video/mp4'),
      );
      await uploadTask;
      final String videoUrl = await videoRef.getDownloadURL();
      ShowToastDialog.showLoader("Generating thumbnail...");
      File thumbnail = await VideoCompress.getFileThumbnail(
        video.path,
        quality: 75, // 0 - 100
        position: -1, // Get the first frame
      );

      final String thumbnailID = const Uuid().v4();
      final Reference thumbnailRef = FirebaseStorage.instance.ref('thumbnails/$thumbnailID.jpg');
      final UploadTask thumbnailUploadTask = thumbnailRef.putData(
        thumbnail.readAsBytesSync(),
        SettableMetadata(contentType: 'image/jpeg'),
      );
      await thumbnailUploadTask;
      final String thumbnailUrl = await thumbnailRef.getDownloadURL();
      var metaData = await thumbnailRef.getMetadata();
      ShowToastDialog.closeLoader();

      return ChatVideoContainer(videoUrl: Url(url: videoUrl.toString(), mime: metaData.contentType ?? 'video'), thumbnailUrl: thumbnailUrl);
    } catch (e) {
      ShowToastDialog.closeLoader();
      ShowToastDialog.showToast("Error: ${e.toString()}");
      return null;
    }
  }

  static Future<String> uploadVideoThumbnailToFireStorage(File file) async {
    var uniqueID = const Uuid().v4();
    Reference upload = FirebaseStorage.instance.ref().child('thumbnails/$uniqueID.png');
    UploadTask uploadTask = upload.putFile(file);
    var downloadUrl = await (await uploadTask.whenComplete(() {})).ref.getDownloadURL();
    return downloadUrl.toString();
  }

  static Future<List<RatingModel>> getVendorReviews(String vendorId) async {
    List<RatingModel> ratingList = [];
    await fireStore.collection(CollectionName.foodsReview).where('VendorId', isEqualTo: vendorId).limit(100).get().then((value) {
      for (var element in value.docs) {
        RatingModel giftCardsOrderModel = RatingModel.fromJson(element.data());
        ratingList.add(giftCardsOrderModel);
      }
    });
    return ratingList;
  }

  static Future<RatingModel?> getOrderReviewsByID(String orderId, String productID) async {
    RatingModel? ratingModel;

    await fireStore.collection(CollectionName.foodsReview).where('orderid', isEqualTo: orderId).where('productId', isEqualTo: productID).get().then((value) {
      if (value.docs.isNotEmpty) {
        ratingModel = RatingModel.fromJson(value.docs.first.data());
      }
    }).catchError((error) {
      log(error.toString());
    });
    return ratingModel;
  }

  static Future<VendorCategoryModel?> getVendorCategoryByCategoryId(String categoryId) async {
    VendorCategoryModel? vendorCategoryModel;
    try {
      await fireStore.collection(CollectionName.vendorCategories).doc(categoryId).get().then((value) {
        if (value.exists) {
          vendorCategoryModel = VendorCategoryModel.fromJson(value.data()!);
        }
      });
    } catch (e, s) {
      log('FireStoreUtils.firebaseCreateNewUser $e $s');
      return null;
    }
    return vendorCategoryModel;
  }

  static Future<ReviewAttributeModel?> getVendorReviewAttribute(String attributeId) async {
    ReviewAttributeModel? vendorCategoryModel;
    try {
      await fireStore.collection(CollectionName.reviewAttributes).doc(attributeId).get().then((value) {
        if (value.exists) {
          vendorCategoryModel = ReviewAttributeModel.fromJson(value.data()!);
        }
      });
    } catch (e, s) {
      log('FireStoreUtils.firebaseCreateNewUser $e $s');
      return null;
    }
    return vendorCategoryModel;
  }

  static Future<bool?> setRatingModel(RatingModel ratingModel) async {
    bool isAdded = false;
    await fireStore.collection(CollectionName.foodsReview).doc(ratingModel.id).set(ratingModel.toJson()).then((value) {
      isAdded = true;
    }).catchError((error) {
      log("Failed to update user: $error");
      isAdded = false;
    });
    return isAdded;
  }

  static Future<VendorModel?> updateVendor(VendorModel vendor) async {
    // isLive / isVerified sont geres par le backend (regles Firestore : le client
    // ne peut pas en changer la valeur). On ne les renvoie pas — une valeur lue
    // en cache pourrait etre perimee et faire rejeter l'ecriture — et on fusionne
    // (merge) pour ne jamais effacer ces champs ni ceux que le modele ignore.
    final Map<String, dynamic> data = vendor.toJson()
      ..remove('isLive')
      ..remove('isVerified');
    return await fireStore.collection(CollectionName.vendors).doc(vendor.id).set(data, SetOptions(merge: true)).then((document) {
      return vendor;
    });
  }

  static Future<List<AdvertisementModel>> getAllAdvertisement({void Function(List<AdvertisementModel>)? onRefresh}) async {
    return _cacheFirstQuery<AdvertisementModel>(
      fireStore
          .collection(CollectionName.advertisements)
          .where('status', isEqualTo: 'approved')
          .where('paymentStatus', isEqualTo: true)
          .where('startDate', isLessThanOrEqualTo: DateTime.now())
          .where('endDate', isGreaterThan: DateTime.now())
          .orderBy('priority', descending: false),
      AdvertisementModel.fromJson,
      // Filtre client conserve : une annonce sans champ isPaused est active.
      where: (AdvertisementModel a) => a.isPaused == null || a.isPaused == false,
      onRefresh: onRefresh,
      tag: 'getAllAdvertisement',
    );
  }

  static Future<AdvertisementModel> getAdvertisementById(String advId, {void Function(AdvertisementModel?)? onRefresh}) async {
    final AdvertisementModel? advertisementModel = await _cacheThenServer<AdvertisementModel>(
      fireStore.collection(CollectionName.advertisements).doc(advId),
      (value) => value.exists ? AdvertisementModel.fromJson(value.data()!) : null,
      onRefresh: onRefresh,
      tag: 'getAdvertisementById',
    );
    // Signature non nullable conservee : les appelants attendent un modele vide,
    // pas un null, quand l'annonce n'existe pas.
    return advertisementModel ?? AdvertisementModel();
  }

  static Future<List<CashbackModel>> getAllCashbak() async {
    List<CashbackModel> cashbackList = [];
    await fireStore.collection(CollectionName.cashback).limit(100).get().then((value) {
      cashbackList = value.docs.map((doc) {
        return CashbackModel.fromJson(doc.data());
      }).toList();
    }).catchError((error) {
      log(error.toString());
    });

    return cashbackList;
  }

  static Future<List<CashbackRedeemModel>> getRedeemedCashbacks(String cashbackId) async {
    List<CashbackRedeemModel> redeemedDocs = [];

    try {
      await fireStore.collection(CollectionName.cashbackRedeem).where('userId', isEqualTo: FireStoreUtils.getCurrentUid()).where('cashbackId', isEqualTo: cashbackId).get().then((value) {
        redeemedDocs = value.docs.map((doc) {
          return CashbackRedeemModel.fromJson(doc.data());
        }).toList();
      });
    } catch (error, stackTrace) {
      log('Error fetching redeemed cashback data: $error', stackTrace: stackTrace);
    }

    return redeemedDocs;
  }

  static Future<List<CashbackModel>> getCashbackList() async {
    List<CashbackModel> cashbackList = [];
    try {
      await fireStore
          .collection(CollectionName.cashback)
          .where('isEnabled', isEqualTo: true)
          .where('startDate', isLessThanOrEqualTo: Timestamp.now())
          .where('endDate', isGreaterThanOrEqualTo: Timestamp.now())
          .get()
          .then((event) {
        if (event.docs.isNotEmpty) {
          for (var element in event.docs) {
            CashbackModel cashbackModel = CashbackModel.fromJson(element.data());
            if (cashbackModel.customerIds == null || cashbackModel.customerIds?.contains(FireStoreUtils.getCurrentUid()) == true) {
              cashbackList.add(cashbackModel);
            }
          }
        }
      });
    } catch (error, stackTrace) {
      log('Error fetching redeemed cashback data: $error', stackTrace: stackTrace);
    }

    return cashbackList;
  }

  static late StreamSubscription<QuerySnapshot> adminChatSeenSubscription;

  static void setSeen() {
    final currentUserId = FireStoreUtils.getCurrentUid();

    adminChatSeenSubscription = fireStore
        .collection(CollectionName.chat)
        .doc(currentUserId)
        .collection("thread")
        .where('senderId', isEqualTo: Constant.adminType)
        .where('seen', isEqualTo: false)
        .snapshots()
        .listen((querySnapshot) async {
      for (final doc in querySnapshot.docs) {
        try {
          await doc.reference.update({'seen': true});
        } catch (e) {
          log(e.toString());
        }
      }
    }, onError: (error) {
      log(error.toString());
    });
  }

  static void stopSeenListener() {
    adminChatSeenSubscription.cancel();
  }

  static late StreamSubscription<QuerySnapshot> orderChatSeenSubscription;

  static void setSeenChatForOrder({required String orderId}) {
    orderChatSeenSubscription = fireStore
        .collection(CollectionName.chat)
        .doc(orderId)
        .collection("thread")
        .where('senderId', isNotEqualTo: FireStoreUtils.getCurrentUid())
        .where('seen', isEqualTo: false)
        .snapshots()
        .listen((querySnapshot) async {
      for (final doc in querySnapshot.docs) {
        try {
          await doc.reference.update({'seen': true});
        } catch (e) {
          log(e.toString());
        }
      }
    }, onError: (error) {
      log(error.toString());
    });
  }

  static void stopSeenForOrderListener() {
    orderChatSeenSubscription.cancel();
  }

  static Future<ConversationModel> addChat(ConversationModel conversationModel) async {
    final chatCollection = fireStore.collection(CollectionName.chat);
    final docId = (conversationModel.receiverId?.contains('admin') == false) ? conversationModel.orderId : conversationModel.senderId;
    await chatCollection.doc(docId).collection("thread").doc(conversationModel.id).set(conversationModel.toJson());
    return conversationModel;
  }

  static Future<InboxModel> addInbox(InboxModel inboxModel) async {
    final collection = fireStore.collection(CollectionName.chat);
    final docId = (inboxModel.senderReceiverId?.contains('admin') == false) ? inboxModel.orderId : inboxModel.senderId;
    await collection.doc(docId).set(inboxModel.toJson());
    return inboxModel;
  }

  static Future<String?> isAddressLocationInVendorZone({
    required double latitude,
    required double longitude,
    required VendorModel vendor,
  }) async {
    final zones = await FireStoreUtils.getZone();
    if (zones == null || zones.isEmpty) return null;

    final currentPoint = LatLng(latitude, longitude);

    for (final zone in zones) {
      if (zone.area == null) continue;

      final isInside = Constant.isPointInPolygon(currentPoint, zone.area!);

      if (isInside && vendor.zoneId == zone.id) {
        return vendor.zoneId;
      }
    }

    return null;
  }

  static Future<bool?> getNearbyVendor({
    required double latitude,
    required double longitude,
    required VendorModel vendor,
  }) async {
    String? zoneIdData = await isAddressLocationInVendorZone(latitude: latitude, longitude: longitude, vendor: vendor);
    if (zoneIdData == null) {
      return false;
    }
    final query = fireStore.collection(CollectionName.vendors).where('id', isEqualTo: vendor.id).where('zoneId', isEqualTo: zoneIdData);
    final GeoFirePoint center = Geoflutterfire().point(latitude: latitude, longitude: longitude);
    const String field = 'g';
    final List<DocumentSnapshot> vendors = await Geoflutterfire()
        .collection(collectionRef: query)
        .within(
          center: center,
          radius: double.parse(Constant.radius),
          field: field,
          strictMode: true,
        )
        .first;
    return vendors.isNotEmpty ? true : false;
  }
}
