import 'package:customer/models/user_model.dart';
import 'package:customer/utils/fire_store_utils.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';

class AddressListController extends GetxController {
  Rx<UserModel> userModel = UserModel().obs;

  RxList<ShippingAddress> shippingAddressList = <ShippingAddress>[].obs;

  List saveAsList = ['Home', 'Work', 'Hotel', 'other'].obs;
  RxString selectedSaveAs = "Home".obs;

  Rx<TextEditingController> houseBuildingTextEditingController = TextEditingController().obs;
  Rx<TextEditingController> localityEditingController = TextEditingController().obs;
  Rx<TextEditingController> landmarkEditingController = TextEditingController().obs;
  Rx<UserLocation> location = UserLocation().obs;
  Rx<ShippingAddress> shippingModel = ShippingAddress().obs;
  RxBool isLoading = false.obs;

  @override
  void onInit() {
    // TODO: implement onInit
    getUser();
    super.onInit();
  }

  clearData() {
    shippingModel.value = ShippingAddress();
    houseBuildingTextEditingController.value.clear();
    localityEditingController.value.clear();
    landmarkEditingController.value.clear();
    location.value = UserLocation();
    selectedSaveAs.value = "Home";
  }

  setData(ShippingAddress shippingAddress) {
    shippingModel.value = shippingAddress;
    // .toString() sur un String? null ecrivait litteralement "null" dans les
    // champs de saisie, et location! plantait a l'edition d'une adresse
    // enregistree sans coordonnees.
    houseBuildingTextEditingController.value.text = shippingAddress.address ?? '';
    localityEditingController.value.text = shippingAddress.locality ?? '';
    landmarkEditingController.value.text = shippingAddress.landmark ?? '';
    selectedSaveAs.value = shippingAddress.addressAs ?? "Home";
    location.value = shippingAddress.location ?? UserLocation();
  }

  getUser() async {
    await FireStoreUtils.getUserProfile(FireStoreUtils.getCurrentUid()).then(
      (value) {
        if (value != null) {
          userModel.value = value;
          if (userModel.value.shippingAddress != null) {
            shippingAddressList.value = userModel.value.shippingAddress!;
          }
        }
      },
    );
  }
}
