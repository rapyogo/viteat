import 'package:customer/themes/app_them_data.dart';
import 'package:customer/utils/dark_theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Squelette affiche pendant le chargement de l'accueil (Foodie 9.2).
///
/// Skeleton placeholder shown while the home screen loads.
///
/// Renders instantly (gradient header + pulsing grey blocks shaped like the
/// real layout) so the user never stares at a bare spinner. Purely visual —
/// no data dependencies.
class HomeSkeleton extends StatefulWidget {
  const HomeSkeleton({super.key});

  @override
  State<HomeSkeleton> createState() => _HomeSkeletonState();
}

class _HomeSkeletonState extends State<HomeSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _pulse = Tween<double>(begin: 0.45, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respecte le reglage systeme « supprimer les animations » : bloc fixe.
    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
      _controller.value = 1.0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeChange = Provider.of<DarkThemeProvider>(context);
    final bool isDark = themeChange.getThem();
    final Color block = isDark ? AppThemeData.grey800 : AppThemeData.grey200;

    Widget bar({double? width, double height = 12, double radius = 6}) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: block, borderRadius: BorderRadius.circular(radius)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Gradient header placeholder — mirrors the real hero header.
        Container(
          width: double.infinity,
          padding: EdgeInsets.only(top: MediaQuery.of(context).viewPadding.top + 8, left: 16, right: 16, bottom: 18),
          decoration: BoxDecoration(
            gradient: AppThemeData.brandGradientSoft,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppThemeData.radiusXl)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.30), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(height: 10, width: 70, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(5))),
                        const SizedBox(height: 6),
                        Container(height: 12, width: 180, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(6))),
                      ],
                    ),
                  ),
                  Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(height: 20, width: 240, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8))),
              const SizedBox(height: 14),
              Container(
                height: 48,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(AppThemeData.radiusMd),
                ),
              ),
            ],
          ),
        ),
        // Pulsing body placeholders.
        Expanded(
          child: FadeTransition(
            opacity: _pulse,
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(width: 170, height: 18, radius: 8),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(4, (i) {
                      return Column(
                        children: [
                          Container(height: 62, width: 62, decoration: BoxDecoration(color: block, shape: BoxShape.circle)),
                          const SizedBox(height: 8),
                          bar(width: 46, height: 9),
                        ],
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    height: 140,
                    width: double.infinity,
                    decoration: BoxDecoration(color: block, borderRadius: BorderRadius.circular(AppThemeData.radiusLg)),
                  ),
                  const SizedBox(height: 24),
                  bar(width: 150, height: 18, radius: 8),
                  const SizedBox(height: 16),
                  ...List.generate(3, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        children: [
                          Container(height: 92, width: 100, decoration: BoxDecoration(color: block, borderRadius: BorderRadius.circular(AppThemeData.radiusMd))),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                bar(width: 160, height: 14),
                                const SizedBox(height: 8),
                                bar(width: 120, height: 10),
                                const SizedBox(height: 8),
                                bar(width: 90, height: 10),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
