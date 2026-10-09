import 'package:customer/app/ai_agent/ai_agent_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

/// Bouton « Agent IA » (icone de robot) de l'en-tete d'accueil, a cote du
/// panier : icone blanche seule sur le degrade orange, sans bulle de fond.
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
        // Icone seule, sans bulle de fond (comme le panier voisin).
        child: SizedBox(
          width: size,
          height: size,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: SvgPicture.asset("assets/icons/ic_ai_agent.svg"),
          ),
        ),
      ),
    );
  }
}
