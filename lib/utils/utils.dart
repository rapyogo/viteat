import 'package:customer/services/location_service.dart';
import 'package:customer/constant/constant.dart';
import 'package:customer/constant/show_toast_dialog.dart';
import 'package:geolocator/geolocator.dart';
import 'package:map_launcher/map_launcher.dart' as map_launcher;

class Utils {
  /// Conserve en delegation le temps que les appelants migrent : cette version
  /// n'avait aucun timeout (l'attente GPS pouvait ne jamais aboutir en
  /// interieur) et levait sur permission refusee definitivement, la ou
  /// rawPosition() rend simplement null.
  @Deprecated('Utiliser LocationService.to.rawPosition()')
  static Future<Position?> getCurrentLocation() async {
    return LocationService.to.rawPosition();
  }

  /// Ouvre l'itineraire dans l'application de cartes choisie par l'admin
  /// (`Constant.mapType`). API map_launcher 6 (MapApp/TravelMode), reprise de Foodie 9.2.
  static redirectMap({required String name, required double latitude, required double longLatitude}) async {
    const Map<String, (map_launcher.MapApp, String)> supported = {
      "google": (map_launcher.MapApp.google, "Google map"),
      "googleGo": (map_launcher.MapApp.googleGo, "Google Go map"),
      "waze": (map_launcher.MapApp.waze, "Waze"),
      "mapswithme": (map_launcher.MapApp.mapswithme, "Mapswithme"),
      "yandexNavi": (map_launcher.MapApp.yandexNavi, "YandexNavi"),
      "yandexMaps": (map_launcher.MapApp.yandexMaps, "yandexMaps map"),
    };

    final entry = supported[Constant.mapType];
    if (entry == null) return;
    final (mapApp, label) = entry;

    final request = map_launcher.MapLauncher.directions(
      map_launcher.Location.coords(latitude, longLatitude, title: name),
      mode: map_launcher.TravelMode.driving,
    );

    final available = await request.getSupportedMaps([mapApp]);
    if (available.isEmpty) {
      ShowToastDialog.showToast("$label is not installed");
      return;
    }
    await request.show(map: mapApp);
  }
}
