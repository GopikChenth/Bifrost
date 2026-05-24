import 'package:flutter/material.dart';
import 'package:bifrost/Pages/bifrost_dashboard.dart';
import 'package:bifrost/Utils/settings_repository.dart';
import 'package:bifrost/Components/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SettingsRepository settingsRepo = const SettingsRepository();
  AppSettings.disableAnimations = await settingsRepo.loadDisableAnimations();
  AppSettings.themeNotifier.value = await settingsRepo.loadAppTheme();
  runApp(const BifrostApp());
}

class BifrostApp extends StatelessWidget {
  const BifrostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppSettings.themeNotifier,
      builder: (BuildContext context, String currentTheme, Widget? child) {
        return MaterialApp(
          title: 'Bifrost',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.dark,
          darkTheme: AppTheme.buildTheme(currentTheme),
          home: const HomePage(),
        );
      },
    );
  }
}

