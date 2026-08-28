import 'package:customer/themes/app_them_data.dart';
import 'package:customer/themes/responsive.dart';
import 'package:flutter/material.dart';
import 'package:customer/widget/translated_text.dart';

class RoundedButtonBorder extends StatelessWidget {
  final String title;
  final double? width;
  final double? height;
  final double? fontSizes;
  final Color? color;
  final Color? borderColor;
  final Color? textColor;
  final Widget? icon;
  final bool? isRight;
  final Function()? onPress;

  const RoundedButtonBorder({
    super.key,
    required this.title,
    this.height,
    required this.onPress,
    this.width,
    this.color,
    this.icon,
    this.fontSizes,
    this.textColor,
    this.isRight,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
        onPress!();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final Widget label = TranslatedText(
            title.toString(),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppThemeData.semiBold,
              color: textColor ?? AppThemeData.grey800,
              fontSize: fontSizes ?? 14,
            ),
          );
          // Meme principe que RoundedButtonFill : la taille demandee est un
          // minimum, le cadre suit la longueur du libelle traduit.
          return Container(
            constraints: BoxConstraints(
              minWidth: Responsive.width(width ?? 100, context),
              minHeight: Responsive.height(height ?? 6, context),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: ShapeDecoration(
              color: color ?? Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(200),
                side: BorderSide(color: borderColor ?? AppThemeData.primary300),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                (isRight == false) ? Padding(padding: const EdgeInsets.only(right: 10), child: icon) : const SizedBox(),
                constraints.maxWidth.isFinite ? Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: label)) : label,
                (isRight == true) ? Padding(padding: const EdgeInsets.only(left: 10), child: icon) : const SizedBox(),
              ],
            ),
          );
        },
      ),
    );
  }
}
