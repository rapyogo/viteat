import 'dart:async';

import 'package:customer/constant/constant.dart';
import 'package:customer/models/vendor_model.dart';
import 'package:customer/services/location_service.dart';
import 'package:customer/utils/fire_store_utils.dart';
import 'package:flutter/foundation.dart';

/// Un seul flux geographique des restaurants proches, partage par tous les
/// ecrans (accueil, dine-in, categories, publicites, scan QR).
///
/// Avant, chaque ecran ouvrait sa propre requete geographique (9 requetes
/// geohash en temps reel par ecran) sur les memes documents, avec seulement un
/// filtre different. Les filtres « categorie » et « dine-in » sont maintenant
/// appliques en memoire sur le flux commun.
///
/// Le flux reste ouvert [_idleGrace] apres le depart du dernier ecran, pour
/// qu'ouvrir puis fermer une categorie ne relance pas la requete.
class VendorRepository {
  VendorRepository._();

  static final VendorRepository instance = VendorRepository._();

  static const Duration _idleGrace = Duration(seconds: 90);

  final StreamController<List<VendorModel>> _hub = StreamController<List<VendorModel>>.broadcast();
  StreamSubscription<List<VendorModel>>? _source;
  String? _sourceKey;
  List<VendorModel>? _last;
  int _listeners = 0;
  Timer? _idleTimer;

  /// Derniere liste recue pour la position courante (filtre de base), ou null.
  List<VendorModel>? get current => _last == null || _sourceKey != _currentKey() ? null : List<VendorModel>.of(_last!);

  /// Restaurants proches. [categoryId] et [dineIn] reproduisent exactement les
  /// anciennes requetes dediees (voir [_matches]).
  Stream<List<VendorModel>> watchNearby({String? categoryId, bool dineIn = false}) {
    StreamSubscription<List<VendorModel>>? hubSub;
    late final StreamController<List<VendorModel>> out;
    List<VendorModel> view(List<VendorModel> base) => base.where((VendorModel v) => _matches(v, categoryId: categoryId, dineIn: dineIn)).toList();

    out = StreamController<List<VendorModel>>(
      onListen: () {
        final String? key = _currentKey();
        if (key == null) {
          // Pas de localisation ou de zone : meme comportement qu'avant
          // (liste vide, les ecrans invitent a choisir une adresse).
          out.add(<VendorModel>[]);
          return;
        }
        _listeners++;
        _idleTimer?.cancel();
        _ensureSource(key);
        hubSub = _hub.stream.listen((List<VendorModel> base) => out.add(view(base)));
        if (_last != null) out.add(view(_last!));
      },
      onCancel: () async {
        if (hubSub == null) return;
        await hubSub?.cancel();
        hubSub = null;
        _listeners--;
        if (_listeners <= 0) {
          _listeners = 0;
          _idleTimer?.cancel();
          _idleTimer = Timer(_idleGrace, _closeSource);
        }
      },
    );
    return out.stream;
  }

  /// Une nouvelle position ou zone (cle differente) relance la requete : les
  /// autres ecrans encore abonnes recoivent alors la liste du nouvel endroit.
  void _ensureSource(String key) {
    if (_source != null && _sourceKey == key) return;
    _source?.cancel();
    if (_sourceKey != key) _last = null;
    _sourceKey = key;
    _source = FireStoreUtils.getAllNearestRestaurant().listen((List<VendorModel> vendors) {
      _last = vendors;
      for (final VendorModel v in vendors) {
        if (v.id != null) FireStoreUtils.rememberVendor(v);
      }
      _hub.add(List<VendorModel>.of(vendors));
    }, onError: (Object e) => debugPrint("VendorRepository :: $e"));
  }

  void _closeSource() {
    if (_listeners > 0) return;
    _source?.cancel();
    _source = null;
  }

  static String? _currentKey() {
    if (!LocationService.isResolved || Constant.selectedZone == null) return null;
    return '${Constant.selectedZone?.id}|${LocationService.latitude}|${LocationService.longitude}|${Constant.radius}';
  }

  /// Memes regles que les anciennes requetes getAllNearestRestaurantByCategoryId
  /// et getAllNearestRestaurant(isDining: true), appliquees au flux de base
  /// (qui porte deja les regles « en ligne » et « abonnement » communes).
  static bool _matches(VendorModel v, {String? categoryId, required bool dineIn}) {
    if (dineIn && v.enabledDiveInFuture != true) return false;
    if (categoryId != null) {
      if (!(v.categoryID ?? const <dynamic>[]).contains(categoryId)) return false;
      // Regle propre a l'ancienne requete par categorie : un abonnement limite
      // dont le quota de commandes est epuise n'y apparaissait pas.
      final bool subscriptionRules = Constant.isSubscriptionModelApplied == true || Constant.adminCommission?.isEnabled == true;
      if (subscriptionRules && v.subscriptionPlan != null && v.subscriptionTotalOrders != "-1" && v.subscriptionTotalOrders == '0') return false;
    }
    return true;
  }
}
