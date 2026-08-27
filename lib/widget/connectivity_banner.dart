import 'package:customer/services/connectivity_service.dart';
import 'package:customer/themes/app_them_data.dart';
import 'package:customer/widget/translated_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Petite bannière non bloquante affichée en haut de l'app quand le réseau
/// est indisponible ou qu'une synchronisation en arrière-plan a échoué.
/// Les données déjà en cache restent affichées derrière — cette bannière
/// n'obstrue jamais le contenu, elle informe seulement.
class ConnectivityBanner extends StatelessWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<ConnectivityService>()) return const SizedBox.shrink();
    final ConnectivityService connectivity = Get.find<ConnectivityService>();
    return Obx(() {
      final SyncState state = connectivity.state.value;
      if (state == SyncState.online) return const SizedBox.shrink();

      final (Color background, Color foreground, String message) = switch (state) {
        SyncState.offline => (AppThemeData.warning100, AppThemeData.warning500, "You're offline — showing saved data"),
        SyncState.syncing => (AppThemeData.info100, AppThemeData.info500, "Syncing..."),
        SyncState.syncFailed => (AppThemeData.danger100, AppThemeData.danger500, "Sync failed — retrying when back online"),
        SyncState.online => (AppThemeData.grey100, AppThemeData.grey600, ""),
      };

      return Container(
        width: double.infinity,
        color: background,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        child: SafeArea(
          bottom: false,
          child: TranslatedText(
            message,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppThemeData.medium,
              fontSize: 12,
              color: foreground,
            ),
          ),
        ),
      );
    });
  }
}
