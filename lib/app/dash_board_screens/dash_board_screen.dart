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
              // Comme Foodie 9.2 : le contenu defile sous la barre flottante ; les
              // ecrans gardent un espace bas pour que rien ne reste masque dessous.
              extendBody: true,
              body: Column(
                children: [
                  const ConnectivityBanner(),
                  Expanded(
                    // Onglets persistants : un onglet deja ouvert reste monte (son
                    // controleur et ses donnees aussi) au lieu d'etre detruit puis
                    // recharge a chaque changement d'onglet. Construction
                    // paresseuse : un onglet n'est cree qu'a sa premiere ouverture.
                    child: controller.pageList.isEmpty
                        ? const SizedBox()
                        : Builder(builder: (context) {
                            final int selected = controller.selectedIndex.value.clamp(0, controller.pageList.length - 1);
                            controller.visitedTabs.add(selected);
                            return IndexedStack(
                              index: selected,
                              children: List.generate(
                                controller.pageList.length,
                                (i) => controller.visitedTabs.contains(i) ? controller.pageList[i] as Widget : const SizedBox.shrink(),
                              ),
                            );
                          }),
                  ),
                ],
              ),
              // Barre flottante arrondie et animee (Foodie 9.2).
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
                          // Les onglets inactifs gardent leur taille (icone, 44 px) ;
                          // l'onglet actif prend toute la place restante et son
                          // libelle se coupe avec « … » au lieu de deborder
                          // (« Portefeuille », « Commandes » avec 5 onglets).
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(items.length, (index) {
                              final bool selected = controller.selectedIndex.value == index;
                              final Widget item = _NavItem(
                                data: items[index],
                                selected: selected,
                                isDark: isDark,
                                onTap: () {
                                  if (index == 0) {
                                    Get.put(DashBoardController());
                                  }
                                  controller.selectedIndex.value = index;
                                },
                              );
                              // heightFactor 1 : la barre garde la hauteur de l'onglet (une
                              // bottomNavigationBar n'a pas de hauteur bornee, un Center seul
                              // s'etirait sur tout l'ecran).
                              return selected ? Expanded(child: Center(heightFactor: 1, child: item)) : item;
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
          padding: EdgeInsets.symmetric(horizontal: selected ? 12 : 10, vertical: 10),
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
                Flexible(
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
