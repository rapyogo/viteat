import 'package:customer/constant/collection_name.dart';
import 'package:customer/constant/constant.dart';
import 'package:customer/models/favourite_item_model.dart';
import 'package:customer/models/favourite_model.dart';
import 'package:customer/models/product_model.dart';
import 'package:customer/models/vendor_model.dart';
import 'package:customer/utils/fire_store_utils.dart';
import 'package:get/get.dart';

class FavouriteController extends GetxController {
  RxBool favouriteRestaurant = true.obs;
  RxList<FavouriteModel> favouriteList = <FavouriteModel>[].obs;
  RxList<VendorModel> favouriteVendorList = <VendorModel>[].obs;

  RxList<FavouriteItemModel> favouriteItemList = <FavouriteItemModel>[].obs;
  RxList<ProductModel> favouriteFoodList = <ProductModel>[].obs;

  // Prix par article favori affiché sur l'écran (getPrice()) — précharge une
  // fois par vendeur unique au lieu d'un aller-retour Firestore à chaque
  // rebuild de la liste.
  RxMap<String, VendorModel> foodVendorCache = <String, VendorModel>{}.obs;

  RxBool isLoading = true.obs;

  Worker? _favouritesWorker;

  /// Rechargements qui se chevauchent : seul le dernier ecrit les listes.
  int _loadId = 0;

  @override
  void onInit() {
    super.onInit();
    getData();
    // L'onglet reste monte (IndexedStack du dashboard) : sans ce signal, un plat
    // ou un restaurant ajoute ailleurs n'apparaissait jamais ici.
    _favouritesWorker = debounce<int>(FireStoreUtils.favouritesVersion, (_) => getData(silent: true), time: const Duration(milliseconds: 400));
  }

  @override
  void onClose() {
    _favouritesWorker?.dispose();
    super.onClose();
  }

  /// [silent] : rechargement en arriere-plan, sans spinner ni liste videe.
  Future<void> getData({bool silent = false}) async {
    final int loadId = ++_loadId;
    if (!silent) reset();
    final List<FavouriteModel> favouriteList = <FavouriteModel>[];
    final List<VendorModel> favouriteVendorList = <VendorModel>[];
    final List<FavouriteItemModel> favouriteItemList = <FavouriteItemModel>[];
    final List<ProductModel> favouriteFoodList = <ProductModel>[];
    final Map<String, VendorModel> foodVendorCache = <String, VendorModel>{};
    if (Constant.userModel != null) {
      // getFavouriteRestaurant() et getFavouriteItem() sont indépendants.
      final List<dynamic> baseLists = await Future.wait([
        FireStoreUtils.getFavouriteRestaurant(),
        FireStoreUtils.getFavouriteItem(),
      ]);
      favouriteList.addAll(baseLists[0] as List<FavouriteModel>);
      favouriteItemList.addAll(baseLists[1] as List<FavouriteItemModel>);

      // Un getVendorById() par favori, mais lancés en parallèle plutôt qu'en
      // séquence (N allers-retours l'un après l'autre auparavant).
      final List<VendorModel?> vendorResults = await Future.wait(
        favouriteList.map((element) => FireStoreUtils.getVendorByIdCached(element.restaurantId.toString())),
      );
      List<VendorModel> favouriteVendorData = [];
      for (final value in vendorResults) {
        if (value != null && Constant.isVendorLive(value)) {
          if ((Constant.isSubscriptionModelApplied == true || Constant.adminCommission?.isEnabled == true) && value.subscriptionPlan != null) {
            if (value.subscriptionTotalOrders == "-1") {
              favouriteVendorData.add(value);
            } else {
              if ((value.subscriptionExpiryDate != null && value.subscriptionExpiryDate!.toDate().isBefore(DateTime.now()) == false) || value.subscriptionPlan?.expiryDay == '-1') {
                if (value.subscriptionTotalOrders != '0') {
                  favouriteVendorData.add(value);
                }
              }
            }
          } else {
            favouriteVendorData.add(value);
          }
        }
      }
      favouriteVendorData.sort((a, b) {
        final aOpen = Constant.statusCheckOpenORClose(vendorModel: a);
        final bOpen = Constant.statusCheckOpenORClose(vendorModel: b);
        if (aOpen == bOpen) return 0;
        return aOpen ? -1 : 1;
      });
      favouriteVendorList.addAll(favouriteVendorData);

      // Idem pour les articles favoris : chaque résolution (produit puis,
      // si nécessaire, son vendeur) tourne en parallèle des autres.
      final List<ProductModel?> foodResults = await Future.wait(
        favouriteItemList.map((element) => _resolveFavouriteFood(element)),
      );
      favouriteFoodList.addAll(foodResults.whereType<ProductModel>());
    }
    final List<ProductModel> foods = removeDuplicateFoods(favouriteFoodList);
    final List<VendorModel> vendors = removeDuplicateVendor(favouriteVendorList);
    await _loadFoodVendorCache(foods, foodVendorCache);
    // Plats dont le restaurant est hors ligne (isLive == false) : non proposes.
    foods.removeWhere((p) => !Constant.isVendorLive(foodVendorCache[p.vendorID]));
    if (loadId != _loadId || isClosed) return;
    this.favouriteList.value = favouriteList;
    this.favouriteItemList.value = favouriteItemList;
    this.favouriteVendorList.value = vendors;
    this.foodVendorCache.assignAll(foodVendorCache);
    this.favouriteFoodList.value = foods;
    isLoading.value = false;
  }

  Future<void> _loadFoodVendorCache(List<ProductModel> foods, Map<String, VendorModel> foodVendorCache) async {
    final List<String> vendorIds = foods.map((p) => p.vendorID).whereType<String>().toSet().where((id) => !foodVendorCache.containsKey(id)).toList();
    if (vendorIds.isEmpty) return;
    final List<VendorModel?> results = await Future.wait(vendorIds.map((id) => FireStoreUtils.getVendorByIdCached(id)));
    for (int i = 0; i < vendorIds.length; i++) {
      final VendorModel? vendor = results[i];
      if (vendor != null) foodVendorCache[vendorIds[i]] = vendor;
    }
  }

  Future<ProductModel?> _resolveFavouriteFood(FavouriteItemModel element) async {
    final ProductModel? value = await FireStoreUtils.getProductById(element.productId.toString());
    if (value == null || value.publish != true) return null;
    if (Constant.isSubscriptionModelApplied != true && Constant.adminCommission?.isEnabled != true) {
      return value;
    }
    final vendorDoc = await FireStoreUtils.fireStore.collection(CollectionName.vendors).doc(value.vendorID.toString()).get();
    if (!vendorDoc.exists) return null;
    VendorModel vendorModel = VendorModel.fromJson(vendorDoc.data()!);
    if (vendorModel.subscriptionPlan == null) return null;
    if (vendorModel.subscriptionTotalOrders == "-1") return value;
    if ((vendorModel.subscriptionExpiryDate != null && vendorModel.subscriptionExpiryDate!.toDate().isBefore(DateTime.now()) == false) || vendorModel.subscriptionPlan?.expiryDay == "-1") {
      if (vendorModel.subscriptionTotalOrders != '0') return value;
    }
    return null;
  }

  List<ProductModel> removeDuplicateFoods(List<ProductModel> favouriteFoodList) {
    final seenIds = <String>{};
    return favouriteFoodList.where((food) {
      return seenIds.add(food.id!);
    }).toList();
  }

  List<VendorModel> removeDuplicateVendor(List<VendorModel> favouriteFoodVendor) {
    final seenIds = <String>{};
    return favouriteFoodVendor.where((food) {
      return seenIds.add(food.id!);
    }).toList();
  }

  void reset() {
    favouriteRestaurant.value = true;
    favouriteList.value = [];
    favouriteVendorList.value = [];
    favouriteItemList.value = [];
    favouriteFoodList.value = [];
    foodVendorCache.clear();
    isLoading.value = true;
  }
}
