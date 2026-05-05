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

class PlayitTunnelSettings {
  const PlayitTunnelSettings({
    required this.enabled,
    required this.autoStart,
    required this.executablePath,
  });

  final bool enabled;
  final bool autoStart;
  final String executablePath;

  bool get isConfigured =>
      enabled && executablePath.trim().isNotEmpty;

  PlayitTunnelSettings copyWith({
    bool? enabled,
    bool? autoStart,
    String? executablePath,
  }) {
    return PlayitTunnelSettings(
      enabled: enabled ?? this.enabled,
      autoStart: autoStart ?? this.autoStart,
      executablePath: executablePath ?? this.executablePath,
    );
  }

  static const PlayitTunnelSettings defaults = PlayitTunnelSettings(
    enabled: false,
    autoStart: true,
    executablePath: '',
  );
}

class SettingsRepository {
  const SettingsRepository();

  static const String _useDefaultDirectoryKey = 'use_default_server_directory';
  static const String _customDirectoryPathKey = 'custom_server_directory_path';
  static const String _customDirectoryUriKey = 'custom_server_directory_uri';
  static const String _playitEnabledKey = 'playit_tunnel_enabled';
  static const String _playitAutoStartKey = 'playit_tunnel_auto_start';
  static const String _playitExecutablePathKey =
      'playit_tunnel_executable_path';

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

  Future<PlayitTunnelSettings> loadPlayitTunnelSettings() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    return PlayitTunnelSettings(
      enabled: preferences.getBool(_playitEnabledKey) ??
          PlayitTunnelSettings.defaults.enabled,
      autoStart: preferences.getBool(_playitAutoStartKey) ??
          PlayitTunnelSettings.defaults.autoStart,
      executablePath: preferences.getString(_playitExecutablePathKey) ??
          PlayitTunnelSettings.defaults.executablePath,
    );
  }

  Future<void> savePlayitTunnelSettings(
    PlayitTunnelSettings settings,
  ) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_playitEnabledKey, settings.enabled);
    await preferences.setBool(_playitAutoStartKey, settings.autoStart);
    await preferences.setString(
      _playitExecutablePathKey,
      settings.executablePath,
    );
  }
}
