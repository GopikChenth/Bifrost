import 'dart:convert';
import 'dart:io';

import 'package:bifrost/Components/add_server_window.dart';
import 'package:bifrost/Services/storage_access_service.dart';
import 'package:bifrost/Utils/settings_repository.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class ServerStorageException implements Exception {
  const ServerStorageException(this.message);

  final String message;

  @override
  String toString() => 'ServerStorageException: $message';
}

class ServerStorageResult {
  const ServerStorageResult({
    required this.serverDirectory,
    required this.worldDirectory,
    required this.jarsDirectory,
    required this.modsDirectory,
    required this.backupsDirectory,
    required this.propertiesFile,
    required this.metadataFile,
    this.serverUri,
    this.jarsUri,
    this.metadataUri,
  });

  final Directory serverDirectory;
  final Directory worldDirectory;
  final Directory jarsDirectory;
  final Directory modsDirectory;
  final Directory backupsDirectory;
  final File propertiesFile;
  final File metadataFile;
  final String? serverUri;
  final String? jarsUri;
  final String? metadataUri;
}

class ServerLaunchConfig {
  const ServerLaunchConfig({
    required this.serverDirectory,
    required this.jarFilePath,
    required this.maxRamMb,
    required this.metadataFile,
  });

  final Directory serverDirectory;
  final String jarFilePath;
  final int maxRamMb;
  final File metadataFile;
}

class ServerStorageService {
  const ServerStorageService({
    SettingsRepository settingsRepository = const SettingsRepository(),
    StorageAccessService storageAccessService = const StorageAccessService(),
  }) : _settingsRepository = settingsRepository,
       _storageAccessService = storageAccessService;

  final SettingsRepository _settingsRepository;
  final StorageAccessService _storageAccessService;

  Future<ServerStorageResult> createServerStructure(
    AddServerResult server,
  ) async {
    try {
      final ServerDirectorySettings settings =
          await _settingsRepository.loadServerDirectorySettings();
      if (_usesCustomTreeStorage(settings)) {
        final Map<String, Object?> result = await _storageAccessService
            .createServerStructure(
              treeUri: settings.customDirectoryUri,
              serverName: server.name,
              version: server.version,
              serverType: server.serverType,
              memoryLabel: server.memoryLabel,
              serverProperties: _buildServerProperties(server),
            );
        return _storageResultFromMap(result);
      }

      final String baseDirectoryPath = await resolveBaseDirectoryPath();
      final Directory baseDirectory = Directory(baseDirectoryPath);
      await baseDirectory.create(recursive: true);
      await _validateWritableBaseDirectory(baseDirectory);

      final Directory serverDirectory = await _createUniqueServerDirectory(
        baseDirectory,
        server.name,
      );

      final Directory worldDirectory = Directory(
        path.join(serverDirectory.path, 'world'),
      );
      final Directory jarsDirectory = Directory(
        path.join(serverDirectory.path, 'jars'),
      );
      final Directory modsDirectory = Directory(
        path.join(serverDirectory.path, 'mods'),
      );
      final Directory backupsDirectory = Directory(
        path.join(serverDirectory.path, 'backups'),
      );

      await worldDirectory.create(recursive: true);
      await jarsDirectory.create(recursive: true);
      await modsDirectory.create(recursive: true);
      await backupsDirectory.create(recursive: true);

      final File propertiesFile = File(
        path.join(serverDirectory.path, 'server.properties'),
      );
      final File metadataFile = File(
        path.join(serverDirectory.path, 'bifrost_server.json'),
      );

      await propertiesFile.writeAsString(_buildServerProperties(server));
      await metadataFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'name': server.name,
          'version': server.version,
          'type': server.serverType,
          'allocatedRam': server.memoryLabel,
          'download': null,
          'paths': <String, String>{
            'root': serverDirectory.path,
            'world': worldDirectory.path,
            'jars': jarsDirectory.path,
            'mods': modsDirectory.path,
            'backups': backupsDirectory.path,
            'properties': propertiesFile.path,
          },
        }),
      );

      return ServerStorageResult(
        serverDirectory: serverDirectory,
        worldDirectory: worldDirectory,
        jarsDirectory: jarsDirectory,
        modsDirectory: modsDirectory,
        backupsDirectory: backupsDirectory,
        propertiesFile: propertiesFile,
        metadataFile: metadataFile,
      );
    } on FileSystemException catch (error) {
      throw ServerStorageException(
        'Unable to write server files at ${error.path ?? 'the selected directory'}: ${error.message}',
      );
    } catch (error) {
      throw ServerStorageException('Unable to create server storage: $error');
    }
  }

  Future<List<Map<String, Object>>> loadStoredServers() async {
    try {
      final ServerDirectorySettings settings =
          await _settingsRepository.loadServerDirectorySettings();
      if (_usesCustomTreeStorage(settings)) {
        final List<Map<String, Object?>> rawServers =
            await _storageAccessService.loadStoredServers(
              treeUri: settings.customDirectoryUri,
            );
        return rawServers.map(_serverMapFromRaw).toList();
      }

      final Directory baseDirectory = Directory(await resolveBaseDirectoryPath());
      if (!await baseDirectory.exists()) {
        return <Map<String, Object>>[];
      }

      final List<Map<String, Object>> servers = <Map<String, Object>>[];
      await for (final FileSystemEntity entity in baseDirectory.list()) {
        if (entity is! Directory) {
          continue;
        }

        final File metadataFile = File(
          path.join(entity.path, 'bifrost_server.json'),
        );
        if (!await metadataFile.exists()) {
          continue;
        }

        try {
          final Map<String, dynamic> metadata =
              jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
          final Map<String, dynamic>? paths = metadata['paths'] as Map<String, dynamic>?;

          servers.add(<String, Object>{
            'name': (metadata['name'] as String?)?.trim().isNotEmpty == true
                ? metadata['name'] as String
                : path.basename(entity.path),
            'version': (metadata['version'] as String?) ?? 'Unknown',
            'type': (metadata['type'] as String?) ?? 'Unknown',
            'status': 'Offline',
            'memory': (metadata['allocatedRam'] as String?) ?? '2.0 GB',
            'isOnline': false,
            'path': (paths?['root'] as String?) ?? entity.path,
          });
        } catch (_) {
          continue;
        }
      }

      servers.sort((Map<String, Object> a, Map<String, Object> b) {
        return (a['name'] as String).toLowerCase().compareTo(
          (b['name'] as String).toLowerCase(),
        );
      });
      return servers;
    } on FileSystemException catch (error) {
      throw ServerStorageException(
        'Unable to read stored servers at ${error.path ?? 'the server directory'}: ${error.message}',
      );
    } catch (error) {
      throw ServerStorageException('Unable to load stored servers: $error');
    }
  }

  Future<String> resolveBaseDirectoryPath() async {
    final ServerDirectorySettings settings =
        await _settingsRepository.loadServerDirectorySettings();
    if (!settings.useDefaultDirectory) {
      final String customDirectoryPath = settings.customDirectoryPath.trim();
      if (customDirectoryPath.isNotEmpty &&
          _isDirectFilesystemPath(customDirectoryPath)) {
        return path.join(customDirectoryPath, 'minecraft');
      }
    }

    return _resolveDefaultBaseDirectoryPath();
  }

  Future<void> writeDownloadMetadata({
    required ServerStorageResult storage,
    required Map<String, Object?> downloadMetadata,
  }) async {
    try {
      if (storage.metadataUri != null) {
        await _storageAccessService.writeDownloadMetadata(
          metadataUri: storage.metadataUri!,
          downloadMetadata: downloadMetadata,
        );
        return;
      }

      final Map<String, dynamic> currentMetadata =
          jsonDecode(await storage.metadataFile.readAsString())
              as Map<String, dynamic>;

      currentMetadata['download'] = downloadMetadata;

      await storage.metadataFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(currentMetadata),
      );
    } on FileSystemException catch (error) {
      throw ServerStorageException(
        'Unable to update server metadata at ${error.path ?? storage.metadataFile.path}: ${error.message}',
      );
    } catch (error) {
      throw ServerStorageException('Unable to update server metadata: $error');
    }
  }

  Future<void> deleteServerDirectory(
    String serverPath, {
    String? serverUri,
  }) async {
    try {
      final ServerDirectorySettings settings =
          await _settingsRepository.loadServerDirectorySettings();
      if (_usesCustomTreeStorage(settings)) {
        await _storageAccessService.deleteServerDirectory(
          treeUri: settings.customDirectoryUri,
          serverUri: serverUri?.trim().isNotEmpty == true ? serverUri : null,
          serverPath: serverPath,
        );
        return;
      }

      Directory serverDirectory = Directory(serverPath);
      if (!await serverDirectory.exists()) {
        final File metadataFile = File(
          path.join(serverPath, 'bifrost_server.json'),
        );
        if (await metadataFile.exists()) {
          final Map<String, dynamic> metadata =
              jsonDecode(await metadataFile.readAsString())
                  as Map<String, dynamic>;
          final Map<String, dynamic>? paths =
              metadata['paths'] as Map<String, dynamic>?;
          final String? rootPath = paths?['root'] as String?;
          if (rootPath != null && rootPath.trim().isNotEmpty) {
            serverDirectory = Directory(rootPath);
          }
        }
      }

      if (!await serverDirectory.exists()) {
        return;
      }

      await serverDirectory.delete(recursive: true);
      if (await serverDirectory.exists()) {
        throw ServerStorageException(
          'Server files still exist at ${serverDirectory.path} after deletion.',
        );
      }
    } on FileSystemException catch (error) {
      throw ServerStorageException(
        'Unable to delete server files at ${error.path ?? serverPath}: ${error.message}',
      );
    } catch (error) {
      throw ServerStorageException('Unable to delete server storage: $error');
    }
  }

  Future<ServerLaunchConfig> prepareServerLaunch({
    required String serverPath,
    required String memoryLabel,
    String? serverUri,
  }) async {
    try {
      final ServerDirectorySettings settings =
          await _settingsRepository.loadServerDirectorySettings();
      if (_usesCustomTreeStorage(settings) &&
          serverUri != null &&
          serverUri.trim().isNotEmpty) {
        final Map<String, Object?> launchResult =
            await _storageAccessService.prepareServerLaunch(
              serverUri: serverUri,
            );
        final String safServerPath =
            (launchResult['serverPath'] as String?)?.trim().isNotEmpty == true
            ? launchResult['serverPath'] as String
            : serverPath;
        final String safJarFilePath =
            ((launchResult['jarPath'] as String?) ?? '').trim();

        if (safJarFilePath.isEmpty) {
          throw const ServerStorageException(
            'No downloaded server jar is registered for this server yet.',
          );
        }

        final String mirrorPath = await _resolveRuntimeMirrorPath(safServerPath);
        final Map<String, Object?> mirroredLaunch =
            await _storageAccessService.copyServerToDirectory(
              serverUri: serverUri,
              destinationPath: mirrorPath,
            );
        final String resolvedServerPath =
            ((mirroredLaunch['serverPath'] as String?) ?? mirrorPath).trim();
        final String jarFilePath =
            ((mirroredLaunch['jarPath'] as String?) ?? '').trim();

        if (jarFilePath.isEmpty || !await File(jarFilePath).exists()) {
          throw ServerStorageException(
            'The server jar could not be prepared in app storage for launch.',
          );
        }

        return ServerLaunchConfig(
          serverDirectory: Directory(resolvedServerPath),
          jarFilePath: jarFilePath,
          maxRamMb: _parseMemoryLabelToMb(memoryLabel),
          metadataFile: File(path.join(resolvedServerPath, 'bifrost_server.json')),
        );
      }

      final Directory serverDirectory = Directory(serverPath);
      if (!await serverDirectory.exists()) {
        throw const ServerStorageException(
          'The selected server directory no longer exists.',
        );
      }

      final File metadataFile = File(
        path.join(serverDirectory.path, 'bifrost_server.json'),
      );
      if (!await metadataFile.exists()) {
        throw const ServerStorageException(
          'bifrost_server.json is missing for this server.',
        );
      }

      final Map<String, dynamic> metadata =
          jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
      final Map<String, dynamic>? download =
          metadata['download'] as Map<String, dynamic>?;
      final String? jarFilePath = download?['path'] as String?;

      if (jarFilePath == null || jarFilePath.trim().isEmpty) {
        throw const ServerStorageException(
          'No downloaded server jar is registered for this server yet.',
        );
      }

      final File jarFile = File(jarFilePath);
      if (!await jarFile.exists()) {
        throw ServerStorageException(
          'The configured server jar was not found at $jarFilePath.',
        );
      }

      final File eulaFile = File(path.join(serverDirectory.path, 'eula.txt'));
      await eulaFile.writeAsString('eula=true\n');

      return ServerLaunchConfig(
        serverDirectory: serverDirectory,
        jarFilePath: jarFile.path,
        maxRamMb: _parseMemoryLabelToMb(memoryLabel),
        metadataFile: metadataFile,
      );
    } on ServerStorageException {
      rethrow;
    } on FileSystemException catch (error) {
      throw ServerStorageException(
        'Unable to prepare server launch at ${error.path ?? serverPath}: ${error.message}',
      );
    } catch (error) {
      throw ServerStorageException('Unable to prepare the server launch: $error');
    }
  }

  Future<void> syncRuntimeMirrorToServer({
    required String serverPath,
    String? serverUri,
  }) async {
    try {
      final ServerDirectorySettings settings =
          await _settingsRepository.loadServerDirectorySettings();
      if (!_usesCustomTreeStorage(settings) ||
          serverUri == null ||
          serverUri.trim().isEmpty) {
        return;
      }

      final String mirrorPath = await _resolveRuntimeMirrorPath(serverPath);
      final Directory mirrorDirectory = Directory(mirrorPath);
      if (!await mirrorDirectory.exists()) {
        return;
      }

      await _storageAccessService.syncDirectoryToServer(
        serverUri: serverUri,
        sourcePath: mirrorPath,
      );
    } on FileSystemException catch (error) {
      throw ServerStorageException(
        'Unable to sync server files from ${error.path ?? serverPath}: ${error.message}',
      );
    } catch (error) {
      throw ServerStorageException('Unable to sync server files: $error');
    }
  }

  Future<String> _resolveDefaultBaseDirectoryPath() async {
    if (Platform.isAndroid) {
      final Directory? externalDirectory = await getExternalStorageDirectory();
      if (externalDirectory != null) {
        return path.join(externalDirectory.path, 'minecraft');
      }
    }

    final Directory appDirectory = await getApplicationSupportDirectory();
    return path.join(appDirectory.path, 'minecraft');
  }

  Future<void> _validateWritableBaseDirectory(Directory baseDirectory) async {
    final File probeFile = File(
      path.join(baseDirectory.path, '.bifrost_write_probe'),
    );

    try {
      await probeFile.writeAsString('ok', flush: true);
      if (await probeFile.exists()) {
        await probeFile.delete();
      }
    } on FileSystemException {
      throw ServerStorageException(
        'Bifrost cannot write to ${baseDirectory.path}. Choose a direct writable filesystem path or use default app storage.',
      );
    }
  }

  Future<String> _resolveRuntimeMirrorPath(String serverPath) async {
    final Directory appDirectory = await getApplicationSupportDirectory();
    final String serverSlug = _slugify(path.basename(serverPath));
    return path.join(appDirectory.path, 'minecraft-runtime', serverSlug);
  }

  bool _isDirectFilesystemPath(String directoryPath) {
    if (directoryPath.startsWith('content://')) {
      return false;
    }

    if (Platform.isAndroid) {
      return directoryPath.startsWith('/storage/') ||
          directoryPath.startsWith('/sdcard/') ||
          directoryPath.startsWith('/data/');
    }

    return path.isAbsolute(directoryPath);
  }

  bool _usesCustomTreeStorage(ServerDirectorySettings settings) {
    return !settings.useDefaultDirectory &&
        settings.customDirectoryUri.trim().isNotEmpty;
  }

  ServerStorageResult _storageResultFromMap(Map<String, Object?> result) {
    final String serverPath = (result['serverPath'] as String?) ?? '';
    final String worldPath = (result['worldPath'] as String?) ?? '';
    final String jarsPath = (result['jarsPath'] as String?) ?? '';
    final String modsPath = (result['modsPath'] as String?) ?? '';
    final String backupsPath = (result['backupsPath'] as String?) ?? '';
    final String propertiesPath = (result['propertiesPath'] as String?) ?? '';
    final String metadataPath = (result['metadataPath'] as String?) ?? '';

    return ServerStorageResult(
      serverDirectory: Directory(serverPath),
      worldDirectory: Directory(worldPath),
      jarsDirectory: Directory(jarsPath),
      modsDirectory: Directory(modsPath),
      backupsDirectory: Directory(backupsPath),
      propertiesFile: File(propertiesPath),
      metadataFile: File(metadataPath),
      serverUri: result['serverUri'] as String?,
      jarsUri: result['jarsUri'] as String?,
      metadataUri: result['metadataUri'] as String?,
    );
  }

  Map<String, Object> _serverMapFromRaw(Map<String, Object?> server) {
    return <String, Object>{
      'name': (server['name'] as String?) ?? 'Unknown',
      'version': (server['version'] as String?) ?? 'Unknown',
      'type': (server['type'] as String?) ?? 'Unknown',
      'status': 'Offline',
      'memory': (server['memory'] as String?) ?? '2.0 GB',
      'isOnline': false,
      'path': (server['path'] as String?) ?? '',
      if (server['serverUri'] != null) 'serverUri': server['serverUri'] as String,
      if (server['metadataUri'] != null)
        'metadataUri': server['metadataUri'] as String,
      if (server['jarsUri'] != null) 'jarsUri': server['jarsUri'] as String,
    };
  }

  Future<Directory> _createUniqueServerDirectory(
    Directory baseDirectory,
    String serverName,
  ) async {
    final String sanitizedName = _slugify(serverName);
    var candidatePath = path.join(baseDirectory.path, sanitizedName);
    var suffix = 2;

    while (await Directory(candidatePath).exists()) {
      candidatePath = path.join(baseDirectory.path, '$sanitizedName-$suffix');
      suffix++;
    }

    final Directory directory = Directory(candidatePath);
    await directory.create(recursive: true);
    return directory;
  }

  String _slugify(String input) {
    final String lower = input.trim().toLowerCase();
    final String hyphenated = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final String cleaned = hyphenated.replaceAll(RegExp(r'^-+|-+$'), '');
    return cleaned.isEmpty ? 'server' : cleaned;
  }

  String _buildServerProperties(AddServerResult server) {
    return <String>[
      '# Bifrost generated server.properties',
      'motd=${server.name}',
      'level-name=world',
      'online-mode=true',
      'enable-command-block=false',
      'max-players=20',
      'spawn-protection=16',
      'difficulty=easy',
      'gamemode=survival',
      'pvp=true',
      'view-distance=10',
      'simulation-distance=10',
    ].join('\n');
  }

  int _parseMemoryLabelToMb(String memoryLabel) {
    final RegExpMatch? match = RegExp(
      r'([0-9]+(?:\.[0-9]+)?)\s*(GB|MB)',
      caseSensitive: false,
    ).firstMatch(memoryLabel.trim());

    if (match == null) {
      return 2048;
    }

    final double value = double.tryParse(match.group(1) ?? '') ?? 2.0;
    final String unit = (match.group(2) ?? 'GB').toUpperCase();

    final int mb = unit == 'GB' ? (value * 1024).round() : value.round();
    return mb < 512 ? 512 : mb;
  }
}
