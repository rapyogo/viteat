import 'package:customer/services/location_service.dart';
import 'package:customer/constant/constant.dart';
import 'package:customer/constant/show_toast_dialog.dart';
import 'package:geolocator/geolocator.dart';
import 'package:map_launcher/map_launcher.dart';

class Utils {
  /// Conserve en delegation le temps que les appelants migrent : cette version
  /// n'avait aucun timeout (l'attente GPS pouvait ne jamais aboutir en
  /// interieur) et levait sur permission refusee definitivement, la ou
  /// rawPosition() rend simplement null.
  @Deprecated('Utiliser LocationService.to.rawPosition()')
  static Future<Position?> getCurrentLocation() async {
    return LocationService.to.rawPosition();
  }

  static redirectMap({required String name, required double latitude, required double longLatitude}) async {
    if (Constant.mapType == "google") {
      bool? isAvailable = await MapLauncher.isMapAvailable(MapType.google);
      if (isAvailable == true) {
        await MapLauncher.showDirections(
          mapType: MapType.google,
          directionsMode: DirectionsMode.driving,
          destinationTitle: name,
          destination: Coords(latitude, longLatitude),
        );
      } else {
        ShowToastDialog.showToast("Google map is not installed");
      }
    } else if (Constant.mapType == "googleGo") {
      bool? isAvailable = await MapLauncher.isMapAvailable(MapType.googleGo);
      if (isAvailable == true) {
        await MapLauncher.showDirections(
          mapType: MapType.googleGo,
          directionsMode: DirectionsMode.driving,
          destinationTitle: name,
          destination: Coords(latitude, longLatitude),
        );
      } else {
        ShowToastDialog.showToast("Google Go map is not installed");
      }
    } else if (Constant.mapType == "waze") {
      bool? isAvailable = await MapLauncher.isMapAvailable(MapType.waze);
      if (isAvailable == true) {
        await MapLauncher.showDirections(
          mapType: MapType.waze,
          directionsMode: DirectionsMode.driving,
          destinationTitle: name,
          destination: Coords(latitude, longLatitude),
        );
      } else {
        ShowToastDialog.showToast("Waze is not installed");
      }
    } else if (Constant.mapType == "mapswithme") {
      bool? isAvailable = await MapLauncher.isMapAvailable(MapType.mapswithme);
      if (isAvailable == true) {
        await MapLauncher.showDirections(
          mapType: MapType.mapswithme,
          directionsMode: DirectionsMode.driving,
          destinationTitle: name,
          destination: Coords(latitude, longLatitude),
        );
      } else {
        ShowToastDialog.showToast("Mapswithme is not installed");
      }
    } else if (Constant.mapType == "yandexNavi") {
      bool? isAvailable = await MapLauncher.isMapAvailable(MapType.yandexNavi);
      if (isAvailable == true) {
        await MapLauncher.showDirections(
          mapType: MapType.yandexNavi,
          directionsMode: DirectionsMode.driving,
          destinationTitle: name,
          destination: Coords(latitude, longLatitude),
        );
      } else {
        ShowToastDialog.showToast("YandexNavi is not installed");
      }
    } else if (Constant.mapType == "yandexMaps") {
      bool? isAvailable = await MapLauncher.isMapAvailable(MapType.yandexMaps);
      if (isAvailable == true) {
        await MapLauncher.showDirections(
          mapType: MapType.yandexMaps,
          directionsMode: DirectionsMode.driving,
          destinationTitle: name,
          destination: Coords(latitude, longLatitude),
        );
      } else {
        ShowToastDialog.showToast("yandexMaps map is not installed");
      }
    }
  }
}
