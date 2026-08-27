import 'package:customer/app/address_screens/address_list_screen.dart';
import 'package:customer/app/dash_board_screens/dash_board_screen.dart';
import 'package:customer/constant/constant.dart';
import 'package:customer/constant/show_toast_dialog.dart';
import 'package:customer/controllers/location_permission_controller.dart';
import 'package:customer/models/user_model.dart';
import 'package:customer/services/location_service.dart';
import 'package:customer/themes/app_them_data.dart';
import 'package:customer/themes/responsive.dart';
import 'package:customer/themes/round_button_fill.dart';
import 'package:customer/utils/dark_theme_provider.dart';
import 'package:customer/widget/location_failure_sheet.dart';
import 'package:customer/widget/location_picker_flow.dart';
import 'package:flutter/material.dart';
import 'package:customer/widget/translated_text.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

class LocationPermissionScreen extends StatelessWidget {
  const LocationPermissionScreen({super.key});

  /// GPS. En cas d'echec on ne renseigne AUCUNE localisation et on reste sur
  /// l'ecran : les deux autres boutons ci-dessous sont deja la sortie de
  /// secours. C'est ici que se trouvaient les coordonnees de Mumbai en dur.
  Future<void> _useCurrentLocation(BuildContext context) async {
    ShowToastDialog.showLoader("Please wait".tr);
    final LocationResult result = await LocationService.to.resolveFromGps();
    ShowToastDialog.closeLoader();

    if (result.isSuccess) {
      LocationService.setLocation(result.address!, source: LocationSource.gps);
      Get.offAll(const DashBoardScreen());
      return;
    }
    if (!context.mounted) return;
    await showLocationFailureSheet(
      context,
      failure: result.failure!,
      onRetry: () => _useCurrentLocation(context),
      onPickOnMap: () => _pickOnMap(context),
      onEnterAddress: _enterAddress,
    );
  }

  /// Choix manuel sur la carte. Aucune permission n'est requise pour ca — le
  /// picker demande lui-meme la position s'il peut, seulement pour centrer sa
  /// camera. L'ancien code appelait getCurrentPosition() ici et jetait le
  /// resultat, ce qui rendait tout l'appel faillible pour rien.
  /// Choix manuel sur la carte, via le flux partage avec les ecrans d'accueil.
  Future<void> _pickOnMap(BuildContext context) async {
    if (await pickLocationOnMap()) {
      Get.offAll(const DashBoardScreen());
    }
  }

  Future<void> _enterAddress() async {
    final dynamic value = await Get.to(const AddressListScreen());
    if (value == null) return;
    LocationService.setLocation(value as ShippingAddress, source: LocationSource.manual);
    Get.offAll(const DashBoardScreen());
  }

  @override
  Widget build(BuildContext context) {
    final themeChange = Provider.of<DarkThemeProvider>(context);
    return GetBuilder(
      init: LocationPermissionController(),
      builder: (controller) {
        return Scaffold(
          body: Container(
            height: Responsive.height(100, context),
            width: Responsive.width(100, context),
            decoration:
                BoxDecoration(image: DecorationImage(image: themeChange.getThem() ? AssetImage("assets/images/location_bg_dark.png") : AssetImage("assets/images/location_bg.png"), fit: BoxFit.cover)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 35),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TranslatedText(
                    "Enable Location Services 📍",
                    style: TextStyle(color: themeChange.getThem() ? AppThemeData.grey200 : AppThemeData.grey900, fontSize: 22, fontFamily: AppThemeData.semiBold),
                  ),
                  TranslatedText(
                    "To provide the best dining experience, allow Viteat to access your location.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: themeChange.getThem() ? AppThemeData.grey200 : AppThemeData.grey900, fontSize: 16, fontFamily: AppThemeData.bold),
                  ),
                  const SizedBox(
                    height: 32,
                  ),
                  RoundedButtonFill(
                    title: "Use Current Location",
                    color: AppThemeData.primary300,
                    textColor: AppThemeData.grey50,
                    onPress: () => _useCurrentLocation(context),
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  RoundedButtonFill(
                    title: "Set From Map",
                    color: AppThemeData.primary300,
                    textColor: AppThemeData.grey50,
                    icon: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: SvgPicture.asset(
                        "assets/icons/ic_location_pin.svg",
                        colorFilter: const ColorFilter.mode(AppThemeData.grey50, BlendMode.srcIn),
                      ),
                    ),
                    isRight: false,
                    onPress: () => _pickOnMap(context),
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  Constant.userModel == null
                      ? const SizedBox()
                      : RoundedButtonFill(
                          title: "Enter Manually location",
                          color: AppThemeData.primary300,
                          textColor: AppThemeData.grey50,
                          isRight: false,
                          onPress: _enterAddress,
                        ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
