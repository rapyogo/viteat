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
      child: Container(
        width: Responsive.width(width ?? 100, context),
        height: Responsive.height(height ?? 6, context),
        decoration: ShapeDecoration(
          color: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius ?? 200),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            (isRight == false) ? Padding(padding: const EdgeInsets.only(right: 5), child: icon) : const SizedBox(),
            // Le libelle etait pose directement dans le Row : il prenait sa
            // largeur naturelle et debordait des qu'une traduction depassait
            // l'anglais (le francais est regulierement 30% plus long). Flexible
            // borne la largeur disponible, FittedBox reduit legerement la
            // police plutot que de tronquer — le libelle reste entier et
            // aucun bouton de l'app ne peut plus deborder.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: TranslatedText(
                  title.tr.toString(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppThemeData.semiBold,
                    color: textColor ?? AppThemeData.grey800,
                    fontSize: fontSizes ?? 14,
                  ),
                ),
              ),
            ),
            (isRight == true) ? Padding(padding: const EdgeInsets.only(left: 5), child: icon) : const SizedBox(),
          ],
        ),
      ),
    );
  }
}
