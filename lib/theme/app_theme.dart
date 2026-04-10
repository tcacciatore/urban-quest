import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_text.dart';

ThemeData appTheme = ThemeData(
  scaffoldBackgroundColor: AppColors.parchment,
  textTheme: GoogleFonts.frauncesTextTheme(),
  colorScheme: const ColorScheme.light(
    primary: AppColors.terra,
    secondary: AppColors.forest,
    surface: AppColors.white,
    onPrimary: AppColors.parchment,
    onSecondary: AppColors.parchment,
    onSurface: AppColors.ink,
  ),
  dividerColor: AppColors.sandLight,
  appBarTheme: AppBarTheme(
    backgroundColor: AppColors.parchment,
    foregroundColor: AppColors.ink,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: AppText.sectionTitle,
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: AppColors.parchment,
    selectedItemColor: AppColors.terra,
    unselectedItemColor: AppColors.sand,
    elevation: 0,
  ),
);
