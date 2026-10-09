import 'package:customer/services/location_service.dart';
import 'dart:async';
import 'dart:developer';

import 'package:customer/constant/constant.dart';
import 'package:customer/models/vendor_category_model.dart';
import 'package:customer/models/vendor_model.dart';
import 'package:customer/data/vendor_repository.dart';
import 'package:get/get.dart';

class CategoryRestaurantController extends GetxController {
  RxBool isLoading = true.obs;
  RxBool dineIn = true.obs;

  @override
  void onInit() {
    // TODO: implement onInit
    getArgument();
    super.onInit();
  }

  StreamSubscription<List<VendorModel>>? _restaurantSubscription;

  @override
  void onClose() {
    _restaurantSubscription?.cancel();
    super.onClose();
  }

  Rx<VendorCategoryModel> vendorCategoryModel = VendorCategoryModel().obs;
  RxList<VendorModel> allNearestRestaurant = <VendorModel>[].obs;

  getArgument() async {
    dynamic argumentData = Get.arguments;
    if (argumentData != null) {
      vendorCategoryModel.value = argumentData['vendorCategoryModel'];
      dineIn.value = argumentData['dineIn'];
      await getZone();
      await getRestaurant();
    } else {
      isLoading.value = false;
    }
    // Plus de spinner force d'1 s : le chargement s'arrete a la premiere
    // reponse du flux (voir getRestaurant).
  }

  Future getRestaurant() async {
    log("::::::::::GetRestaurant::::::::::::::");
    _restaurantSubscription?.cancel();
    _restaurantSubscription = VendorRepository.instance.watchNearby(categoryId: vendorCategoryModel.value.id.toString(), dineIn: dineIn.value).listen((event) async {
      allNearestRestaurant.clear();
      event.sort((a, b) {
        final aOpen = Constant.statusCheckOpenORClose(vendorModel: a);
        final bOpen = Constant.statusCheckOpenORClose(vendorModel: b);
        if (aOpen == bOpen) return 0;
        return aOpen ? -1 : 1;
      });
      allNearestRestaurant.addAll(event);
      isLoading.value = false;
      for (var store in allNearestRestaurant) {
        final storeData = Constant.statusCheckOpenORClose(vendorModel: store);
        log("storeData :: ${allNearestRestaurant.indexOf(store)} :: ${store.title} :: $storeData");
      }
    });
  }

  Future<void> getZone() => LocationService.refreshZone();
}
