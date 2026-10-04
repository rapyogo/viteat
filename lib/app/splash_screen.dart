import 'package:customer/controllers/splash_controller.dart';
import 'package:customer/themes/app_them_data.dart';
import 'package:customer/utils/dark_theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:customer/widget/translated_text.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

/// Splash Viteat, habillage anime Foodie 9.2 (fondu + zoom, degrade de marque).
/// Toute la logique (session hors ligne, mise a jour forcee, maintenance)
/// reste dans SplashController : cet ecran ne fait que l'afficher.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reglage systeme « supprimer les animations » : etat final directement.
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1.0;
    } else if (_controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Garde le provider de theme branche pour la navigation qui suit.
    Provider.of<DarkThemeProvider>(context);
    return GetBuilder<SplashController>(
      init: SplashController(),
      builder: (controller) {
        return Scaffold(
          backgroundColor: AppThemeData.primary300,
          body: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(gradient: AppThemeData.brandGradientSoft),
            child: Stack(
              children: [
                // Formes decoratives douces pour la profondeur.
                Positioned(top: -80, right: -60, child: _blob(220, Colors.white.withValues(alpha: 0.10))),
                Positioned(bottom: -70, left: -50, child: _blob(200, Colors.white.withValues(alpha: 0.08))),
                SafeArea(
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: FadeTransition(
                            opacity: _fade,
                            child: ScaleTransition(
                              scale: _scale,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(22),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.16),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.30), width: 1.5),
                                    ),
                                    child: Image.asset("assets/images/ic_logo.png", height: 96, width: 96),
                                  ),
                                  const SizedBox(height: 26),
                                  const TranslatedText(
                                    "Welcome to Viteat",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: AppThemeData.grey50, fontSize: 28, fontFamily: AppThemeData.extraBold, letterSpacing: 0.2),
                                  ),
                                  const SizedBox(height: 8),
                                  TranslatedText(
                                    "Your Favorite Food Delivered Fast!",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: AppThemeData.grey50.withValues(alpha: 0.92), fontSize: 15, fontFamily: AppThemeData.medium),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      FadeTransition(
                        opacity: _fade,
                        child: SizedBox(
                          height: 26,
                          width: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation(Colors.white.withValues(alpha: 0.9)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: TranslatedText(
                          "by Rapyogo Ltd",
                          style: TextStyle(color: AppThemeData.grey50.withValues(alpha: 0.7), fontSize: 12, fontFamily: AppThemeData.medium),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _blob(double size, Color color) {
    return Container(height: size, width: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
  }
}
