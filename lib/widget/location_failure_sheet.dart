import 'package:customer/constant/constant.dart';
import 'package:customer/services/location_service.dart';
import 'package:customer/themes/app_them_data.dart';
import 'package:customer/themes/round_button_fill.dart';
import 'package:customer/utils/dark_theme_provider.dart';
import 'package:customer/widget/translated_text.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

/// Affiche pourquoi la localisation n'a pas pu etre obtenue, et ce que
/// l'utilisateur peut faire — au lieu de lui substituer silencieusement une
/// coordonnee par defaut, ce que faisaient les anciens blocs catch.
///
/// Un seul endroit a maintenir pour les 5 sites d'acquisition.
Future<void> showLocationFailureSheet(
  BuildContext context, {
  required LocationFailure failure,
  Future<void> Function()? onRetry,
  Future<void> Function()? onPickOnMap,
  Future<void> Function()? onEnterAddress,
}) {
  final themeChange = Provider.of<DarkThemeProvider>(context, listen: false);

  final String title;
  final String message;
  switch (failure) {
    case LocationFailure.serviceDisabled:
      title = 'Location is turned off';
      message = 'Turn on your phone location, or enter your address manually.';
      break;
    case LocationFailure.permissionDenied:
      title = 'Location permission denied';
      message = 'Viteat needs your position to find the restaurants closest to you.';
      break;
    case LocationFailure.permissionDeniedForever:
      title = 'Location permission blocked';
      message = 'Allow location access in your phone settings to continue.';
      break;
    case LocationFailure.timeout:
    case LocationFailure.unknown:
      title = 'Position not found';
      message = 'The GPS signal is too weak here. Pick your position on the map instead.';
      break;
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
    clipBehavior: Clip.antiAliasWithSaveLayer,
    backgroundColor: themeChange.getThem() ? AppThemeData.grey900 : AppThemeData.grey50,
    builder: (BuildContext sheetContext) {
      // Action principale, propre a chaque cause : elle envoie l'utilisateur la
      // ou le probleme se resout reellement (reglages systeme, permission,
      // carte) plutot que de lui demander de reessayer a l'aveugle.
      final List<Widget> actions = <Widget>[];

      void addAction(String label, Future<void> Function() action, {bool primary = true}) {
        actions.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: RoundedButtonFill(
            title: label,
            color: primary ? AppThemeData.primary300 : (themeChange.getThem() ? AppThemeData.grey800 : AppThemeData.grey100),
            textColor: primary ? AppThemeData.grey50 : (themeChange.getThem() ? AppThemeData.grey50 : AppThemeData.grey900),
            onPress: () async {
              Navigator.pop(sheetContext);
              await action();
            },
          ),
        ));
      }

      switch (failure) {
        case LocationFailure.serviceDisabled:
          addAction('Turn on location', () => Geolocator.openLocationSettings());
          break;
        case LocationFailure.permissionDenied:
          if (onRetry != null) addAction('Allow location', onRetry);
          break;
        case LocationFailure.permissionDeniedForever:
          addAction('Open settings', () => Geolocator.openAppSettings());
          break;
        case LocationFailure.timeout:
        case LocationFailure.unknown:
          if (onRetry != null) addAction('Try again', onRetry);
          break;
      }

      if (onPickOnMap != null) {
        addAction('Pick on map', onPickOnMap, primary: actions.isEmpty);
      }
      // Saisie manuelle reservee aux comptes connectes : la liste d'adresses
      // n'existe que sur un profil (meme regle qu'au LocationPermissionScreen).
      if (onEnterAddress != null && Constant.userModel != null) {
        addAction('Enter an address', onEnterAddress, primary: false);
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 134,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: ShapeDecoration(
                    color: themeChange.getThem() ? AppThemeData.grey50 : AppThemeData.grey800,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                  ),
                ),
              ),
              Icon(Icons.location_off_outlined, size: 48, color: AppThemeData.primary300),
              const SizedBox(height: 16),
              TranslatedText(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontFamily: AppThemeData.semiBold,
                  color: themeChange.getThem() ? AppThemeData.grey50 : AppThemeData.grey900,
                ),
              ),
              const SizedBox(height: 8),
              TranslatedText(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: AppThemeData.regular,
                  color: themeChange.getThem() ? AppThemeData.grey300 : AppThemeData.grey600,
                ),
              ),
              const SizedBox(height: 24),
              ...actions,
            ],
          ),
        ),
      );
    },
  );
}
