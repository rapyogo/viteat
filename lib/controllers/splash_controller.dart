import 'package:customer/services/location_service.dart';
import 'dart:async';
import 'dart:developer';
import 'package:customer/app/auth_screen/login_screen.dart';
import 'package:customer/app/dash_board_screens/dash_board_screen.dart';
import 'package:customer/app/help_support_screen/help_support_screen.dart';
import 'package:customer/app/location_permission_screen/location_permission_screen.dart';
import 'package:customer/app/maintenance_mode_screen/maintenance_mode_screen.dart';
import 'package:customer/app/on_boarding_screen.dart';
import 'package:customer/constant/constant.dart';
import 'package:customer/models/user_model.dart';
import 'package:customer/services/connectivity_service.dart';
import 'package:customer/utils/fire_store_utils.dart';
import 'package:customer/utils/notification_service.dart';
import 'package:customer/utils/preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

class SplashController extends GetxController {
  @override
  void onInit() {
    // Pas de délai artificiel : on attend juste la 1ère frame avant de
    // naviguer (Get.offAll a besoin du Navigator déjà monté — appelé trop tôt
    // dans onInit(), quand _redirectScreen() résout très vite (cache Firestore
    // déjà chaud), la redirection échouait silencieusement et l'app restait
    // bloquée sur le splash). On n'impose plus 3s fixes pour autant.
    WidgetsBinding.instance.addPostFrameCallback((_) => redirectScreen());
    super.onInit();
  }

  Future<void> redirectScreen({int retryCount = 0}) async {
    try {
      await _redirectScreen();
    } catch (e) {
      log("SplashController.redirectScreen error :: $e");

      // Le device peut se croire "en ligne" (connectivity_plus voit du signal)
      // alors que le backend Firestore est injoignable/lent (10s+ de timeout) —
      // c'est le cas réel le plus fréquent, pas seulement le mode avion.
      final bool deviceOffline = Get.isRegistered<ConnectivityService>() && Get.find<ConnectivityService>().isOffline;
      final bool transientBackendError = e is FirebaseException && const {'unavailable', 'deadline-exceeded', 'network-request-failed', 'cancelled'}.contains(e.code);
      final bool hasLocalSession = FirebaseAuth.instance.currentUser != null;

      if ((deviceOffline || transientBackendError) && hasLocalSession) {
        // Session Firebase Auth déjà persistée localement — ne pas renvoyer
        // vers le login pour un simple problème réseau, l'app fonctionnera
        // en mode cache une fois sur le dashboard.
        Get.offAll(const DashBoardScreen());
        return;
      }

      if (retryCount < 1) {
        // Transient Firestore/network failure right at startup (e.g. connectivity
        // not fully up yet) — retry once instead of leaving the splash stuck forever.
        await Future.delayed(const Duration(seconds: 2));
        await redirectScreen(retryCount: retryCount + 1);
      } else {
        Get.offAll(const LoginScreen());
      }
    }
  }

  Future<void> _redirectScreen() async {
    // isMaintenanceMode() et isLogin() sont indépendants — seule la logique de
    // branchement ci-dessous dépend de leurs résultats, pas leur exécution.
    final List<bool> results = await Future.wait([
      FireStoreUtils.isMaintenanceMode(),
      FireStoreUtils.isLogin(),
    ]);
    final bool maintenanceMode = results[0];
    final bool isLoginResult = results[1];

    if (maintenanceMode == true) {
      Get.offAll(() => MaintenanceModeScreen());
      return;
    } else {
      if (Preferences.getBoolean(Preferences.isClickOnNotification) != true) {
        if (Preferences.getBoolean(Preferences.isFinishOnBoardingKey) == false) {
          Get.offAll(const OnBoardingScreen());
        } else {
          bool isLogin = isLoginResult;
          if (isLogin == true) {
            await FireStoreUtils.getUserProfile(FireStoreUtils.getCurrentUid()).then((value) async {
              if (value != null) {
                UserModel userModel = value;
                // userModel.shippingAddress?[0].location = UserLocation(latitude: 23.8500, longitude: 72.1210);
                log(userModel.toJson().toString());
                if (userModel.role == Constant.userRoleCustomer) {
                  if (userModel.active == true) {
                    try {
                      // Le token FCM est secondaire : s'il échoue (hors-ligne,
                      // service Messaging indisponible...), ça ne doit jamais
                      // faire échouer toute la redirection vers le dashboard —
                      // avant ce try/catch, une erreur ici remontait jusqu'au
                      // catch de redirectScreen() sans forcément matcher son
                      // filtre "erreur réseau connue", et l'utilisateur
                      // retombait sur l'écran de connexion au lieu du cache.
                      userModel.fcmToken = await NotificationService.getToken();
                    } catch (e) {
                      log("SplashController: échec récupération token FCM (ignoré) :: $e");
                    }
                    // Pas d'await : le rafraîchissement du token FCM ne doit pas
                    // retarder la navigation vers le dashboard à chaque lancement.
                    FireStoreUtils.updateUser(userModel);
                    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
                    if (initialMessage != null && initialMessage.data['type'] != null) {
                    } else if (userModel.shippingAddress != null && userModel.shippingAddress!.isNotEmpty) {
                      if (userModel.shippingAddress!.where((element) => element.isDefault == true).isNotEmpty) {
                        Constant.selectedLocation = userModel.shippingAddress!.where((element) => element.isDefault == true).single;
                      } else {
                        Constant.selectedLocation = userModel.shippingAddress!.first;
                      }
                      Get.offAll(const DashBoardScreen());
                    } else {
                      Get.offAll(const LocationPermissionScreen());
                    }
                  } else {
                    await LocationService.clear();
                    await FirebaseAuth.instance.signOut();
                    Get.offAll(const LoginScreen());
                  }
                } else {
                  await LocationService.clear();
                  await FirebaseAuth.instance.signOut();
                  Get.offAll(const LoginScreen());
                }
              } else {
                // getUserProfile() avale ses erreurs et renvoie null aussi bien
                // pour "profil absent" que pour "lecture impossible" (hors-ligne,
                // pas encore de cache pour ce document). On ne peut pas distinguer
                // les deux ici, donc on relance une erreur : le catch de
                // redirectScreen() sait déjà faire la bonne chose (rester sur le
                // dashboard si l'utilisateur a une session locale et est hors-ligne)
                // plutôt que de laisser le splash bloqué indéfiniment.
                throw Exception("User profile unavailable (offline or missing document)");
              }
            });
          } else {
            await LocationService.clear();
            await FirebaseAuth.instance.signOut();
            Get.offAll(const LoginScreen());
          }
        }
      } else {
        Get.to(HelpSupportScreen(isNavigateViaNotification: true));
      }
    }
  }

  // Future<void> handleMessageClick({required String type, required String role, required bool isBgApp}) async {
  //   final String uid = FireStoreUtils.getCurrentUid();
  //   if (type == 'admin_chat' && uid.isNotEmpty) {
  //     await Preferences.setBoolean(Preferences.isClickOnNotification, true);
  //     if (isBgApp == false) {
  //       Get.offAll(HelpSupportScreen(isNavigateViaNotification: true));
  //     }
  //   } else if (type == 'orderChat') {
  //     DashBoardController dashBoardScreen = Get.put(DashBoardController());
  //     dashBoardScreen.selectedIndex.value = 4;
  //     Get.offAll(DashBoardScreen());
  //     if (role == Constant.userRoleVendor) {
  //       Get.to(RestaurantInboxScreen());
  //     } else {
  //       Get.to(DriverInboxScreen());
  //     }
  //   }
  // }
}
