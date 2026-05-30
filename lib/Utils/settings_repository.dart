import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ServerDirectorySettings {
  const ServerDirectorySettings({
    required this.useDefaultDirectory,
    required this.customDirectoryPath,
  });

  static const String defaultDirectoryPath =
      '/storage/emulated/0/Bifrost';

  final bool useDefaultDirectory;
  final String customDirectoryPath;

  String get effectiveDirectoryPath {
    if (useDefaultDirectory || customDirectoryPath.trim().isEmpty) {
      return defaultDirectoryPath;
    }

    return customDirectoryPath.trim();
  }

  ServerDirectorySettings copyWith({
    bool? useDefaultDirectory,
    String? customDirectoryPath,
  }) {
    return ServerDirectorySettings(
      useDefaultDirectory:
          useDefaultDirectory ?? this.useDefaultDirectory,
      customDirectoryPath:
          customDirectoryPath ?? this.customDirectoryPath,
    );
  }
}

class AppSettings {
  static bool disableAnimations = false;
  static final ValueNotifier<String> themeNotifier = ValueNotifier<String>('teal');
}

class SettingsRepository {
  const SettingsRepository();

  static const String _useDefaultDirectoryKey = 'use_default_server_directory';
  static const String _customDirectoryPathKey = 'custom_server_directory_path';
  static const String _disableAnimationsKey = 'disable_animations';
  static const String _appThemeKey = 'app_theme';
  static const String _onboardingCompletedKey = 'onboarding_completed';

  Future<ServerDirectorySettings> loadServerDirectorySettings() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    return ServerDirectorySettings(
      useDefaultDirectory:
          preferences.getBool(_useDefaultDirectoryKey) ?? true,
      customDirectoryPath:
          preferences.getString(_customDirectoryPathKey) ?? '',
    );
  }

  Future<void> saveServerDirectorySettings(
    ServerDirectorySettings settings,
  ) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setBool(
      _useDefaultDirectoryKey,
      settings.useDefaultDirectory,
    );
    await preferences.setString(
      _customDirectoryPathKey,
      settings.customDirectoryPath,
    );
  }

  Future<bool> loadDisableAnimations() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_disableAnimationsKey) ?? false;
  }

  Future<void> saveDisableAnimations(bool value) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_disableAnimationsKey, value);
    AppSettings.disableAnimations = value;
  }

  Future<String> loadAppTheme() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getString(_appThemeKey) ?? 'teal';
  }

  Future<void> saveAppTheme(String value) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setString(_appThemeKey, value);
    AppSettings.themeNotifier.value = value;
  }

  Future<bool> loadOnboardingCompleted() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_onboardingCompletedKey) ?? false;
  }

  Future<void> saveOnboardingCompleted(bool value) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_onboardingCompletedKey, value);
  }
}
