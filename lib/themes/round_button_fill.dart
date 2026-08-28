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

  const RoundedButtonFill(
      {super.key, this.isEnabled = true, required this.title, this.height, required this.onPress, this.width, this.color, this.icon, this.fontSizes, this.textColor, this.isRight, this.radius});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isEnabled == true
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
            decoration: ShapeDecoration(
              color: color,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radius ?? 200),
              ),
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
    );
  }
}
