import 'package:flutter/material.dart';


class AppThemeData {
  static const Color primary50 = Color(0xFFFFEBE5);
  static const Color primary100 = Color(0xFFFFC0AB);
  static const Color primary200 = Color(0xFFFF9472);
  static Color primary300 = const Color.fromRGBO(255, 106, 0, 1);
  static const Color primary400 = Color(0xFFB24826);
  static const Color primary500 = Color(0xFF662713);
  static const Color primary600 = Color(0xFF1A0600);

  static const Color surface = Color(0xFFF9FAFB);
  static const Color surfaceDark = Color(0xFF030712);

  static const Color info50 = Color(0xFFE5F9FF);
  static const Color info100 = Color(0xFFACECFF);
  static const Color info200 = Color(0xFF72DEFF);
  static const Color info300 = Color(0xFF38D0FF);
  static const Color info400 = Color(0xFF2692B2);
  static const Color info500 = Color(0xFF135366);
  static const Color info600 = Color(0xFF00141A);

  static const Color danger50 = Color(0xFFFFE5E6);
  static const Color danger100 = Color(0xFFFFACAE);
  static const Color danger200 = Color(0xFFFF7277);
  static const Color danger300 = Color(0xFFFF3840);
  static const Color danger400 = Color(0xFFB2262B);
  static const Color danger500 = Color(0xFF661316);
  static const Color danger600 = Color(0xFF1A0001);

  static const Color secondary50 = Color(0xFFEBE5FF);
  static const Color secondary100 = Color(0xFFC0ABFF);
  static const Color secondary200 = Color(0xFF9472FF);
  static const Color secondary300 = Color(0xFF6839FF);
  static const Color secondary400 = Color(0xFF4826B2);
  static const Color secondary500 = Color(0xFF271366);
  static const Color secondary600 = Color(0xFF06001A);

  static const Color success50 = Color(0xFFE5FFF5);
  static const Color success100 = Color(0xFFA1FFD9);
  static const Color success200 = Color(0xFF5DFFBE);
  static const Color success300 = Color(0xFF19FFA3);
  static const Color success400 = Color(0xFF10B271);
  static const Color success500 = Color(0xFF086640);
  static const Color success600 = Color(0xFF001A0F);
  static const Color lightGreen = Color(0XFFEFF9EB);
  static const Color darkGreen = Color(0XFF3F8826);

  static const Color warning50 = Color(0xFFFFF8E5);
  static const Color warning100 = Color(0xFFFFE9AB);
  static const Color warning200 = Color(0xFFFFDA72);
  static const Color warning300 = Color(0xFFFFCB39);
  static const Color warning400 = Color(0xFFB28D26);
  static const Color warning500 = Color(0xFF665013);
  static const Color warning600 = Color(0xFF191200);

  static const Color grey50 = Color(0xFFFFFFFF);
  static const Color grey100 = Color(0xFFF3F4F6);
  static const Color grey200 = Color(0xFFE5E7EB);
  static const Color grey300 = Color(0xFFD1D5DB);
  static const Color grey400 = Color(0xFF9CA3AF);
  static const Color grey500 = Color(0xFF6B7280);
  static const Color grey600 = Color(0xFF4B5563);
  static const Color grey700 = Color(0xFF374151);
  static const Color grey800 = Color(0xFF1F2937);
  static const Color grey900 = Color(0xFF111827);
  static const Color outrageous300 = Color(0xFFFF6839);

  static const String black = 'Urbanist-Black';
  static const String bold = 'Urbanist-Bold';
  static const String extraBold = 'Urbanist-ExtraBold';
  static const String extraLight = 'Urbanist-ExtraLight';
  static const String light = 'Urbanist-Light';
  static const String medium = 'Urbanist-Medium';
  static const String regular = 'Urbanist-Regular';
  static const String semiBold = 'Urbanist-SemiBold';
  static const String thin = 'Urbanist-Thin';

  // ─────────────────────────────────────────────────────────────
  //  Jetons de design Foodie 9.2 (couche additive)
  //  Degrades, ombres, rayons et espacements. La palette ne change pas :
  //  la couleur de marque reste l'orange Viteat (primary300), et les
  //  degrades en sont DERIVES pour suivre app_customer_color de l'admin.
  // ─────────────────────────────────────────────────────────────

  /// Decale la luminosite HSL d'une couleur (teintes de degrade).
  static Color shiftLightness(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
  }

  /// Teintes du degrade de marque, derivees de [primary300] (getters : elles
  /// suivent la couleur dynamique fixee depuis l'admin).
  static Color get primaryGradientStart => shiftLightness(primary300, 0.06);
  static Color get primaryGradientEnd => shiftLightness(primary300, -0.05);

  static LinearGradient get primaryGradient => LinearGradient(
        colors: [primaryGradientStart, primaryGradientEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  /// Degrade plus doux pour les grandes surfaces (splash, en-tetes, cartes).
  static LinearGradient get brandGradientSoft => LinearGradient(
        colors: [shiftLightness(primary300, 0.09), shiftLightness(primary300, -0.02)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );

  /// Voile pose sur les photos de plats pour garder le texte lisible.
  static const LinearGradient imageScrim = LinearGradient(
    colors: [Colors.transparent, Color(0xCC000000)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Echelle des rayons.
  static const double radiusSm = 10;
  static const double radiusMd = 16;
  static const double radiusLg = 22;
  static const double radiusXl = 28;
  static const double radiusPill = 100;

  // Echelle des espacements (base 4 pt).
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;

  /// Ombre douce des cartes sur fond clair.
  static List<BoxShadow> cardShadow = [
    BoxShadow(
      color: grey900.withValues(alpha: 0.06),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];

  /// Halo colore sous les boutons principaux (suit la couleur dynamique).
  static List<BoxShadow> get primaryGlow => [
        BoxShadow(
          color: primary300.withValues(alpha: 0.35),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ];

  /// Ombre des elements flottants (barre de navigation, boutons flottants).
  static List<BoxShadow> floatShadow = [
    BoxShadow(
      color: grey900.withValues(alpha: 0.10),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];
}
