import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get/get.dart';

enum SyncState { offline, online, syncing, syncFailed }

/// Etat de connectivité/synchronisation partagé par toute l'app.
/// Posé tôt (avant runApp) via Get.put(..., permanent: true) pour être
/// disponible depuis n'importe quel contrôleur sans câblage par écran.
class ConnectivityService extends GetxService {
  final Rx<SyncState> state = SyncState.online.obs;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool get isOffline => state.value == SyncState.offline;

  @override
  void onInit() {
    super.onInit();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final List<ConnectivityResult> initial = await Connectivity().checkConnectivity();
    _applyConnectivity(initial);
    _subscription = Connectivity().onConnectivityChanged.listen(_applyConnectivity);
  }

  void _applyConnectivity(List<ConnectivityResult> results) {
    final bool offline = results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    if (offline) {
      state.value = SyncState.offline;
    } else if (state.value == SyncState.offline) {
      // On ne repasse pas systématiquement à "online" sur syncing/syncFailed —
      // seule la transition depuis offline doit être automatique ici, le reste
      // est piloté par markSyncing/markSynced/markSyncFailed autour des lectures réseau.
      state.value = SyncState.online;
    }
  }

  void markSyncing() {
    if (state.value != SyncState.offline) state.value = SyncState.syncing;
  }

  void markSynced() {
    if (state.value != SyncState.offline) state.value = SyncState.online;
  }

  void markSyncFailed() {
    if (state.value != SyncState.offline) state.value = SyncState.syncFailed;
  }

  @override
  void onClose() {
    _subscription?.cancel();
    super.onClose();
  }
}
