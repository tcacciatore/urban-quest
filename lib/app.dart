import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'presentation/screens/home/home_screen.dart';

class UrbanQuestApp extends StatelessWidget {
  const UrbanQuestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Urban Quest',
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      home: const HomeScreen(),
    );
  }
}
