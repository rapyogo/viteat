import 'dart:async';

import 'package:customer/models/vendor_model.dart';
import 'package:customer/data/vendor_repository.dart';
import 'package:get/get.dart';

class ScanQrCodeController extends GetxController {
  @override
  void onInit() {
    // TODO: implement onInit
    getData();
    super.onInit();
  }

  RxList<VendorModel> allNearestRestaurant = <VendorModel>[].obs;

  StreamSubscription<List<VendorModel>>? _restaurantSubscription;

  getData() {
    _restaurantSubscription?.cancel();
    _restaurantSubscription = VendorRepository.instance.watchNearby().listen((event) {
      allNearestRestaurant.assignAll(event);
    });
  }

  @override
  void onClose() {
    _restaurantSubscription?.cancel();
    super.onClose();
  }
}
