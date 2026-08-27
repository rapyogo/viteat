import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:customer/models/user_model.dart';
import 'package:customer/utils/preferences.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:location/location.dart' as location_pkg;

/// D'ou provient la localisation courante. Purement informatif (log/debug) :
/// aucune regle de priorite ne s'appuie dessus — voir la note sur le conflit
/// cache/profil dans setLocation().
enum LocationSource { profile, gps, mapPicker, manual, unknown }

/// Raison d'echec d'une acquisition GPS. Sert a afficher un message et une
/// action utiles (cf. LocationFailureSheet) plutot qu'un "erreur" generique.
enum LocationFailure { serviceDisabled, permissionDenied, permissionDeniedForever, timeout, unknown }

/// Resultat d'une acquisition GPS.
///
/// `address` non-null <=> succes, avec coordonnees garanties non-null. Il n'y a
/// deliberement aucun moyen de representer une adresse de repli dans ce type :
/// un echec ne peut pas se transformer en fausse position.
class LocationResult {
  final ShippingAddress? address;
  final LocationFailure? failure;

  const LocationResult._({this.address, this.failure});

  factory LocationResult.success(ShippingAddress address) => LocationResult._(address: address);

  factory LocationResult.failed(LocationFailure failure) => LocationResult._(failure: failure);

  bool get isSuccess => address != null;
}

/// Point de passage unique pour lire, ecrire et persister la localisation de
/// l'utilisateur.
///
/// Le principe fondateur (decide en session du 2026-08-26, cf. le commentaire
/// de Constant.selectedLocation) : **une localisation non resolue reste null**.
/// Elle n'est JAMAIS remplacee par une coordonnee factice — ni (0,0), ni une
/// ville par defaut. Le type expose ici est un `Rxn`, donc `ShippingAddress?` :
/// le null fait partie du type et l'analyseur refuse une lecture non gardee.
///
/// L'etat est `static` parce que la facade `Constant.selectedLocation` est
/// appelee depuis des dizaines d'endroits, parfois avant toute injection GetX ;
/// un `Get.find()` y leverait un "LocationService not found". Le GetxService ne
/// sert qu'au cycle de vie (hydratation depuis le cache dans onInit).
class LocationService extends GetxService {
  static final Rxn<ShippingAddress> current = Rxn<ShippingAddress>();

  static LocationService get to => Get.find<LocationService>();

  @override
  void onInit() {
    super.onInit();
    hydrateFromCache();
  }

  // --------------------------------------------------------------- lecture

  /// true seulement si latitude ET longitude sont reellement renseignees.
  static bool get isResolved => current.value?.location?.latitude != null && current.value?.location?.longitude != null;

  static UserLocation? get coordinates => isResolved ? current.value!.location : null;

  static double? get latitude => coordinates?.latitude;

  static double? get longitude => coordinates?.longitude;

  /// Libelle a afficher (header d'accueil...). Ne rend jamais une chaine vide
  /// ni le " null " que produisait getFullAddress() sur une adresse vide : sans
  /// localisation, c'est un appel a l'action.
  static String get displayLabel {
    if (!isResolved) return 'Set my location'.tr;
    final String label = current.value!.getFullAddress().trim();
    return label.isEmpty ? 'Current position'.tr : label;
  }

  // -------------------------------------------------------------- ecriture

  /// Unique point d'ecriture — la facade `Constant.selectedLocation = ...`
  /// passe par ici, donc les 19 sites d'affectation de l'app en heritent.
  ///
  /// Une adresse sans coordonnees est **refusee** (log + no-op) : c'est ce qui
  /// garantit qu'une `ShippingAddress()` vide ne peut jamais ecraser une
  /// localisation valide, sans avoir a auditer chaque appelant.
  static void setLocation(ShippingAddress address, {LocationSource source = LocationSource.unknown}) {
    if (address.location?.latitude == null || address.location?.longitude == null) {
      log("LocationService: adresse sans coordonnees ignoree (source: ${source.name})");
      return;
    }
    current.value = address;
    // L'UI ne doit pas attendre le disque : le Rx est deja a jour.
    _persist(address, source);
  }

  /// Variante attendable, pour un appelant qui doit garantir l'ecriture disque
  /// avant de poursuivre (aucun aujourd'hui — la facade est synchrone).
  static Future<void> setLocationAndPersist(ShippingAddress address, {LocationSource source = LocationSource.unknown}) async {
    if (address.location?.latitude == null || address.location?.longitude == null) {
      log("LocationService: adresse sans coordonnees ignoree (source: ${source.name})");
      return;
    }
    current.value = address;
    await _persist(address, source);
  }

  /// A appeler a la deconnexion : sans ca la localisation du compte precedent
  /// est reutilisee par le compte suivant sur le meme appareil
  /// (clearSharPreference() n'est jamais appele nulle part dans l'app).
  static Future<void> clear() async {
    current.value = null;
    await Preferences.clearKeyData(Preferences.selectedLocationKey);
    await Preferences.clearKeyData(Preferences.selectedLocationSourceKey);
    log("LocationService: localisation effacee");
  }

  // ----------------------------------------------------------- acquisition

  /// Verifie que le service de localisation systeme est actif, et propose a
  /// l'utilisateur de l'activer si non (c'est le seul endroit de l'app qui le
  /// propose — repris de l'ancien Utils.getCurrentLocation).
  Future<bool> ensureServiceEnabled() async {
    if (await Geolocator.isLocationServiceEnabled()) return true;
    await location_pkg.Location().requestService();
    return Geolocator.isLocationServiceEnabled();
  }

  /// Demande la permission si elle n'est pas encore accordee. Sans UI : c'est
  /// ce qui permet de l'appeler depuis un controleur. La partie dialogue reste
  /// dans Constant.checkPermission, qui delegue ici.
  Future<LocationPermission> ensurePermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission;
  }

  /// Position brute, sans adresse — pour les widgets carte qui veulent
  /// seulement centrer la camera. Rend null plutot que de lever.
  Future<Position?> rawPosition() async {
    try {
      if (!await ensureServiceEnabled()) return null;
      final LocationPermission permission = await ensurePermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(locationSettings: _settings);
    } catch (e) {
      log("LocationService.rawPosition :: $e");
      return null;
    }
  }

  /// Acquisition GPS complete : service, permission, position, puis adresse.
  ///
  /// accuracy medium + timeLimit 10s : la haute precision peut ne jamais
  /// aboutir en interieur (bug corrige en session precedente, ici generalise a
  /// tous les appelants).
  static const LocationSettings _settings = LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 10));

  Future<LocationResult> resolveFromGps({bool reverseGeocode = true}) async {
    if (!await ensureServiceEnabled()) {
      return LocationResult.failed(LocationFailure.serviceDisabled);
    }
    final LocationPermission permission = await ensurePermission();
    if (permission == LocationPermission.denied) {
      return LocationResult.failed(LocationFailure.permissionDenied);
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationResult.failed(LocationFailure.permissionDeniedForever);
    }

    final Position position;
    try {
      position = await Geolocator.getCurrentPosition(locationSettings: _settings);
    } on TimeoutException {
      return LocationResult.failed(LocationFailure.timeout);
    } on LocationServiceDisabledException {
      return LocationResult.failed(LocationFailure.serviceDisabled);
    } catch (e) {
      log("LocationService.resolveFromGps :: $e");
      return LocationResult.failed(LocationFailure.unknown);
    }

    final ShippingAddress address = ShippingAddress(
      addressAs: "Home",
      location: UserLocation(latitude: position.latitude, longitude: position.longitude),
    );

    // Le geocodage inverse a besoin du reseau : son echec ne doit PAS invalider
    // un point GPS parfaitement valide. C'etait le bug de fond des anciens
    // catch, qui jetaient la vraie position pour lui substituer une ville en
    // dur. Ici on garde les coordonnees, seul le libelle manque.
    if (reverseGeocode) {
      try {
        final List<Placemark> places = await placemarkFromCoordinates(position.latitude, position.longitude);
        if (places.isNotEmpty) {
          final Placemark p = places.first;
          address.locality = "${p.name}, ${p.subLocality}, ${p.locality}, ${p.administrativeArea}, ${p.postalCode}, ${p.country}";
        }
      } catch (e) {
        log("LocationService: geocodage inverse indisponible, coordonnees conservees :: $e");
      }
    }

    return LocationResult.success(address);
  }

  // ----------------------------------------------------------- persistance

  static Future<void> _persist(ShippingAddress address, LocationSource source) async {
    try {
      await Preferences.setString(Preferences.selectedLocationKey, jsonEncode(address.toJson()));
      await Preferences.setString(Preferences.selectedLocationSourceKey, source.name);
    } catch (e) {
      // Echouer a persister ne doit jamais casser le parcours en cours.
      log("LocationService: echec de persistance :: $e");
    }
  }

  /// Restaure la localisation de la session precedente.
  ///
  /// Appelee depuis onInit(), donc avant `runApp` : quand SplashController
  /// s'execute, la localisation est deja la — y compris hors-ligne, ou le
  /// profil Firestore est injoignable.
  ///
  /// Preferences.getString rend "" par defaut et n'a pas de containsKey : on
  /// traite "" comme "jamais defini", on n'ecrit jamais "" (clear() supprime la
  /// cle), et on revalide les coordonnees apres decodage. L'etat "defini mais
  /// vide" est donc inatteignable.
  Future<void> hydrateFromCache() async {
    final String raw = Preferences.getString(Preferences.selectedLocationKey);
    if (raw.isEmpty) {
      log("LocationService: aucune localisation en cache");
      return;
    }
    try {
      final ShippingAddress cached = ShippingAddress.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (cached.location?.latitude == null || cached.location?.longitude == null) {
        log("LocationService: cache sans coordonnees, purge");
        await Preferences.clearKeyData(Preferences.selectedLocationKey);
        return;
      }
      current.value = cached;
      log("LocationService: hydrate depuis le cache (source: ${Preferences.getString(Preferences.selectedLocationSourceKey)})");
    } catch (e) {
      // JSON corrompu/tronque : on purge pour ne pas retenter a chaque lancement.
      log("LocationService: cache illisible, purge :: $e");
      await Preferences.clearKeyData(Preferences.selectedLocationKey);
    }
  }
}
