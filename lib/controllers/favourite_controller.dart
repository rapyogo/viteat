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

  @override
  void onInit() {
    // TODO: implement onInit

    super.onInit();
    getData();
  }

  Future<void> getData() async {
    reset();
    if (Constant.userModel != null) {
      // getFavouriteRestaurant() et getFavouriteItem() sont indépendants.
      final List<dynamic> baseLists = await Future.wait([
        FireStoreUtils.getFavouriteRestaurant(),
        FireStoreUtils.getFavouriteItem(),
      ]);
      favouriteList.value = baseLists[0] as List<FavouriteModel>;
      favouriteItemList.value = baseLists[1] as List<FavouriteItemModel>;

      // Un getVendorById() par favori, mais lancés en parallèle plutôt qu'en
      // séquence (N allers-retours l'un après l'autre auparavant).
      final List<VendorModel?> vendorResults = await Future.wait(
        favouriteList.map((element) => FireStoreUtils.getVendorById(element.restaurantId.toString())),
      );
      List<VendorModel> favouriteVendorData = [];
      for (final value in vendorResults) {
        if (value != null) {
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
      favouriteVendorList.value = favouriteVendorData;

      // Idem pour les articles favoris : chaque résolution (produit puis,
      // si nécessaire, son vendeur) tourne en parallèle des autres.
      final List<ProductModel?> foodResults = await Future.wait(
        favouriteItemList.map((element) => _resolveFavouriteFood(element)),
      );
      favouriteFoodList.addAll(foodResults.whereType<ProductModel>());
    }
    List<ProductModel> favouriteFoodData = favouriteFoodList;
    List<VendorModel> favouriteVendorData = favouriteVendorList;
    favouriteFoodList.value = removeDuplicateFoods(favouriteFoodData);
    favouriteVendorList.value = removeDuplicateVendor(favouriteVendorData);
    await _loadFoodVendorCache();
    isLoading.value = false;
  }

  Future<void> _loadFoodVendorCache() async {
    final List<String> vendorIds = favouriteFoodList.map((p) => p.vendorID).whereType<String>().toSet().where((id) => !foodVendorCache.containsKey(id)).toList();
    if (vendorIds.isEmpty) return;
    final List<VendorModel?> results = await Future.wait(vendorIds.map((id) => FireStoreUtils.getVendorById(id)));
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
