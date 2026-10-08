import 'package:customer/constant/constant.dart';
import 'package:customer/models/user_model.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:customer/utils/fire_store_utils.dart';
import 'package:customer/utils/notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

class GlobalSettingController extends GetxController {
  @override
  void onInit() {
    notificationInit();
    getCurrentCurrency();
    super.onInit();
  }

  Future<void> getCurrentCurrency() async {
    await FireStoreUtils.getSettings();
  }

  NotificationService notificationService = NotificationService();

  void notificationInit() {
    notificationService.initInfo();
    // Le jeton est deja synchronise par le splash (une fois, s'il a change) ;
    // ici on ne suit que son renouvellement, sans relire le profil.
    FirebaseMessaging.instance.onTokenRefresh.listen((_) {
      final UserModel? user = Constant.userModel;
      if (user != null && FirebaseAuth.instance.currentUser != null) {
        FireStoreUtils.syncFcmToken(user);
      }
    });
  }
}
