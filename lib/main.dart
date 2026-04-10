import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'data/repositories/quarter_repository.dart';
import 'data/repositories/city_repository.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  await QuarterRepository.initHive();
  await CityRepository.initHive();
  runApp(
    const ProviderScope(
      child: UrbanQuestApp(),
    ),
  );
}
