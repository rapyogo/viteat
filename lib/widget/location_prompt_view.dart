import 'package:customer/app/address_screens/address_list_screen.dart';
import 'package:customer/constant/constant.dart';
import 'package:customer/constant/show_toast_dialog.dart';
import 'package:customer/models/user_model.dart';
import 'package:customer/services/location_service.dart';
import 'package:customer/themes/app_them_data.dart';
import 'package:customer/themes/round_button_fill.dart';
import 'package:customer/utils/dark_theme_provider.dart';
import 'package:customer/widget/location_failure_sheet.dart';
import 'package:customer/widget/location_picker_flow.dart';
import 'package:customer/widget/translated_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

/// Etat affiche quand la localisation n'a pas encore ete resolue.
///
/// Jusqu'ici ce cas etait confondu avec "aucun restaurant dans votre zone" :
/// deux problemes distincts, avec des solutions distinctes, presentes avec le
/// meme message. Un utilisateur sans localisation se voyait dire que sa zone
/// n'etait pas couverte, et le bouton propose ("Change Zone") ne nommait pas
/// le vrai probleme.
class LocationPromptView extends StatelessWidget {
  /// Appele une fois la localisation definie — typiquement controller.getData(),
  /// qui recalcule la zone puis relance l'ecoute des restaurants.
  final VoidCallback? onLocationSet;

  const LocationPromptView({super.key, this.onLocationSet});

  Future<void> _useCurrentLocation(BuildContext context) async {
    ShowToastDialog.showLoader("Please wait".tr);
    final LocationResult result = await LocationService.to.resolveFromGps();
    ShowToastDialog.closeLoader();

    if (result.isSuccess) {
      LocationService.setLocation(result.address!, source: LocationSource.gps);
      onLocationSet?.call();
      return;
    }
    if (!context.mounted) return;
    await showLocationFailureSheet(
      context,
      failure: result.failure!,
      onRetry: () => _useCurrentLocation(context),
      onPickOnMap: _pickOnMap,
      onEnterAddress: _enterAddress,
    );
  }

  Future<void> _pickOnMap() async {
    if (await pickLocationOnMap()) onLocationSet?.call();
  }

  Future<void> _enterAddress() async {
    final dynamic value = await Get.to(const AddressListScreen());
    if (value == null) return;
    LocationService.setLocation(value as ShippingAddress, source: LocationSource.manual);
    onLocationSet?.call();
  }

  @override
  Widget build(BuildContext context) {
    final themeChange = Provider.of<DarkThemeProvider>(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            "assets/images/location.gif",
            height: 120,
          ),
          const SizedBox(height: 12),
          TranslatedText(
            "Where should we deliver?",
            textAlign: TextAlign.center,
            style: TextStyle(color: themeChange.getThem() ? AppThemeData.grey100 : AppThemeData.grey800, fontSize: 22, fontFamily: AppThemeData.semiBold),
          ),
          const SizedBox(height: 5),
          TranslatedText(
            "We need your position to show you the restaurants closest to you.",
            textAlign: TextAlign.center,
            style: TextStyle(color: themeChange.getThem() ? AppThemeData.grey50 : AppThemeData.grey500, fontSize: 16, fontFamily: AppThemeData.bold),
          ),
          const SizedBox(height: 20),
          RoundedButtonFill(
            title: "Use my position",
            width: 70,
            height: 5.5,
            color: AppThemeData.primary300,
            textColor: AppThemeData.grey50,
            onPress: () => _useCurrentLocation(context),
          ),
          const SizedBox(height: 10),
          RoundedButtonFill(
            title: "Pick on map",
            width: 70,
            height: 5.5,
            color: themeChange.getThem() ? AppThemeData.grey800 : AppThemeData.grey100,
            textColor: themeChange.getThem() ? AppThemeData.grey50 : AppThemeData.grey900,
            onPress: _pickOnMap,
          ),
          // La liste d'adresses n'existe que sur un profil : inutile de la
          // proposer a un invite (meme regle qu'au LocationPermissionScreen).
          if (Constant.userModel != null) ...[
            const SizedBox(height: 10),
            RoundedButtonFill(
              title: "Enter an address",
              width: 70,
              height: 5.5,
              color: themeChange.getThem() ? AppThemeData.grey800 : AppThemeData.grey100,
              textColor: themeChange.getThem() ? AppThemeData.grey50 : AppThemeData.grey900,
              onPress: _enterAddress,
            ),
          ],
        ],
      ),
    );
  }
}
