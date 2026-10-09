import 'package:customer/models/vendor_model.dart';
import 'package:customer/utils/fire_store_utils.dart';
import 'package:flutter/material.dart';

/// Pastille bleue « Restaurant verifie par Viteat » (champ `isVerified` ecrit
/// par le backend). Rosette #1877F2 a coche blanche, lisible en clair comme en
/// sombre. Ne rend rien si le restaurant n'est pas verifie.
///
/// A placer a droite du nom dans une `Row`, le nom etant enveloppe dans un
/// `Flexible` pour conserver la troncature (ellipsis).
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, required this.isVerified, this.size = 16, this.spacing = 4});

  final bool? isVerified;
  final double size;
  final double spacing;

  static const Color color = Color(0xFF1877F2);
  static const String label = 'Restaurant vérifié par Viteat';

  @override
  Widget build(BuildContext context) {
    if (isVerified != true) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsetsDirectional.only(start: spacing),
      child: Tooltip(
        message: label,
        child: Semantics(
          label: label,
          image: true,
          excludeSemantics: true,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Fond blanc sous la coche : l'icone Material laisse la coche
                // transparente, elle doit rester blanche meme sur fond sombre.
                Container(
                  width: size * 0.55,
                  height: size * 0.55,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                ),
                Icon(Icons.verified, color: color, size: size),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Badge pour un restaurant COPIE dans un document (reservation, commande) :
/// la copie date du moment de l'enregistrement et ne porte souvent pas
/// `isVerified`. Si elle ne dit pas « verifie », on lit l'etat actuel du
/// restaurant (lecture memorisee, partagee avec le reste de l'app).
class LiveVerifiedBadge extends StatelessWidget {
  const LiveVerifiedBadge({super.key, required this.vendor, this.size = 16});

  final VendorModel? vendor;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (vendor?.isVerified == true) return VerifiedBadge(isVerified: true, size: size);
    final String id = vendor?.id ?? '';
    if (id.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<VendorModel?>(
      future: FireStoreUtils.getVendorByIdCached(id),
      builder: (context, snapshot) => VerifiedBadge(isVerified: snapshot.data?.isVerified, size: size),
    );
  }
}
