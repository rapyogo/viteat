import 'package:customer/services/location_service.dart';
import 'dart:async';
import 'package:customer/constant/constant.dart';
import 'package:customer/controllers/dash_board_controller.dart';
import 'package:customer/models/BannerModel.dart';
import 'package:customer/models/advertisement_model.dart';
import 'package:customer/models/coupon_model.dart';
import 'package:customer/models/favourite_model.dart';
import 'package:customer/models/story_model.dart';
import 'package:customer/models/tax_model.dart';
import 'package:customer/models/vendor_category_model.dart';
import 'package:customer/models/vendor_model.dart';
import 'package:customer/services/cart_provider.dart';
import 'package:customer/utils/fire_store_utils.dart';
import 'package:customer/utils/preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';

class HomeController extends GetxController {
  final DashBoardController dashBoardController = Get.find<DashBoardController>();
  final CartProvider cartProvider = CartProvider();

  RxBool isLoading = true.obs;
  RxBool isListView = true.obs;
  RxBool isPopular = true.obs;
  RxString selectedOrderTypeValue = "Delivery".obs;

  final Rx<PageController> pageController = PageController(viewportFraction: 0.877).obs;
  final Rx<PageController> pageBottomController = PageController(viewportFraction: 0.877).obs;
  final RxInt currentPage = 0.obs;
  final RxInt currentBottomPage = 0.obs;

  late TabController tabController;

  // 🔹 Caching & reactive data
  final RxList<VendorCategoryModel> vendorCategoryModel = <VendorCategoryModel>[].obs;
  final RxList<VendorModel> allNearestRestaurant = <VendorModel>[].obs;
  final RxList<VendorModel> newArrivalRestaurantList = <VendorModel>[].obs;
  final RxList<VendorModel> popularRestaurantList = <VendorModel>[].obs;
  final RxList<VendorModel> couponRestaurantList = <VendorModel>[].obs;
  final RxList<AdvertisementModel> advertisementList = <AdvertisementModel>[].obs;
  final RxList<CouponModel> couponList = <CouponModel>[].obs;
  final RxList<StoryModel> storyList = <StoryModel>[].obs;
  final RxList<BannerModel> bannerModel = <BannerModel>[].obs;
  final RxList<BannerModel> bannerBottomModel = <BannerModel>[].obs;
  final RxList<FavouriteModel> favouriteList = <FavouriteModel>[].obs;

  StreamSubscription? _cartSubscription;
  StreamSubscription? _restaurantSubscription;

  @override
  void onInit() {
    super.onInit();
    getData();
  }

  Future<void> getData() async {
    isLoading.value = true;
    selectedOrderTypeValue.value = Preferences.getString(Preferences.foodDeliveryType, defaultValue: "Delivery");
    await Future.wait([
      getTaxList(),
      getVendorCategory(),
      getZone(),
      getCartData(),
    ]);
    _listenForRestaurants(); // 🔹 Stream listens in background
  }

  Future<void> getTaxList() async {
    // Le meme traitement sert au resultat servi par le cache et a la version
    // revalidee qui arrive ensuite du serveur.
    void apply(List<TaxModel>? value) {
      if (value != null) {
        Constant.taxProductList = value.where((TaxModel taxModel) => taxModel.scope == "product").toList();
        Constant.orderProductTaxList = value.where((TaxModel taxModel) => taxModel.scope == "order").toList();
        Constant.driverDeliveryTaxList = value.where((TaxModel taxModel) => taxModel.scope == "delivery").toList();

        if (Constant.packagingChargeEnable == true) {
          Constant.packagingTaxList = value.where((TaxModel taxModel) => taxModel.scope == "packaging").toList();
        }
        if (Constant.platformFeeModel?.enable == true) {
          Constant.platformTaxList = value.where((TaxModel taxModel) => taxModel.scope == "platform").toList();
        }
      }
    }

    apply(await FireStoreUtils.getTaxList(onRefresh: apply));
  }

  // ✅ Optimized cart listening
  Future<void> getCartData() async {
    _cartSubscription?.cancel();
    _cartSubscription = cartProvider.cartStream.listen((event) {
      cartItem
        ..clear()
        ..addAll(event);
      update(['cart']); // partial update only for cart widgets
    });
  }

  // ✅ Stream-based restaurant updates
  void _listenForRestaurants() {
    _restaurantSubscription?.cancel();
    _restaurantSubscription = FireStoreUtils.getAllNearestRestaurant().listen((restaurants) async {
      if (restaurants.isEmpty) {
        isLoading.value = false;
        return;
      }

      // Tri : ouverts d'abord, puis par note. Les cles sont calculees une seule
      // fois par restaurant au lieu de l'etre a chaque comparaison (Foodie 9.2).
      // La note est comparee en nombre, pas en texte ("10" < "4.5" en texte).
      final Map<String?, bool> openStatus = {
        for (final r in restaurants) r.id: Constant.statusCheckOpenORClose(vendorModel: r),
      };
      final Map<String?, double> ratingKey = {
        for (final r in restaurants)
          r.id: double.tryParse(Constant.calculateReview(reviewCount: r.reviewsCount.toString(), reviewSum: r.reviewsSum.toString())) ?? 0.0,
      };
      restaurants.sort((a, b) {
        final aOpen = openStatus[a.id] ?? false;
        final bOpen = openStatus[b.id] ?? false;
        if (aOpen == bOpen) {
          return (ratingKey[b.id] ?? 0.0).compareTo(ratingKey[a.id] ?? 0.0);
        }
        return aOpen ? -1 : 1;
      });

      // Batch update data lists (reduces rebuilds)
      allNearestRestaurant.assignAll(restaurants);
      newArrivalRestaurantList.assignAll(restaurants);
      newArrivalRestaurantList.sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
      //:: ${Constant.timestampToDate(vendorModel.createdAt!)}
      popularRestaurantList.assignAll(restaurants.take(10)); // only top 10
      Constant.restaurantList = allNearestRestaurant;

      // Filter categories used by restaurants
      final usedCategoryIds = restaurants.expand((v) => v.categoryID ?? []).toSet();
      vendorCategoryModel.retainWhere((cat) => usedCategoryIds.contains(cat.id));

      // L'accueil s'affiche des que les restaurants sont prets : coupons,
      // stories et pubs sont des listes Rx (servies depuis le cache puis
      // revalidees), leurs sections apparaissent seules (Foodie 9.2).
      isLoading.value = false;
      unawaited(_loadAdditionalData(restaurants).catchError((Object e) {
        debugPrint('HomeController: donnees secondaires de l'accueil indisponibles : $e');
      }));
    });
  }

  // ✅ Parallel fetching of coupons, stories, ads
  Future<void> _loadAdditionalData(List<VendorModel> restaurants) async {
    await Future.wait([
      _fetchCoupons(restaurants),
      _fetchStories(restaurants),
      if (Constant.isEnableAdsFeature) _fetchAds(restaurants),
    ]);
  }

  Future<void> _fetchCoupons(List<VendorModel> restaurants) async {
    void apply(List<CouponModel> values) {
      final now = DateTime.now();
      final List<CouponModel> coupons = [];
      final List<VendorModel> vendors = [];
      for (final c in values) {
        if (c.expiresAt!.toDate().isAfter(now)) {
          final match = restaurants.firstWhereOrNull((r) => r.id == c.resturantId);
          if (match != null) {
            coupons.add(c);
            vendors.add(match);
          }
        }
      }
      couponList.assignAll(coupons);
      couponRestaurantList.assignAll(vendors);
    }

    apply(await FireStoreUtils.getHomeCoupon(onRefresh: apply));
  }

  Future<void> _fetchStories(List<VendorModel> restaurants) async {
    final vendorIds = restaurants.map((r) => r.id).toSet();
    void apply(List<StoryModel> values) {
      storyList.assignAll(values.where((s) => vendorIds.contains(s.vendorID)).toList());
    }

    apply(await FireStoreUtils.getStory(onRefresh: apply));
  }

  Future<void> _fetchAds(List<VendorModel> restaurants) async {
    final vendorIds = restaurants.map((r) => r.id).toSet();
    void apply(List<AdvertisementModel> values) {
      advertisementList.assignAll(values.where((a) => vendorIds.contains(a.vendorId)).toList());
    }

    apply(await FireStoreUtils.getAllAdvertisement(onRefresh: apply));
  }

  // ✅ Cached and parallel category + banner + favourite fetch
  Future<void> getVendorCategory() async {
    final results = await Future.wait([
      FireStoreUtils.getHomeVendorCategory(onRefresh: vendorCategoryModel.assignAll),
      FireStoreUtils.getHomeTopBanner(onRefresh: bannerModel.assignAll),
      FireStoreUtils.getHomeBottomBanner(onRefresh: bannerBottomModel.assignAll),
    ]);

    vendorCategoryModel.assignAll(results[0] as List<VendorCategoryModel>);
    bannerModel.assignAll(results[1] as List<BannerModel>);
    bannerBottomModel.assignAll(results[2] as List<BannerModel>);

    // Les favoris ne pilotent que les coeurs : chargement en arriere-plan
    // plutot que de bloquer le premier affichage (Foodie 9.2).
    unawaited(getFavouriteRestaurant());
  }

  Future<void> getFavouriteRestaurant() async {
    // Comme dans SplashController, c'est la session Firebase Auth persistee
    // localement qui fait foi, pas la presence d'un profil : hors ligne, le
    // dashboard peut s'ouvrir en mode cache sans profil frais. Sans session
    // locale (invite), rien a lire. On ne vide jamais la liste ni le profil
    // sur un echec : un profil restaure depuis le cache reste une session valide.
    if (FirebaseAuth.instance.currentUser == null) return;
    try {
      final favs = await FireStoreUtils.getFavouriteRestaurant();
      favouriteList.assignAll(favs);
    } catch (e) {
      debugPrint('HomeController: favoris indisponibles (liste conservee) : $e');
    }
  }

  Future<void> getZone() => LocationService.refreshZone();

  // allNearestRestaurant contient déjà tous les vendeurs pertinents pour les
  // pubs et stories (elles sont filtrées contre cette même liste dans
  // _fetchAds/_fetchStories) — recherche synchrone, pas de nouveau fetch.
  VendorModel? vendorById(String? id) => id == null ? null : allNearestRestaurant.firstWhereOrNull((v) => v.id == id);

  @override
  void onClose() {
    _cartSubscription?.cancel();
    _restaurantSubscription?.cancel();
    super.onClose();
  }
}
