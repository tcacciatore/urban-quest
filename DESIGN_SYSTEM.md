# Design System — la chasse

## Philosophie
Aventure et mystère, fond clair style carnet de voyage. Inspiré de Headspace : épuré, aéré, jamais froid. Chaque élément visuel doit évoquer la découverte urbaine.

---

## Couleurs

```dart
// lib/theme/app_colors.dart

class AppColors {
  // Fonds
  static const Color parchment   = Color(0xFFF5F2EC); // fond principal
  static const Color white       = Color(0xFFFFFFFF); // cards, surfaces élevées

  // Texte
  static const Color ink         = Color(0xFF2C2010); // texte principal
  static const Color sand        = Color(0xFFC8BAA0); // texte secondaire, placeholders
  static const Color sandLight   = Color(0xFFE8E0D0); // bordures, séparateurs

  // Accents
  static const Color terra       = Color(0xFF7B4F2E); // CTA, sélections, titres forts — couleur de l'aventure
  static const Color terraLight  = Color(0x1A7B4F2E); // fond des éléments sélectionnés (10% terra)
  static const Color forest      = Color(0xFF1A6B52); // victoire, arrivée, onglet actif — rare = fort
  static const Color forestLight = Color(0x1A1A6B52); // fond confirmation (10% forest)
}
```

### Règles d'usage
- **Terra** → tout ce qui est interactif : boutons primaires, pills sélectionnées, titres forts
- **Forest** → uniquement victoire, arrivée, onglet actif. Ne pas diluer.
- **Parchment** → fond principal, jamais blanc pur
- **Sand** → texte secondaire, métadonnées, labels — jamais de gris standard
- **SandLight** → bordures et séparateurs uniquement

---

## Typographie

```dart
// lib/theme/app_text.dart
// Fonts à ajouter dans pubspec.yaml :
// - Fraunces (Google Fonts) — serif display
// - DM Mono (Google Fonts) — monospace labels

class AppText {
  // Titres principaux — Fraunces italic
  static const TextStyle displayTitle = TextStyle(
    fontFamily: 'Fraunces',
    fontStyle: FontStyle.italic,
    fontWeight: FontWeight.w300,
    fontSize: 42,
    color: AppColors.ink,
    height: 1.0,
    letterSpacing: -0.5,
  );

  // Titres de section
  static const TextStyle sectionTitle = TextStyle(
    fontFamily: 'Fraunces',
    fontStyle: FontStyle.italic,
    fontWeight: FontWeight.w300,
    fontSize: 28,
    color: AppColors.ink,
    height: 1.1,
  );

  // Labels et metadata — DM Mono
  static const TextStyle label = TextStyle(
    fontFamily: 'DM Mono',
    fontWeight: FontWeight.w400,
    fontSize: 9,
    color: AppColors.sand,
    letterSpacing: 2.5,
  );

  // Chiffres — DM Mono
  static const TextStyle metric = TextStyle(
    fontFamily: 'DM Mono',
    fontWeight: FontWeight.w400,
    fontSize: 14,
    color: AppColors.ink,
  );

  // Indices poétiques — Fraunces italic
  static const TextStyle hint = TextStyle(
    fontFamily: 'Fraunces',
    fontStyle: FontStyle.italic,
    fontWeight: FontWeight.w300,
    fontSize: 14,
    color: AppColors.ink,
    height: 1.6,
  );

  // Corps de texte — système
  static const TextStyle body = TextStyle(
    fontSize: 14,
    color: AppColors.ink,
    height: 1.5,
  );
}
```

---

## Composants

### Bouton primaire
```dart
// Fond encre, texte parchemin, DM Mono uppercase
ElevatedButton(
  style: ElevatedButton.styleFrom(
    backgroundColor: AppColors.ink,
    foregroundColor: AppColors.parchment,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    padding: EdgeInsets.symmetric(vertical: 14),
    textStyle: AppText.label.copyWith(fontSize: 10, letterSpacing: 3),
  ),
)
```

### Bouton secondaire (outline)
```dart
// Bordure terra, fond terraLight, texte terra
OutlinedButton(
  style: OutlinedButton.styleFrom(
    side: BorderSide(color: AppColors.terra.withOpacity(0.5)),
    backgroundColor: AppColors.terraLight,
    foregroundColor: AppColors.terra,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    padding: EdgeInsets.symmetric(vertical: 14),
    textStyle: AppText.label.copyWith(fontSize: 10, letterSpacing: 3, color: AppColors.terra),
  ),
)
```

### Card
```dart
Container(
  decoration: BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: AppColors.sandLight, width: 0.5),
  ),
  padding: EdgeInsets.all(14),
)
```

### Pill émotion (non sélectionnée)
```dart
Container(
  decoration: BoxDecoration(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: AppColors.sandLight),
  ),
  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
)
```

### Pill émotion (sélectionnée)
```dart
Container(
  decoration: BoxDecoration(
    color: AppColors.terraLight,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: AppColors.terra.withOpacity(0.6), width: 1.5),
  ),
)
```

### Indice box
```dart
Container(
  decoration: BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: AppColors.sandLight, width: 0.5),
  ),
  padding: EdgeInsets.all(14),
  child: Column(children: [
    Text('INDICE', style: AppText.label),
    SizedBox(height: 6),
    Text(indiceText, style: AppText.hint),
  ]),
)
```

---

## Thème Flutter global

```dart
// lib/theme/app_theme.dart

ThemeData appTheme = ThemeData(
  scaffoldBackgroundColor: AppColors.parchment,
  fontFamily: 'Fraunces',
  colorScheme: ColorScheme.light(
    primary: AppColors.terra,
    secondary: AppColors.forest,
    surface: AppColors.white,
    background: AppColors.parchment,
    onPrimary: AppColors.parchment,
    onSecondary: AppColors.parchment,
    onSurface: AppColors.ink,
    onBackground: AppColors.ink,
  ),
  dividerColor: AppColors.sandLight,
  appBarTheme: AppBarTheme(
    backgroundColor: AppColors.parchment,
    foregroundColor: AppColors.ink,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: AppText.sectionTitle,
  ),
  bottomNavigationBarTheme: BottomNavigationBarThemeData(
    backgroundColor: AppColors.parchment,
    selectedItemColor: AppColors.terra,
    unselectedItemColor: AppColors.sand,
    elevation: 0,
  ),
);
```

---

## Espacements

```dart
class AppSpacing {
  static const double xs  = 4;
  static const double sm  = 8;
  static const double md  = 14;
  static const double lg  = 20;
  static const double xl  = 28;
  static const double xxl = 40;
}
```

---

## À dire à Claude Code

Colle ce prompt au début de chaque demande UI :

> "Consulte le fichier DESIGN_SYSTEM.md à la racine avant de coder. Respecte strictement les couleurs AppColors, la typographie AppText, et les styles de composants définis. N'utilise jamais de blanc pur (#FFFFFF) comme fond de page, jamais de gris standard pour le texte secondaire, jamais d'Inter ou Roboto. Fond principal = parchment, accent principal = terra, accent victoire = forest."
