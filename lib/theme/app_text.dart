import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppText {
  // Titres principaux — Fraunces italic
  static TextStyle get displayTitle => GoogleFonts.fraunces(
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w300,
        fontSize: 44,
        color: AppColors.ink,
        height: 1.0,
        letterSpacing: -0.5,
      );

  // Titres de section
  static TextStyle get sectionTitle => GoogleFonts.fraunces(
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w300,
        fontSize: 30,
        color: AppColors.ink,
        height: 1.1,
      );

  // Labels et metadata — DM Mono
  static TextStyle get label => GoogleFonts.dmMono(
        fontWeight: FontWeight.w400,
        fontSize: 11,
        color: AppColors.sand,
        letterSpacing: 2.5,
      );

  // Chiffres — DM Mono
  static TextStyle get metric => GoogleFonts.dmMono(
        fontWeight: FontWeight.w400,
        fontSize: 16,
        color: AppColors.ink,
      );

  // Indices poétiques — Fraunces italic
  static TextStyle get hint => GoogleFonts.fraunces(
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w300,
        fontSize: 16,
        color: AppColors.ink,
        height: 1.6,
      );

  // Corps de texte — système
  static TextStyle get body => const TextStyle(
        fontSize: 16,
        color: AppColors.ink,
        height: 1.5,
      );
}
