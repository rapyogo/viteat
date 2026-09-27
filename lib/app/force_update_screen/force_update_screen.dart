import 'package:customer/themes/app_them_data.dart';
import 'package:customer/utils/dark_theme_provider.dart';
import 'package:customer/widget/translated_text.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Ecran bloquant affiche quand la version installee est plus ancienne que
/// `settings/Version.minCustomerBuildNumber`. Sert a retirer du parc les
/// versions qui ne filtrent pas les restaurants hors ligne (isLive == false).
class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key, required this.storeUrl});

  final String storeUrl;

  @override
  Widget build(BuildContext context) {
    final themeChange = Provider.of<DarkThemeProvider>(context);
    final Color textColor = themeChange.getThem() ? AppThemeData.grey100 : AppThemeData.grey800;
    return Scaffold(
      backgroundColor: themeChange.getThem() ? AppThemeData.surfaceDark : AppThemeData.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.system_update, size: 96, color: AppThemeData.primary300),
              const SizedBox(height: 20),
              TranslatedText(
                "Update required",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor),
              ),
              const SizedBox(height: 10),
              TranslatedText(
                "A new version of the app is available. Please update to continue ordering.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: textColor),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppThemeData.primary300),
                  onPressed: () => launchUrl(Uri.parse(storeUrl), mode: LaunchMode.externalApplication),
                  child: TranslatedText("Update", style: const TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
