import 'package:shared_preferences/shared_preferences.dart';

class ServerDirectorySettings {
  const ServerDirectorySettings({
    required this.useDefaultDirectory,
    required this.customDirectoryPath,
  });

  static const String defaultDirectoryPath = 'internal storage/minecraft';

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

class SettingsRepository {
  const SettingsRepository();

  static const String _useDefaultDirectoryKey = 'use_default_server_directory';
  static const String _customDirectoryPathKey = 'custom_server_directory_path';

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
}
