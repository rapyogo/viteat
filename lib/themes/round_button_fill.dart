import 'package:customer/themes/app_them_data.dart';
import 'package:customer/themes/responsive.dart';
import 'package:flutter/material.dart';
import 'package:customer/widget/translated_text.dart';
import 'package:get/get.dart';

class RoundedButtonFill extends StatelessWidget {
  final String title;
  final double? width;
  final double? height;
  final double? fontSizes;
  final double? radius;
  final Color? color;
  final Color? textColor;
  final Widget? icon;
  final bool? isRight;
  final bool? isEnabled;
  final Function()? onPress;

  /// Degrade optionnel (Foodie 9.2) : s'il est fourni, il remplace [color].
  final Gradient? gradient;

  /// Halo colore sous le bouton (Foodie 9.2). Actif par defaut, seulement
  /// si le bouton a un fond (couleur ou degrade) et qu'il est actif.
  final bool elevated;

  const RoundedButtonFill(
      {super.key,
      this.isEnabled = true,
      required this.title,
      this.height,
      required this.onPress,
      this.width,
      this.color,
      this.icon,
      this.fontSizes,
      this.textColor,
      this.isRight,
      this.radius,
      this.gradient,
      this.elevated = true});

  @override
  Widget build(BuildContext context) {
    final bool enabled = isEnabled == true;
    final double cornerRadius = radius ?? AppThemeData.radiusPill;
    // Le halo prend la couleur du fond ; sans fond (bouton transparent), pas de halo.
    final Color? glowColor = color ?? (gradient != null ? AppThemeData.primary300 : null);
    final bool showGlow = elevated && enabled && glowColor != null && glowColor.a > 0;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(cornerRadius),
          onTap: enabled
              ? () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  onPress!();
                }
              : () {},
          child: LayoutBuilder(
            builder: (context, constraints) {
              final Widget label = TranslatedText(
                title.tr.toString(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppThemeData.semiBold,
                  color: textColor ?? AppThemeData.grey800,
                  fontSize: fontSizes ?? 14,
                ),
              );
              // La largeur/hauteur demandee est un MINIMUM, non une taille figee :
              // le fond du bouton s'elargit avec son libelle, au lieu de laisser un
              // texte traduit deborder d'une pastille de taille fixe (le francais
              // est regulierement 30% plus long que l'anglais). Le defaut (100%)
              // reste plein ecran ; seuls les boutons compacts grandissent.
              return Container(
                constraints: BoxConstraints(
                  minWidth: Responsive.width(width ?? 100, context),
                  minHeight: Responsive.height(height ?? 6, context),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: gradient == null ? color : null,
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(cornerRadius),
                  boxShadow: showGlow
                      ? [
                          BoxShadow(
                            color: glowColor.withValues(alpha: 0.32),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    (isRight == false) ? Padding(padding: const EdgeInsets.only(right: 5), child: icon) : const SizedBox(),
                    // Flexible n'est licite que sous une largeur bornee : dans un
                    // parent a largeur infinie (liste horizontale), il leverait une
                    // exception de layout. Le bouton pouvant desormais s'y trouver
                    // sans largeur fixe, on ne l'applique que si c'est sur.
                    constraints.maxWidth.isFinite ? Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: label)) : label,
                    (isRight == true) ? Padding(padding: const EdgeInsets.only(left: 5), child: icon) : const SizedBox(),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
