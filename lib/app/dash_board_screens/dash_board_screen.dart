import 'package:customer/constant/constant.dart';
import 'package:customer/constant/show_toast_dialog.dart';
import 'package:customer/controllers/dash_board_controller.dart';
import 'package:customer/themes/app_them_data.dart';
import 'package:customer/utils/dark_theme_provider.dart';
import 'package:customer/utils/dynamic_traslator.dart';
import 'package:customer/utils/translation_notifier.dart';
import 'package:customer/widget/connectivity_banner.dart';
import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

class DashBoardScreen extends StatelessWidget {
  const DashBoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeChange = Provider.of<DarkThemeProvider>(context);
    return GetX(
        init: DashBoardController(),
        builder: (controller) {
          return PopScope(
            canPop: controller.canPopNow.value,
            onPopInvoked: (didPop) {
              final now = DateTime.now();
              if (controller.currentBackPressTime == null || now.difference(controller.currentBackPressTime!) > const Duration(seconds: 2)) {
                controller.currentBackPressTime = now;
                controller.canPopNow.value = false;
                ShowToastDialog.showToast("Double press to exit");
                return;
              } else {
                controller.canPopNow.value = true;
              }
            },
            // onPopInvokedWithResult: (didPop, dynamic) {
            //   final now = DateTime.now();
            //   if (controller.currentBackPressTime == null || now.difference(controller.currentBackPressTime!) > const Duration(seconds: 2)) {
            //     controller.currentBackPressTime = now;
            //     controller.canPopNow.value = false;
            //     ShowToastDialog.showToast("Double press to exit");
            //     return;
            //   } else {
            //     controller.canPopNow.value = true;
            //   }
            // },
            child: Scaffold(
              body: Column(
                children: [
                  const ConnectivityBanner(),
                  Expanded(
                    child: controller.pageList.isEmpty ? SizedBox() : controller.pageList[controller.selectedIndex.value],
                  ),
                ],
              ),
              // Barre flottante arrondie et animee (Foodie 9.2). Pas d'extendBody :
              // le contenu (et le bandeau de connexion) reste au-dessus de la barre,
              // rien n'est masque dessous.
              bottomNavigationBar: ValueListenableBuilder(
                  valueListenable: TranslationNotifier.refresh,
                  builder: (_, __, ___) {
                    final bool isDark = themeChange.getThem();
                    final List<_NavItemData> items = Constant.walletSetting == false
                        ? const [
                            _NavItemData(assetIcon: "assets/icons/ic_home.svg", label: 'Home'),
                            _NavItemData(assetIcon: "assets/icons/ic_fav.svg", label: 'Favourites'),
                            _NavItemData(assetIcon: "assets/icons/ic_orders.svg", label: 'Orders'),
                            _NavItemData(assetIcon: "assets/icons/ic_profile.svg", label: 'Profile'),
                          ]
                        : const [
                            _NavItemData(assetIcon: "assets/icons/ic_home.svg", label: 'Home'),
                            _NavItemData(assetIcon: "assets/icons/ic_fav.svg", label: 'Favourites'),
                            _NavItemData(assetIcon: "assets/icons/ic_wallet.svg", label: 'Wallet'),
                            _NavItemData(assetIcon: "assets/icons/ic_orders.svg", label: 'Orders'),
                            _NavItemData(assetIcon: "assets/icons/ic_profile.svg", label: 'Profile'),
                          ];
                    return SafeArea(
                      top: false,
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? AppThemeData.grey900 : AppThemeData.grey50,
                          borderRadius: BorderRadius.circular(AppThemeData.radiusXl),
                          boxShadow: AppThemeData.floatShadow,
                          border: Border.all(color: isDark ? AppThemeData.grey800 : AppThemeData.grey100),
                        ),
                        // Material transparent : l'effet d'encre des onglets se dessine
                        // au-dessus du fond de la barre, pas derriere.
                        child: Material(
                          type: MaterialType.transparency,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: List.generate(items.length, (index) {
                              return _NavItem(
                                data: items[index],
                                selected: controller.selectedIndex.value == index,
                                isDark: isDark,
                                onTap: () {
                                  if (index == 0) {
                                    Get.put(DashBoardController());
                                  }
                                  controller.selectedIndex.value = index;
                                },
                              );
                            }),
                          ),
                        ),
                      ),
                    );
                  }),
            ),
          );
        });
  }
}

class _NavItemData {
  final String assetIcon;
  final String label;
  const _NavItemData({required this.assetIcon, required this.label});
}

class _NavItem extends StatelessWidget {
  final _NavItemData data;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _NavItem({required this.data, required this.selected, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final Color inactive = isDark ? AppThemeData.grey300 : AppThemeData.grey600;
    final String label = data.label.tr;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppThemeData.radiusPill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          padding: EdgeInsets.symmetric(horizontal: selected ? 14 : 10, vertical: 10),
          decoration: BoxDecoration(
            gradient: selected ? AppThemeData.primaryGradient : null,
            borderRadius: BorderRadius.circular(AppThemeData.radiusPill),
            boxShadow: selected ? AppThemeData.primaryGlow : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                data.assetIcon,
                height: 22,
                width: 22,
                colorFilter: ColorFilter.mode(selected ? AppThemeData.grey50 : inactive, BlendMode.srcIn),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 82),
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: AppThemeData.bold, fontSize: 12.5, color: AppThemeData.grey50),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
