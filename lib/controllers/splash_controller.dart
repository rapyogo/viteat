import 'package:customer/services/location_service.dart';
import 'dart:async';
import 'dart:developer';
import 'package:customer/app/auth_screen/login_screen.dart';
import 'package:customer/app/dash_board_screens/dash_board_screen.dart';
import 'package:customer/app/force_update_screen/force_update_screen.dart';
import 'package:customer/app/help_support_screen/help_support_screen.dart';
import 'package:customer/app/location_permission_screen/location_permission_screen.dart';
import 'package:customer/app/maintenance_mode_screen/maintenance_mode_screen.dart';
import 'package:customer/app/on_boarding_screen.dart';
import 'package:customer/constant/constant.dart';
import 'package:customer/models/user_model.dart';
import 'package:customer/services/connectivity_service.dart';
import 'package:customer/utils/fire_store_utils.dart';
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

  /// Au demarrage a froid, la session Firebase persistee n'est pas forcement
  /// restauree a la premiere frame (constate hors ligne : currentUser nul, puis
  /// la session revient). Decider avant envoyait au login un utilisateur
  /// toujours connecte. Le premier evenement d'authStateChanges() donne l'etat
  /// restaure ; delai maximal pour ne jamais bloquer le splash.
  Future<void> _waitForAuthRestore() async {
    if (FirebaseAuth.instance.currentUser != null) return;
    try {
      await FirebaseAuth.instance.authStateChanges().first.timeout(const Duration(seconds: 4));
    } catch (_) {
      // Delai depasse : on garde l'etat courant.
    }
    debugPrint("SplashController: session restauree = ${FirebaseAuth.instance.currentUser != null}");
  }

  Future<void> redirectScreen({int retryCount = 0}) async {
    if (retryCount == 0) await _waitForAuthRestore();
    try {
      await _redirectScreen();
    } catch (e) {
      log("SplashController.redirectScreen error :: $e");
      debugPrint("SplashController.redirectScreen error :: $e");

      // Une session Firebase Auth persistee localement fait foi. Tant qu'elle
      // existe, un echec de LECTURE ne doit JAMAIS renvoyer au login : on ne
      // sait pas distinguer "compte supprime" de "pas pu verifier", et se
      // tromper deconnecte un utilisateur parfaitement valide.
      //
      // Les vraies deconnexions (compte inactif, mauvais role) passent par le
      // chemin nominal de _redirectScreen(), qui appelle signOut() explicitement
      // sur une reponse serveur — jamais par ce catch.
      final bool hasLocalSession = FirebaseAuth.instance.currentUser != null;
      if (!hasLocalSession) {
        debugPrint("SESSION: erreur splash sans session locale -> login ($e)");
        Get.offAll(const LoginScreen());
        return;
      }

      // Le device peut se croire "en ligne" (connectivity_plus voit du signal)
      // alors que le backend Firestore est injoignable/lent (10s+ de timeout) —
      // c'est le cas reel le plus frequent, pas seulement le mode avion.
      final bool deviceOffline = Get.isRegistered<ConnectivityService>() && Get.find<ConnectivityService>().isOffline;
      // getUserProfile() avale ses erreurs et _redirectScreen() relaie son echec
      // par une Exception nue : elle n'est donc pas une FirebaseException et ne
      // matchait aucun code connu. C'est ce trou qui renvoyait au login hors
      // ligne malgre une session valide.
      final bool transientBackendError = e is FirebaseException && const {'unavailable', 'deadline-exceeded', 'network-request-failed', 'cancelled'}.contains(e.code);

      if (deviceOffline || transientBackendError || retryCount >= 1) {
        // Hors ligne, erreur backend connue, ou deuxieme echec consecutif :
        // inutile d'insister. L'app fonctionne en mode cache sur le dashboard,
        // avec le profil du cache local (sinon l'accueil s'affichait comme pour
        // un invite). Le DashBoardController le recharge au retour du reseau.
        Constant.userModel ??= await FireStoreUtils.getUserProfileFromCache(FireStoreUtils.getCurrentUid());
        Get.offAll(const DashBoardScreen());
        return;
      }

      // Premier echec sans cause identifiee : laisser au reseau une chance de
      // s'etablir avant de conclure.
      await Future.delayed(const Duration(seconds: 2));
      await redirectScreen(retryCount: retryCount + 1);
    }
  }

  /// Le splash a ouvert l'app sur des donnees du cache local (profil,
  /// maintenance, version) : on les reverifie sur le serveur, sans bloquer.
  /// Un compte desactive, une maintenance ou une version trop ancienne
  /// produisent le meme effet qu'avant, quelques instants plus tard.
  ///
  /// Maintenance et mise a jour ne remplacent l'ecran que si l'utilisateur est
  /// sur un ecran racine : jamais au milieu d'un panier ou d'un paiement. La
  /// valeur serveur est alors dans le cache local et le prochain lancement
  /// l'applique (confirmee sur le serveur dans _redirectScreen).
  Future<void> _revalidateFromServer({required bool checkProfile}) async {
    try {
      final bool onRootScreen = const {'/DashBoardScreen', '/OnBoardingScreen', '/LoginScreen', '/LocationPermissionScreen'}.contains(Get.currentRoute);
      if (await FireStoreUtils.isMaintenanceMode()) {
        if (onRootScreen) Get.offAll(() => MaintenanceModeScreen());
        return;
      }
      final String? updateStoreUrl = await FireStoreUtils.requiredUpdateStoreUrl();
      if (updateStoreUrl != null) {
        if (onRootScreen) Get.offAll(() => ForceUpdateScreen(storeUrl: updateStoreUrl));
        return;
      }
      if (!checkProfile) return;
      final SessionProfile session = await FireStoreUtils.loadSessionProfile();
      final UserModel? fresh = session.profile;
      // Toujours hors ligne, ou reponse indeterminee (document absent du cache
      // hors ligne) : rien ne prouve que le compte a change, la session reste.
      if (session.fromCache || (session.loggedIn && fresh == null)) return;
      if (!session.loggedIn || fresh == null || fresh.role != Constant.userRoleCustomer || fresh.active != true) {
        if (FirebaseAuth.instance.currentUser == null) return;
        debugPrint("SESSION: deconnexion apres verification serveur (role=${fresh?.role}, actif=${fresh?.active})");
        await LocationService.clear();
        await FirebaseAuth.instance.signOut();
        Get.offAll(const LoginScreen());
        return;
      }
      Constant.userModel = fresh;
      unawaited(FireStoreUtils.syncFcmToken(fresh));
    } catch (e) {
      // Reseau indisponible : on garde la session et les donnees du cache.
      debugPrint("SplashController._revalidateFromServer :: $e");
    }
  }

  Future<void> _redirectScreen() async {
    // Maintenance, profil et version sont lus depuis le cache local quand il
    // existe : plus d'attente reseau au lancement. Ils sont reverifies sur le
    // serveur juste apres l'ouverture (_revalidateFromServer).
    final List<Object?> results = await Future.wait<Object?>([
      FireStoreUtils.isMaintenanceMode(preferCache: true),
      FireStoreUtils.loadSessionProfile(preferCache: true),
      FireStoreUtils.requiredUpdateStoreUrl(preferCache: true),
    ]);
    bool maintenanceMode = results[0] == true;
    final SessionProfile session = results[1] as SessionProfile;
    final bool isLoginResult = session.loggedIn;
    String? updateStoreUrl = results[2] as String?;

    // Un ecran bloquant n'est jamais affiche sur la seule foi du cache : une
    // maintenance levee ou une version minimale abaissee depuis par l'admin
    // bloquerait sinon l'utilisateur a chaque lancement (le cache ne serait
    // jamais rafraichi). Confirmation serveur, comme avant le lot 2.
    if (updateStoreUrl != null) updateStoreUrl = await FireStoreUtils.requiredUpdateStoreUrl();
    if (maintenanceMode) maintenanceMode = await FireStoreUtils.isMaintenanceMode();

    // Reverification serveur lancee APRES la navigation (fin de methode) :
    // lancee avant, un Get.offAll(Login/Maintenance) pouvait etre ecrase par le
    // Get.offAll(DashBoardScreen) qui suivait. null = pas de reverification.
    bool? revalidateProfile;

    final String? confirmedStoreUrl = updateStoreUrl;
    if (confirmedStoreUrl != null) {
      // Version trop ancienne (ex. sans filtre des restaurants hors ligne).
      Get.offAll(() => ForceUpdateScreen(storeUrl: confirmedStoreUrl));
      return;
    }
    if (maintenanceMode == true) {
      Get.offAll(() => MaintenanceModeScreen());
      return;
    } else {
      if (Preferences.getBoolean(Preferences.isClickOnNotification) != true) {
        if (Preferences.getBoolean(Preferences.isFinishOnBoardingKey) == false) {
          Get.offAll(const OnBoardingScreen());
          revalidateProfile = false;
        } else {
          bool isLogin = isLoginResult;
          if (isLogin == true) {
            await Future<UserModel?>.value(session.profile).then((value) async {
              if (value != null) {
                UserModel userModel = value;
                // userModel.shippingAddress?[0].location = UserLocation(latitude: 23.8500, longitude: 72.1210);
                log(userModel.toJson().toString());
                if (userModel.role == Constant.userRoleCustomer) {
                  if (userModel.active == true) {
                    // Jeton FCM synchronise en arriere-plan, et seulement s'il a
                    // change : la navigation n'attend plus getToken() et le
                    // profil complet n'est plus reecrit a chaque lancement.
                    // Profil courant en memoire : c'est lui qui alimente l'en-tete,
                    // le profil, les commandes. Avant, il etait rempli en effet de
                    // bord par updateUser() ; sans cette ligne l'app s'affichait
                    // comme pour un invite alors que la session etait valide.
                    Constant.userModel = userModel;
                    // Maintenance et version reverifiees sur le serveur dans tous
                    // les cas ; le profil seulement s'il venait du cache (il
                    // synchronise alors lui-meme le jeton FCM).
                    revalidateProfile = session.fromCache;
                    if (!session.fromCache) unawaited(FireStoreUtils.syncFcmToken(userModel));
                    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
                    if (initialMessage != null && initialMessage.data['type'] != null) {
                    } else if (userModel.shippingAddress != null && userModel.shippingAddress!.isNotEmpty) {
                      if (userModel.shippingAddress!.where((element) => element.isDefault == true).isNotEmpty) {
                        Constant.selectedLocation = userModel.shippingAddress!.where((element) => element.isDefault == true).single;
                      } else {
                        Constant.selectedLocation = userModel.shippingAddress!.first;
                      }
                      Get.offAll(const DashBoardScreen());
                    } else if (LocationService.isResolved) {
                      // Aucune adresse enregistree au profil, mais une
                      // localisation restauree depuis le cache local : c'est le
                      // cas de tous ceux qui n'utilisent que le GPS, qui
                      // repassaient sinon par l'ecran de permission a CHAQUE
                      // lancement alors qu'on connait deja leur position.
                      Get.offAll(const DashBoardScreen());
                    } else {
                      Get.offAll(const LocationPermissionScreen());
                    }
                  } else {
                    debugPrint("SESSION: deconnexion splash, compte inactif");
                    await LocationService.clear();
                    await FirebaseAuth.instance.signOut();
                    Get.offAll(const LoginScreen());
                  }
                } else {
                  debugPrint("SESSION: deconnexion splash, role=${userModel.role}");
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
            debugPrint("SESSION: isLogin=false (currentUser=${FirebaseAuth.instance.currentUser != null}), deconnexion splash");
            await LocationService.clear();
            await FirebaseAuth.instance.signOut();
            Get.offAll(const LoginScreen());
            revalidateProfile = false;
          }
        }
      } else {
        Get.to(HelpSupportScreen(isNavigateViaNotification: true));
        revalidateProfile = false;
      }
    }
    final bool? checkProfile = revalidateProfile;
    if (checkProfile != null) unawaited(_revalidateFromServer(checkProfile: checkProfile));
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
