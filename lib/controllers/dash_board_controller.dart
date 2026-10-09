import 'package:customer/app/favourite_screens/favourite_screen.dart';
import 'package:customer/app/home_screen/home_screen.dart';
import 'package:customer/app/home_screen/home_screen_two.dart';
import 'package:customer/app/order_list_screen/order_screen.dart';
import 'package:customer/app/profile_screen/profile_screen.dart';
import 'package:customer/app/wallet_screen/wallet_screen.dart';
import 'dart:async';

import 'package:customer/constant/constant.dart';
import 'package:customer/controllers/home_controller.dart';
import 'package:customer/controllers/order_controller.dart';
import 'package:customer/services/connectivity_service.dart';
import 'package:customer/utils/fire_store_utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

class DashBoardController extends GetxController {
  RxInt selectedIndex = 0.obs;

  RxList pageList = [].obs;

  /// Onglets deja ouverts (gardes montes dans l'IndexedStack du dashboard).
  final Set<int> visitedTabs = <int>{0};

  Worker? _connectivityWorker;
  Worker? _layoutWorker;

  /// Theme et wallet pour lesquels les onglets ont ete calcules.
  String? _layoutSignature;

  @override
  void onInit() {
    super.onInit();
    getInit();
    // L'onglet Commandes reste monte : on le rafraichit en arriere-plan quand on
    // y revient, au plus une fois par minute (pas de spinner, pas de relecture
    // systematique comme avant).
    ever<int>(selectedIndex, (index) {
      if (index < pageList.length && pageList[index] is OrderScreen && Get.isRegistered<OrderController>()) {
        unawaited(Get.find<OrderController>().refreshIfStale(const Duration(minutes: 1)));
      }
    });
    // Reglages arrives apres l'ouverture (premier lancement, ou changement de
    // theme par l'admin) : onglets recalcules seulement s'ils different.
    _layoutWorker = ever<int>(FireStoreUtils.layoutSettingsVersion, (_) {
      if (_currentLayoutSignature() != _layoutSignature) {
        // Les index des onglets changent (ex. onglet Wallet insere) : retour
        // sur l'accueil plutot que sur un onglet qui n'est plus le meme.
        getInit();
        selectedIndex.value = 0;
      }
    });
    if (Get.isRegistered<ConnectivityService>()) {
      _connectivityWorker = ever<SyncState>(Get.find<ConnectivityService>().state, (state) {
        if (state == SyncState.online) unawaited(refreshSessionData());
      });
    }
  }

  @override
  void onClose() {
    _connectivityWorker?.dispose();
    _layoutWorker?.dispose();
    super.onClose();
  }

  /// Retour du reseau : relit le profil (qui a pu manquer au demarrage hors
  /// ligne), puis rafraichit l'accueil et les commandes deja ouverts.
  Future<void> refreshSessionData() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    final profile = await FireStoreUtils.getUserProfile(FireStoreUtils.getCurrentUid());
    if (profile != null) Constant.userModel = profile;
    // L'accueil est un GetX : il se reconstruit sur un changement Rx, pas sur update().
    if (Get.isRegistered<HomeController>()) Get.find<HomeController>().isLoading.refresh();
    if (Get.isRegistered<OrderController>()) unawaited(Get.find<OrderController>().getOrder());
  }

  String _currentLayoutSignature() => '${Constant.theme}|${Constant.walletSetting}';

  Future<void> getInit() async {
    _layoutSignature = _currentLayoutSignature();
    // Nouvelle liste d'onglets (theme ou wallet differents) : les index changent.
    visitedTabs
      ..clear()
      ..add(0);
    if (Constant.theme == "theme_2") {
      if (Constant.walletSetting == false) {
        pageList.value = [
          const HomeScreen(),
          const FavouriteScreen(),
          const OrderScreen(),
          const ProfileScreen(),
        ];
      } else {
        pageList.value = [
          const HomeScreen(),
          const FavouriteScreen(),
          const WalletScreen(),
          const OrderScreen(),
          const ProfileScreen(),
        ];
      }
    } else {
      if (Constant.walletSetting == false) {
        pageList.value = [
          const HomeScreenTwo(),
          const FavouriteScreen(),
          const OrderScreen(),
          const ProfileScreen(),
        ];
      } else {
        pageList.value = [
          const HomeScreenTwo(),
          const FavouriteScreen(),
          const WalletScreen(),
          const OrderScreen(),
          const ProfileScreen(),
        ];
      }
    }
  }

  DateTime? currentBackPressTime;
  RxBool canPopNow = false.obs;
}
