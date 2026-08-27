import 'package:customer/constant/constant.dart';
import 'package:customer/models/user_model.dart';
import 'package:customer/services/location_service.dart';
import 'package:customer/widget/osm_map/map_picker_page.dart';
import 'package:customer/widget/place_picker/location_picker_screen.dart';
import 'package:customer/widget/place_picker/selected_location_model.dart';
import 'package:get/get.dart';

/// Ouvre le selecteur de position sur carte (OSM ou Google selon le reglage
/// admin) et enregistre le point choisi comme localisation courante.
///
/// Rend true si l'utilisateur a effectivement choisi une position, false s'il
/// est revenu en arriere — dans ce cas rien n'est modifie.
///
/// Ce flux etait duplique dans 3 ecrans, chacun avec sa propre variante du
/// meme bloc try/catch qui retombait sur une coordonnee en dur. Aucune
/// permission n'est demandee ici : choisir un point sur une carte n'en a pas
/// besoin, le picker demande lui-meme la position uniquement pour centrer sa
/// camera au depart.
Future<bool> pickLocationOnMap({LocationSource source = LocationSource.mapPicker}) async {
  final ShippingAddress picked;

  if (Constant.selectedMapType == 'osm') {
    final dynamic result = await Get.to(() => MapPickerPage());
    if (result == null) return false;
    picked = ShippingAddress(
      addressAs: "Home",
      locality: result.address.toString(),
      location: UserLocation(latitude: result.coordinates.latitude, longitude: result.coordinates.longitude),
    );
  } else {
    final dynamic value = await Get.to(LocationPickerScreen());
    if (value == null) return false;
    final SelectedLocationModel selected = value;
    picked = ShippingAddress(
      addressAs: "Home",
      locality: Constant.formatAddress(selectedLocation: selected),
      location: UserLocation(latitude: selected.latLng!.latitude, longitude: selected.latLng!.longitude),
    );
  }

  LocationService.setLocation(picked, source: source);
  return true;
}
