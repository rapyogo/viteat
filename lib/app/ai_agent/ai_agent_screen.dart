import 'package:customer/app/profile_screen/whatsapp_link_screen.dart';
import 'package:customer/constant/constant.dart';
import 'package:customer/themes/app_them_data.dart';
import 'package:customer/utils/dark_theme_provider.dart';
import 'package:customer/widget/translated_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

/// Agent IA Viteat : ecran d'attente « Bientot disponible ».
///
/// La conversation (meme style que WhatsApp, liee a la session du client) est
/// specifiee dans docs/superpowers/plans/2026-10-09-agent-ia-et-personnalisation.md.
/// L'apercu ci-dessous est illustratif et presente comme tel.
class AiAgentScreen extends StatelessWidget {
  const AiAgentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Provider.of<DarkThemeProvider>(context).getThem();
    final Color background = isDark ? AppThemeData.surfaceDark : AppThemeData.surface;
    final Color surface = isDark ? AppThemeData.grey900 : AppThemeData.grey50;
    final Color textColor = isDark ? AppThemeData.grey50 : AppThemeData.grey900;
    final Color muted = isDark ? AppThemeData.grey400 : AppThemeData.grey500;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: textColor),
        title: TranslatedText("AI Agent", style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 20, color: textColor)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFFF8A2B), Color(0xFFFF5A00)],
                            ),
                          ),
                          child: SvgPicture.asset("assets/icons/ic_ai_agent.svg", width: 28, height: 28),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: AppThemeData.primary300.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                          child: TranslatedText("Coming soon", style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 13, color: AppThemeData.primary300)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    TranslatedText("Your Viteat assistant is on its way", style: TextStyle(fontFamily: AppThemeData.bold, fontSize: 24, height: 1.2, color: textColor)),
                    const SizedBox(height: 8),
                    TranslatedText(
                      "Chat just like on WhatsApp. It already knows your account, your orders and your tastes: no code, no setup.",
                      style: TextStyle(fontFamily: AppThemeData.regular, fontSize: 15, height: 1.45, color: muted),
                    ),
                    const SizedBox(height: 22),
                    _preview(surface, textColor, muted, isDark),
                    const SizedBox(height: 22),
                    TranslatedText("What it will do for you", style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 16, color: textColor)),
                    const SizedBox(height: 12),
                    _feature(Icons.restaurant_menu_rounded, "Find a dish that matches your craving and budget", textColor),
                    _feature(Icons.delivery_dining_rounded, "Follow your orders in progress", textColor),
                    _feature(Icons.favorite_border_rounded, "Remember your preferences and allergies", textColor),
                    if (Constant.userModel != null) ...[
                      const SizedBox(height: 18),
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Get.to(const WhatsAppLinkScreen()),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(14)),
                          child: Row(
                            children: [
                              SvgPicture.asset("assets/icons/ic_whatsapp.svg", width: 26, height: 26),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TranslatedText(
                                  "Meanwhile, order and chat with Viteat on WhatsApp",
                                  style: TextStyle(fontFamily: AppThemeData.medium, fontSize: 14, height: 1.35, color: textColor),
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded, color: muted),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Barre de saisie visible mais inactive : le geste est connu,
            // l'etat « pas encore » est explicite.
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
              decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(28)),
              child: Row(
                children: [
                  Expanded(child: TranslatedText("Available soon…", style: TextStyle(fontFamily: AppThemeData.regular, fontSize: 15, color: muted))),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: muted.withValues(alpha: 0.25), shape: BoxShape.circle),
                    child: Icon(Icons.send_rounded, size: 20, color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(Color surface, Color textColor, Color muted, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TranslatedText("Preview", style: TextStyle(fontFamily: AppThemeData.medium, fontSize: 12, color: muted)),
          const SizedBox(height: 10),
          _bubble("A light meal under \$10 near me?", true, textColor, isDark),
          const SizedBox(height: 8),
          _bubble("Here are 3 light dishes under \$10 open near you. Shall I show you the first one?", false, textColor, isDark),
        ],
      ),
    );
  }

  Widget _bubble(String text, bool fromUser, Color textColor, bool isDark) {
    final Color color = fromUser
        ? AppThemeData.primary300
        : isDark
            ? AppThemeData.grey800
            : AppThemeData.grey100;
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(fromUser ? 16 : 4),
              bottomRight: Radius.circular(fromUser ? 4 : 16),
            ),
          ),
          child: TranslatedText(text, style: TextStyle(fontFamily: AppThemeData.regular, fontSize: 14, height: 1.35, color: fromUser ? AppThemeData.grey50 : textColor)),
        ),
      ),
    );
  }

  Widget _feature(IconData icon, String label, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: AppThemeData.primary300.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: AppThemeData.primary300),
          ),
          const SizedBox(width: 12),
          Expanded(child: TranslatedText(label, style: TextStyle(fontFamily: AppThemeData.regular, fontSize: 14, height: 1.35, color: textColor))),
        ],
      ),
    );
  }
}
