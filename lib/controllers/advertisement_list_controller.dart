import 'dart:async';

import 'package:customer/constant/constant.dart';
import 'package:customer/models/advertisement_model.dart';
import 'package:customer/models/favourite_model.dart';
import 'package:customer/models/vendor_model.dart';
import 'package:customer/utils/fire_store_utils.dart';
import 'package:get/get.dart';

class AdvertisementListController extends GetxController {
  RxBool isLoading = true.obs;

  @override
  void onInit() {
    getAdvertisementList();
    getFavouriteRestaurant();
    super.onInit();
  }

  StreamSubscription<List<VendorModel>>? _restaurantSubscription;

  @override
  void onClose() {
    _restaurantSubscription?.cancel();
    super.onClose();
  }

  RxList<AdvertisementModel> advertisementList = <AdvertisementModel>[].obs;
  RxList<VendorModel> allNearestRestaurant = <VendorModel>[].obs;

  // allNearestRestaurant contient déjà les vendeurs pertinents (advertisementList
  // en est filtrée) — recherche synchrone au lieu d'un FutureBuilder qui
  // refetch à chaque rebuild de la liste.
  VendorModel? vendorById(String? id) => id == null ? null : allNearestRestaurant.firstWhereOrNull((v) => v.id == id);

  getAdvertisementList() async {
    advertisementList.clear();
    _restaurantSubscription?.cancel();
    _restaurantSubscription = FireStoreUtils.getAllNearestRestaurant().listen((event) async {
      allNearestRestaurant.addAll(event);
      await FireStoreUtils.getAllAdvertisement().then((value) {
        List<AdvertisementModel> adsList = value;
        advertisementList.addAll(
          adsList.where((ads) => allNearestRestaurant.any((restaurant) => restaurant.id == ads.vendorId)),
        );
      });
      isLoading.value = false;
    });
  }

  RxList<FavouriteModel> favouriteList = <FavouriteModel>[].obs;

  getFavouriteRestaurant() async {
    if (Constant.userModel != null) {
      await FireStoreUtils.getFavouriteRestaurant().then(
        (value) {
          favouriteList.value = value;
        },
      );
    }
  }
}
