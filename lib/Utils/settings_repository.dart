import 'package:shared_preferences/shared_preferences.dart';

class ServerDirectorySettings {
  const ServerDirectorySettings({
    required this.useDefaultDirectory,
    required this.customDirectoryPath,
    required this.customDirectoryUri,
  });

  static const String defaultDirectoryPath =
      'App storage (persistent) /minecraft';

  final bool useDefaultDirectory;
  final String customDirectoryPath;
  final String customDirectoryUri;

  String get effectiveDirectoryPath {
    if (useDefaultDirectory || customDirectoryPath.trim().isEmpty) {
      return defaultDirectoryPath;
    }

    return customDirectoryPath.trim();
  }

  ServerDirectorySettings copyWith({
    bool? useDefaultDirectory,
    String? customDirectoryPath,
    String? customDirectoryUri,
  }) {
    return ServerDirectorySettings(
      useDefaultDirectory:
          useDefaultDirectory ?? this.useDefaultDirectory,
      customDirectoryPath:
          customDirectoryPath ?? this.customDirectoryPath,
      customDirectoryUri:
          customDirectoryUri ?? this.customDirectoryUri,
    );
  }
}

class SettingsRepository {
  const SettingsRepository();

  static const String _useDefaultDirectoryKey = 'use_default_server_directory';
  static const String _customDirectoryPathKey = 'custom_server_directory_path';
  static const String _customDirectoryUriKey = 'custom_server_directory_uri';

  Future<ServerDirectorySettings> loadServerDirectorySettings() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    return ServerDirectorySettings(
      useDefaultDirectory:
          preferences.getBool(_useDefaultDirectoryKey) ?? true,
      customDirectoryPath:
          preferences.getString(_customDirectoryPathKey) ?? '',
      customDirectoryUri:
          preferences.getString(_customDirectoryUriKey) ?? '',
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
    await preferences.setString(
      _customDirectoryUriKey,
      settings.customDirectoryUri,
    );
  }

}
