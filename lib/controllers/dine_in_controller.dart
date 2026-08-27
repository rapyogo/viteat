import 'package:customer/services/location_service.dart';
import 'dart:async';

import 'package:customer/constant/constant.dart';
import 'package:customer/models/BannerModel.dart';
import 'package:customer/models/favourite_model.dart';
import 'package:customer/models/vendor_category_model.dart';
import 'package:customer/models/vendor_model.dart';
import 'package:customer/utils/fire_store_utils.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';

class DineInController extends GetxController {
  RxBool isLoading = true.obs;
  RxBool isPopular = true.obs;

  @override
  void onInit() {
    getCategory();
    getData();
    // TODO: implement onInit
    super.onInit();
  }

  StreamSubscription<List<VendorModel>>? _restaurantSubscription;

  @override
  void onClose() {
    _restaurantSubscription?.cancel();
    super.onClose();
  }

  RxList<VendorCategoryModel> vendorCategoryModel = <VendorCategoryModel>[].obs;

  RxList<VendorModel> allNearestRestaurant = <VendorModel>[].obs;
  RxList<VendorModel> newArrivalRestaurantList = <VendorModel>[].obs;
  RxList<VendorModel> popularRestaurantList = <VendorModel>[].obs;

  RxList<BannerModel> bannerBottomModel = <BannerModel>[].obs;
  Rx<PageController> pageBottomController = PageController(viewportFraction: 0.877).obs;
  RxInt currentBottomPage = 0.obs;

  RxList<FavouriteModel> favouriteList = <FavouriteModel>[].obs;

  Future<void> getData() async {
    isLoading.value = true;
    await getZone();
    _restaurantSubscription?.cancel();
    _restaurantSubscription = FireStoreUtils.getAllNearestRestaurant(isDining: true).listen((event) async {
      newArrivalRestaurantList.clear();
      allNearestRestaurant.clear();
      popularRestaurantList.clear();
      popularRestaurantList.addAll(event);
      event.sort((a, b) {
        final aOpen = Constant.statusCheckOpenORClose(vendorModel: a);
        final bOpen = Constant.statusCheckOpenORClose(vendorModel: b);
        if (aOpen == bOpen) return 0;
        return aOpen ? -1 : 1;
      });
      allNearestRestaurant.addAll(event);
      newArrivalRestaurantList.addAll(event);

      popularRestaurantList.sort(
        (a, b) => Constant.calculateReview(reviewCount: b.reviewsCount.toString(), reviewSum: b.reviewsSum.toString())
            .compareTo(Constant.calculateReview(reviewCount: a.reviewsCount.toString(), reviewSum: a.reviewsSum.toString())),
      );
    });

    update();
    isLoading.value = false;
  }

  Future<void> getCategory() async {
    // Les 3 lectures ci-dessous sont indépendantes — lancées en parallèle.
    final List<Future<void>> tasks = [
      FireStoreUtils.getHomeVendorCategory().then((value) => vendorCategoryModel.value = value),
      FireStoreUtils.getHomeBottomBanner().then((value) => bannerBottomModel.value = value),
    ];
    if (Constant.userModel != null) {
      tasks.add(FireStoreUtils.getFavouriteRestaurant().then((value) => favouriteList.value = value));
    }
    await Future.wait(tasks);
  }

  Future<void> getZone() => LocationService.refreshZone();
}
