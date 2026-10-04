import 'package:customer/app/auth_screen/login_screen.dart';
import 'package:customer/controllers/on_boarding_controller.dart';
import 'package:customer/themes/app_them_data.dart';
import 'package:customer/themes/round_button_fill.dart';
import 'package:customer/utils/dark_theme_provider.dart';
import 'package:customer/utils/preferences.dart';
import 'package:flutter/material.dart';
import 'package:customer/widget/translated_text.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../constant/constant.dart';

class OnBoardingScreen extends StatelessWidget {
  const OnBoardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeChange = Provider.of<DarkThemeProvider>(context);
    return GetX<OnBoardingController>(
      init: OnBoardingController(),
      builder: (controller) {
        return Scaffold(
          body: controller.isLoading.value
              ? Constant.loader()
              : Container(
                  decoration: BoxDecoration(
                      image: DecorationImage(
                          image: AssetImage(controller.selectedPageIndex.value == 0
                              ? "assets/images/image_1.png"
                              : controller.selectedPageIndex.value == 1
                                  ? "assets/images/image_2.png"
                                  : "assets/images/image_3.png"),
                          fit: BoxFit.cover)),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.transparent, Color(0xF2000000)],
                        stops: [0.0, 0.4, 1.0],
                      ),
                    ),
                    child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: PageView.builder(
                              controller: controller.pageController,
                              onPageChanged: controller.selectedPageIndex.call,
                              itemCount: controller.onBoardingList.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Image.asset(
                                        "assets/images/ic_logo.png",
                                        width: 72,
                                        height: 72,
                                      ),
                                      TranslatedText(
                                        "Viteat",
                                        style: TextStyle(color: themeChange.getThem() ? AppThemeData.grey50 : AppThemeData.grey50, fontSize: 24, fontFamily: AppThemeData.bold),
                                      ),
                                      const SizedBox(
                                        height: 30,
                                      ),
                                      TranslatedText(
                                        controller.onBoardingList[index].title.toString(),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: themeChange.getThem() ? AppThemeData.primary300 : AppThemeData.primary300,
                                          fontSize: 28,
                                          fontFamily: AppThemeData.bold,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                      TranslatedText(
                                        controller.onBoardingList[index].description.toString(),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: themeChange.getThem() ? AppThemeData.grey600 : AppThemeData.grey300,
                                          fontSize: 16,
                                          fontFamily: AppThemeData.regular,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                        ),
                        const SizedBox(
                          height: 20,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            controller.onBoardingList.length,
                            (index) {
                              final bool active = controller.selectedPageIndex.value == index;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                height: 8,
                                width: active ? 24 : 8,
                                decoration: BoxDecoration(
                                  color: active ? AppThemeData.primary300 : AppThemeData.grey50.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(AppThemeData.radiusPill),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(
                          height: 20,
                        ),
                        RoundedButtonFill(
                          title: controller.selectedPageIndex.value == controller.onBoardingList.length - 1 ? "Get Started" : "Next",
                          gradient: AppThemeData.primaryGradient,
                          color: AppThemeData.primary300,
                          textColor: AppThemeData.grey50,
                          onPress: () {
                            if (controller.selectedPageIndex.value == 2) {
                              Preferences.setBoolean(Preferences.isFinishOnBoardingKey, true);
                              Get.offAll(const LoginScreen());
                            } else {
                              controller.pageController.jumpToPage(controller.selectedPageIndex.value + 1);
                            }
                          },
                        ),
                        const SizedBox(
                          height: 50,
                        ),
                      ],
                    ),
                  ),
                  ),
                ),
        );
      },
    );
  }
}
