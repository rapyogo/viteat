import 'package:cached_network_image/cached_network_image.dart';
import 'package:customer/constant/constant.dart';
import 'package:customer/themes/responsive.dart';
import 'package:flutter/material.dart';


class NetworkImageWidget extends StatelessWidget {
  final String imageUrl;
  final double? height;
  final double? width;
  final Widget? errorWidget;
  final BoxFit? fit;
  final double? borderRadius;
  final Color? color;

  const NetworkImageWidget({
    super.key,
    this.height,
    this.width,
    this.fit,
    required this.imageUrl,
    this.borderRadius,
    this.errorWidget,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final double h = height ?? Responsive.height(8, context);
    final double w = width ?? Responsive.width(15, context);
    // Decodage a la taille affichee (et non en pleine resolution) : une photo
    // de 2000 px decodee pour une vignette de 60 px saturait la memoire et
    // saccadait le defilement. On se base sur le plus grand cote pour garder
    // une image nette quel que soit le BoxFit.
    final double dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    // Si un cote n'est pas borne (largeur pleine, double.infinity), on ne
    // connait pas la taille reelle : pas de reduction, sinon l'image (ex.
    // banniere) etait decodee trop petite et apparaissait floue.
    final bool bounded = w.isFinite && h.isFinite && w > 0 && h > 0;
    final int? decodeSize = bounded ? ((w > h ? w : h) * dpr).round() : null;

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit ?? BoxFit.fitWidth,
      height: h,
      width: w,
      color: color,
      memCacheWidth: decodeSize,
      fadeInDuration: const Duration(milliseconds: 150),
      // Fond neutre statique au lieu d'un GIF anime par image (couteux a
      // decoder et a animer dans les longues listes).
      placeholder: (context, url) => Container(
        height: height,
        width: width,
        color: Colors.grey.withValues(alpha: 0.15),
      ),
      errorWidget: (context, url, error) =>
          errorWidget ??
          (Constant.placeholderImage.isEmpty
              ? Icon(
                  Icons.image_not_supported_outlined,
                  size: h,
                  color: color,
                )
              : CachedNetworkImage(
                  // Image de remplacement elle aussi mise en cache (avant :
                  // Image.network, retelechargee a chaque affichage).
                  imageUrl: Constant.placeholderImage,
                  fit: fit ?? BoxFit.fitWidth,
                  height: h,
                  width: w,
                  memCacheWidth: decodeSize,
                )),
    );
  }
}
