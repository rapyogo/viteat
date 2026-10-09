import 'package:customer/app/ai_agent/ai_agent_screen.dart';
import 'package:customer/themes/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

/// Bouton rond « Agent IA » de l'en-tete d'accueil, au meme style que le
/// bouton panier voisin (verre depoli blanc sur le degrade orange).
class AiAgentButton extends StatelessWidget {
  const AiAgentButton({super.key, this.size = 42});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: "AI Agent".tr,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => Get.to(const AiAgentScreen()),
        child: Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppThemeData.grey50.withValues(alpha: 0.22),
            shape: BoxShape.circle,
            border: Border.all(color: AppThemeData.grey50.withValues(alpha: 0.35)),
          ),
          child: SvgPicture.asset("assets/icons/ic_ai_agent.svg"),
        ),
      ),
    );
  }
}
