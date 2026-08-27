import 'dart:developer';
import 'package:customer/services/location_service.dart';
import 'dart:convert';

import 'package:customer/widget/osm_map/place_model.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class OSMMapController extends GetxController {
  final mapController = MapController();
  // Store only one picked place instead of multiple
  var pickedPlace = Rxn<PlaceModel>(); // Use Rxn to hold a nullable value
  var searchResults = [].obs;

  Future<void> searchPlace(String query) async {
    if (query.length < 3) {
      searchResults.clear();
      return;
    }

    final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$query&format=json&addressdetails=1&limit=10');

    final response = await http.get(url, headers: {
      'User-Agent': 'FlutterMapApp/1.0 (menil.siddhiinfosoft@gmail.com)',
    });

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      searchResults.value = data;
    }
  }

  void selectSearchResult(Map<String, dynamic> place) {
    final lat = double.parse(place['lat']);
    final lon = double.parse(place['lon']);
    final address = place['display_name'];

    // Store only the selected place
    pickedPlace.value = PlaceModel(
      coordinates: LatLng(lat, lon),
      address: address,
    );
    searchResults.clear();
  }

  void addLatLngOnly(LatLng coords) async {
    final address = await _getAddressFromLatLng(coords);
    pickedPlace.value = PlaceModel(coordinates: coords, address: address);
  }

  Future<String> _getAddressFromLatLng(LatLng coords) async {
    final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?lat=${coords.latitude}&lon=${coords.longitude}&format=json');

    final response = await http.get(url, headers: {
      'User-Agent': 'FlutterMapApp/1.0 (menil.siddhiinfosoft@gmail.com)',
    });

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['display_name'] ?? 'Unknown location';
    } else {
      return 'Unknown location';
    }
  }

  void clearAll() {
    pickedPlace.value = null; // Clear the selected place
  }

  @override
  void onInit() {
    // TODO: implement onInit
    super.onInit();
    getCurrentLocation();
  }

  getCurrentLocation() async {
    // Le `?? 0.0` d'origine centrait la carte sur (0,0) — au large de l'Afrique
    // — des que le GPS n'aboutissait pas. Repli en cascade, puis abandon :
    // mieux vaut laisser la camera en place que sauter dans l'ocean.
    final Position? position = await LocationService.to.rawPosition();
    LatLng? target;
    if (position != null) {
      target = LatLng(position.latitude, position.longitude);
    } else if (LocationService.isResolved) {
      target = LatLng(LocationService.latitude!, LocationService.longitude!);
    } else {
      final Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) target = LatLng(lastKnown.latitude, lastKnown.longitude);
    }
    if (target == null) {
      log("OSMMapController: aucune position disponible, camera inchangee");
      return;
    }
    addLatLngOnly(target);
    mapController.move(target, mapController.camera.zoom);
  }
}
