import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  });

  final Directory serverDirectory;
  final Directory worldDirectory;
  final Directory jarsDirectory;
  final Directory modsDirectory;
  final Directory backupsDirectory;
  final File propertiesFile;
  final File metadataFile;
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

  /// Returns `true` when the app has full filesystem access.
  Future<bool> hasAllFilesAccess() {
    return _storageAccessService.hasAllFilesAccess();
  }

  /// Opens the system settings page for the user to grant
  /// MANAGE_EXTERNAL_STORAGE.
  Future<void> requestAllFilesAccess() {
    return _storageAccessService.requestAllFilesAccess();
  }

  Future<ServerStorageResult> createServerStructure(
    AddServerResult server,
  ) async {
    try {
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
          path.isAbsolute(customDirectoryPath)) {
        return customDirectoryPath;
      }
    }

    return _resolveDefaultBaseDirectoryPath();
  }

  Future<void> writeDownloadMetadata({
    required ServerStorageResult storage,
    required Map<String, Object?> downloadMetadata,
  }) async {
    try {
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

  Future<void> deleteServerDirectory(String serverPath) async {
    try {
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
  }) async {
    try {
      final Directory serverDirectory = Directory(serverPath);
      if (!await serverDirectory.exists()) {
        throw ServerStorageException(
          'Server directory does not exist at $serverPath.',
        );
      }

      final File metadataFile = File(
        path.join(serverDirectory.path, 'bifrost_server.json'),
      );
      if (!await metadataFile.exists()) {
        throw const ServerStorageException(
          'Server metadata file is missing.',
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
          'Server jar not found at $jarFilePath.',
        );
      }

      await _repairLaunchDirectoryForServer(
        serverDirectory: serverDirectory,
        metadataFile: metadataFile,
      );

      return ServerLaunchConfig(
        serverDirectory: serverDirectory,
        jarFilePath: jarFile.path,
        maxRamMb: _parseMemoryLabelToMb(memoryLabel),
        metadataFile: metadataFile,
      );
    } catch (error) {
      if (error is ServerStorageException) rethrow;
      throw ServerStorageException('Unable to prepare the server launch: $error');
    }
  }

  Future<void> _repairLaunchDirectoryForServer({
    required Directory serverDirectory,
    required File metadataFile,
  }) async {
    if (!await metadataFile.exists()) {
      return;
    }

    final Map<String, dynamic> metadata =
        jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
    if (!_isPaperServerMetadata(metadata)) {
      return;
    }

    await _repairPaperExtractionCache(serverDirectory);
  }

  bool _isPaperServerMetadata(Map<String, dynamic> metadata) {
    final String type = (metadata['type'] as String? ?? '').toLowerCase();
    final Map<String, dynamic>? download =
        metadata['download'] as Map<String, dynamic>?;
    final String project = (download?['project'] as String? ?? '').toLowerCase();
    return type == 'paper' || project == 'paper';
  }

  Future<void> _repairPaperExtractionCache(Directory serverDirectory) async {
    final Directory librariesDirectory = Directory(
      path.join(serverDirectory.path, 'libraries'),
    );
    if (!await librariesDirectory.exists()) {
      return;
    }

    final bool hasPaperPathConflict =
        await _hasPaperLibraryPathConflict(librariesDirectory);
    if (!hasPaperPathConflict) {
      return;
    }

    await librariesDirectory.delete(recursive: true);
  }

  Future<bool> _hasPaperLibraryPathConflict(Directory librariesDirectory) async {
    await for (final FileSystemEntity groupEntity
        in librariesDirectory.list(followLinks: false)) {
      if (groupEntity is! Directory) {
        return true;
      }

      await for (final FileSystemEntity artifactEntity
          in groupEntity.list(followLinks: false)) {
        if (artifactEntity is File) {
          return true;
        }
      }
    }

    return false;
  }

  Future<Map<String, String>> readServerProperties(String serverPath) async {
    try {
      final File propertiesFile = File(
        path.join(serverPath, 'server.properties'),
      );
      if (!await propertiesFile.exists()) {
        return <String, String>{};
      }

      return _parseServerProperties(await propertiesFile.readAsString());
    } on FileSystemException catch (error) {
      throw ServerStorageException(
        'Unable to read server.properties at ${error.path ?? serverPath}: ${error.message}',
      );
    } catch (error) {
      throw ServerStorageException('Unable to read server properties: $error');
    }
  }

  Future<String> resolveWorldDirectoryPath(String serverPath) async {
    final Map<String, String> properties = await readServerProperties(serverPath);
    final String levelName = properties['level-name']?.trim().isNotEmpty == true
        ? properties['level-name']!.trim()
        : 'world';
    return path.join(serverPath, levelName);
  }

  Future<String> exportWorldBackup(String serverPath) async {
    try {
      final String worldPath = await resolveWorldDirectoryPath(serverPath);
      final Directory worldDirectory = Directory(worldPath);
      if (!await worldDirectory.exists()) {
        throw const ServerStorageException('World folder does not exist yet.');
      }

      final Directory backupsDirectory = Directory(path.join(serverPath, 'backups'));
      await backupsDirectory.create(recursive: true);
      final String stamp = DateTime.now().millisecondsSinceEpoch.toString();
      final Directory destination = Directory(
        path.join(backupsDirectory.path, 'world-export-$stamp'),
      );
      await _copyDirectory(worldDirectory, destination);
      return destination.path;
    } on ServerStorageException {
      rethrow;
    } on FileSystemException catch (error) {
      throw ServerStorageException(
        'Unable to export world at ${error.path ?? serverPath}: ${error.message}',
      );
    } catch (error) {
      throw ServerStorageException('Unable to export world: $error');
    }
  }

  Future<void> importWorldFromDirectory({
    required String serverPath,
    required String sourcePath,
  }) async {
    try {
      final Directory sourceDirectory = Directory(sourcePath);
      if (!await sourceDirectory.exists()) {
        throw const ServerStorageException('Selected world folder does not exist.');
      }

      final String worldPath = await resolveWorldDirectoryPath(serverPath);
      final Directory worldDirectory = Directory(worldPath);
      if (await worldDirectory.exists()) {
        final Directory backupsDirectory = Directory(path.join(serverPath, 'backups'));
        await backupsDirectory.create(recursive: true);
        final String stamp = DateTime.now().millisecondsSinceEpoch.toString();
        await _copyDirectory(
          worldDirectory,
          Directory(path.join(backupsDirectory.path, 'world-before-import-$stamp')),
        );
        await worldDirectory.delete(recursive: true);
      }

      await _copyDirectory(sourceDirectory, worldDirectory);
    } on ServerStorageException {
      rethrow;
    } on FileSystemException catch (error) {
      throw ServerStorageException(
        'Unable to import world at ${error.path ?? sourcePath}: ${error.message}',
      );
    } catch (error) {
      throw ServerStorageException('Unable to import world: $error');
    }
  }

  Future<String> regenerateWorldWithRandomSeed(String serverPath) async {
    try {
      final String seed = DateTime.now().microsecondsSinceEpoch.toString();
      final String worldPath = await resolveWorldDirectoryPath(serverPath);
      final Directory worldDirectory = Directory(worldPath);
      if (await worldDirectory.exists()) {
        final Directory backupsDirectory = Directory(path.join(serverPath, 'backups'));
        await backupsDirectory.create(recursive: true);
        await _copyDirectory(
          worldDirectory,
          Directory(path.join(backupsDirectory.path, 'world-before-regenerate-$seed')),
        );
        await worldDirectory.delete(recursive: true);
      }
      await updateServerProperty(serverPath: serverPath, key: 'level-seed', value: seed);
      return seed;
    } on ServerStorageException {
      rethrow;
    } on FileSystemException catch (error) {
      throw ServerStorageException(
        'Unable to regenerate world at ${error.path ?? serverPath}: ${error.message}',
      );
    } catch (error) {
      throw ServerStorageException('Unable to regenerate world: $error');
    }
  }

  Future<Map<String, List<String>>> readPlayerAccessLists(
    String serverPath,
  ) async {
    return <String, List<String>>{
      'whitelist': await _readJsonListValues(
        File(path.join(serverPath, 'whitelist.json')),
        valueKey: 'name',
      ),
      'ops': await _readJsonListValues(
        File(path.join(serverPath, 'ops.json')),
        valueKey: 'name',
      ),
      'bannedPlayers': await _readJsonListValues(
        File(path.join(serverPath, 'banned-players.json')),
        valueKey: 'name',
      ),
      'bannedIps': await _readJsonListValues(
        File(path.join(serverPath, 'banned-ips.json')),
        valueKey: 'ip',
      ),
    };
  }

  Future<bool> isEulaAccepted(String serverPath) async {
    try {
      final File eulaFile = File(path.join(serverPath, 'eula.txt'));
      if (!await eulaFile.exists()) {
        return false;
      }
      final Map<String, String> eulaProperties = _parseServerProperties(
        await eulaFile.readAsString(),
      );
      return eulaProperties['eula']?.toLowerCase() == 'true';
    } on FileSystemException {
      return false;
    } catch (error) {
      throw ServerStorageException('Unable to read EULA state: $error');
    }
  }

  Future<void> acceptEula(String serverPath) async {
    try {
      final File eulaFile = File(path.join(serverPath, 'eula.txt'));
      await eulaFile.writeAsString('eula=true\n');
    } on FileSystemException catch (error) {
      throw ServerStorageException(
        'Unable to write eula.txt at ${error.path ?? serverPath}: ${error.message}',
      );
    } catch (error) {
      throw ServerStorageException('Unable to accept EULA: $error');
    }
  }

  Future<void> updateServerProperty({
    required String serverPath,
    required String key,
    required String value,
  }) async {
    try {
      final File propertiesFile = File(
        path.join(serverPath, 'server.properties'),
      );
      if (!await propertiesFile.exists()) {
        throw const ServerStorageException(
          'server.properties is missing for this server.',
        );
      }

      final List<String> lines = await propertiesFile.readAsLines();
      var updated = false;
      final List<String> nextLines = <String>[
        for (final String line in lines)
          if (_propertyLineKey(line) == key) ...<String>[
            '$key=$value',
          ] else ...<String>[
            line,
          ],
      ];

      updated = lines.any((String line) => _propertyLineKey(line) == key);
      if (!updated) {
        nextLines.add('$key=$value');
      }

      await propertiesFile.writeAsString('${nextLines.join('\n')}\n');
    } on ServerStorageException {
      rethrow;
    } on FileSystemException catch (error) {
      throw ServerStorageException(
        'Unable to update server.properties at ${error.path ?? serverPath}: ${error.message}',
      );
    } catch (error) {
      throw ServerStorageException('Unable to update server property: $error');
    }
  }

  Future<String> _resolveDefaultBaseDirectoryPath() async {
    if (Platform.isAndroid) {
      // With MANAGE_EXTERNAL_STORAGE, use a well-known public path
      // that survives app uninstalls and is browsable in file managers.
      try {
        final String basePath = await _storageAccessService
            .getDefaultExternalBasePath();
        if (basePath.isNotEmpty) {
          return basePath;
        }
      } catch (_) {
        // Fall through to app-internal storage.
      }

      final Directory? externalDirectory = await getExternalStorageDirectory();
      if (externalDirectory != null) {
        return path.join(externalDirectory.path, 'Bifrost');
      }
    }

    final Directory appDirectory = await getApplicationSupportDirectory();
    return path.join(appDirectory.path, 'Bifrost');
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
        'Bifrost cannot write to ${baseDirectory.path}. Grant "All files access" in Settings or use a different path.',
      );
    }
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

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    if (!await destination.exists()) {
      await destination.create(recursive: true);
    }

    final List<Directory> subdirectories = <Directory>[];
    final List<_FileCopyTask> fileTasks = <_FileCopyTask>[];

    await for (final FileSystemEntity entity in source.list(recursive: false)) {
      final String destinationPath = path.join(
        destination.path,
        path.basename(entity.path),
      );
      if (entity is Directory) {
        subdirectories.add(entity);
      } else if (entity is File) {
        fileTasks.add(_FileCopyTask(source: entity, destinationPath: destinationPath));
      }
    }

    // Copy files in parallel batches to avoid FD exhaustion.
    const int batchSize = 8;
    for (var i = 0; i < fileTasks.length; i += batchSize) {
      final int end = (i + batchSize).clamp(0, fileTasks.length);
      await Future.wait(
        fileTasks.sublist(i, end).map(
          (_FileCopyTask task) => task.source.copy(task.destinationPath),
        ),
      );
    }

    // Recurse into subdirectories.
    for (final Directory subdirectory in subdirectories) {
      await _copyDirectory(
        subdirectory,
        Directory(path.join(destination.path, path.basename(subdirectory.path))),
      );
    }
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
      'level-seed=',
      'hardcore=false',
      'online-mode=true',
      'white-list=false',
      'allow-flight=false',
      'force-gamemode=false',
      'resource-pack=',
      'require-resource-pack=false',
      'max-players=20',
      'enable-command-block=false',
      'spawn-protection=16',
      'difficulty=easy',
      'gamemode=survival',
      'pvp=true',
      'view-distance=10',
      'simulation-distance=10',
    ].join('\n');
  }

  Map<String, String> _parseServerProperties(String content) {
    final Map<String, String> properties = <String, String>{};
    for (final String line in const LineSplitter().convert(content)) {
      final String? key = _propertyLineKey(line);
      if (key == null) {
        continue;
      }
      final int separatorIndex = line.indexOf('=');
      properties[key] = separatorIndex == -1
          ? ''
          : line.substring(separatorIndex + 1).trim();
    }
    return properties;
  }

  Future<List<String>> _readJsonListValues(
    File file, {
    required String valueKey,
  }) async {
    try {
      if (!await file.exists()) {
        return <String>[];
      }

      final String content = await file.readAsString();
      if (content.trim().isEmpty) {
        return <String>[];
      }

      final Object? decoded = jsonDecode(content);
      if (decoded is! List<dynamic>) {
        return <String>[];
      }

      final List<String> values = <String>[];
      for (final Object? item in decoded) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final String? value = item[valueKey] as String?;
        if (value != null && value.trim().isNotEmpty) {
          values.add(value.trim());
        }
      }
      values.sort(
        (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
      );
      return values;
    } on FileSystemException {
      return <String>[];
    } on FormatException {
      return <String>[];
    }
  }

  String? _propertyLineKey(String line) {
    final String trimmedLine = line.trim();
    if (trimmedLine.isEmpty || trimmedLine.startsWith('#')) {
      return null;
    }

    final int separatorIndex = trimmedLine.indexOf('=');
    if (separatorIndex == -1) {
      return trimmedLine;
    }

    return trimmedLine.substring(0, separatorIndex).trim();
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

  Future<void> addPlayerAccessEntryOffline({
    required String serverPath,
    required String storageKey,
    required String value,
  }) async {
    final File file = _getPlayerAccessFile(serverPath, storageKey);
    final String valueKey = storageKey == 'bannedIps' ? 'ip' : 'name';

    List<dynamic> list = <dynamic>[];
    if (await file.exists()) {
      try {
        final String content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final Object? decoded = jsonDecode(content);
          if (decoded is List<dynamic>) {
            list = decoded;
          }
        }
      } catch (_) {}
    }

    final bool exists = list.any((dynamic item) {
      if (item is Map<String, dynamic>) {
        return (item[valueKey] as String?)?.toLowerCase() == value.toLowerCase();
      }
      return false;
    });

    if (!exists) {
      final Map<String, dynamic> entry = <String, dynamic>{};
      if (storageKey == 'bannedIps') {
        entry['ip'] = value;
        entry['created'] = DateTime.now().toString();
        entry['source'] = 'Bifrost';
        entry['expires'] = 'forever';
        entry['reason'] = 'Banned by admin';
      } else {
        entry['uuid'] = '';
        entry['name'] = value;
        if (storageKey == 'ops') {
          entry['level'] = 4;
          entry['bypassesPlayerLimit'] = false;
        } else if (storageKey == 'bannedPlayers') {
          entry['created'] = DateTime.now().toString();
          entry['source'] = 'Bifrost';
          entry['expires'] = 'forever';
          entry['reason'] = 'Banned by admin';
        }
      }
      list.add(entry);
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(list));
    }
  }

  Future<void> removePlayerAccessEntryOffline({
    required String serverPath,
    required String storageKey,
    required String value,
  }) async {
    final File file = _getPlayerAccessFile(serverPath, storageKey);
    final String valueKey = storageKey == 'bannedIps' ? 'ip' : 'name';

    if (!await file.exists()) {
      return;
    }

    List<dynamic> list = <dynamic>[];
    try {
      final String content = await file.readAsString();
      if (content.trim().isNotEmpty) {
        final Object? decoded = jsonDecode(content);
        if (decoded is List<dynamic>) {
          list = decoded;
        }
      }
    } catch (_) {
      return;
    }

    list.removeWhere((dynamic item) {
      if (item is Map<String, dynamic>) {
        return (item[valueKey] as String?)?.toLowerCase() == value.toLowerCase();
      }
      return false;
    });

    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(list));
  }

  File _getPlayerAccessFile(String serverPath, String storageKey) {
    return switch (storageKey) {
      'whitelist' => File(path.join(serverPath, 'whitelist.json')),
      'ops' => File(path.join(serverPath, 'ops.json')),
      'bannedPlayers' => File(path.join(serverPath, 'banned-players.json')),
      'bannedIps' => File(path.join(serverPath, 'banned-ips.json')),
      _ => throw ArgumentError('Unknown storage key: $storageKey'),
    };
  }

  Future<List<String>> readPlayedPlayers(String serverPath) async {
    final File userCacheFile = File(path.join(serverPath, 'usercache.json'));
    if (!await userCacheFile.exists()) {
      return <String>[];
    }
    try {
      final String content = await userCacheFile.readAsString();
      if (content.trim().isEmpty) return <String>[];
      final Object? decoded = jsonDecode(content);
      if (decoded is! List<dynamic>) return <String>[];

      final List<String> players = <String>[];
      for (final Object? item in decoded) {
        if (item is Map<String, dynamic>) {
          final String? name = item['name'] as String?;
          if (name != null && name.trim().isNotEmpty) {
            players.add(name.trim());
          }
        }
      }
      return players;
    } catch (_) {
      return <String>[];
    }
  }

  Future<Map<String, dynamic>> readPlayerDataAndStats(
    String serverPath,
    String playerName,
  ) async {
    final File userCacheFile = File(path.join(serverPath, 'usercache.json'));
    String? uuid;
    if (await userCacheFile.exists()) {
      try {
        final String content = await userCacheFile.readAsString();
        if (content.trim().isNotEmpty) {
          final Object? decoded = jsonDecode(content);
          if (decoded is List<dynamic>) {
            for (final Object? item in decoded) {
              if (item is Map<String, dynamic>) {
                final String? name = item['name'] as String?;
                if (name?.toLowerCase() == playerName.toLowerCase()) {
                  uuid = item['uuid'] as String?;
                  break;
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    final File propertiesFile = File(path.join(serverPath, 'server.properties'));
    String levelName = 'world';
    if (await propertiesFile.exists()) {
      try {
        final List<String> lines = await propertiesFile.readAsLines();
        for (final String line in lines) {
          final String trimmed = line.trim();
          if (trimmed.startsWith('level-name=')) {
            final String val = trimmed.split('=').sublist(1).join('=').trim();
            if (val.isNotEmpty) {
              levelName = val;
            }
            break;
          }
        }
      } catch (_) {}
    }

    final Map<String, dynamic> resultStats = <String, dynamic>{
      'playtime': '0m',
      'deaths': 0,
      'playerKills': 0,
      'mobKills': 0,
      'xpLevel': 0,
      'health': 20.0,
      'coordinates': 'N/A',
    };

    final List<Map<String, dynamic>> inventoryItems = <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> enderItems = <Map<String, dynamic>>[];

    if (uuid != null) {
      // 1. Read Stats
      final File statsFile = File(
        path.join(serverPath, levelName, 'stats', '$uuid.json'),
      );
      if (await statsFile.exists()) {
        try {
          final String content = await statsFile.readAsString();
          final Object? decoded = jsonDecode(content);
          if (decoded is Map<String, dynamic>) {
            final Map<String, dynamic>? statsMap =
                decoded['stats'] as Map<String, dynamic>?;
            if (statsMap != null) {
              final Map<String, dynamic>? custom =
                  statsMap['minecraft:custom'] as Map<String, dynamic>?;
              if (custom != null) {
                final int playtimeTicks =
                    custom['minecraft:play_time'] ??
                    custom['minecraft:play_one_minute'] ??
                    0;
                final int deaths = custom['minecraft:deaths'] ?? 0;
                final int playerKills = custom['minecraft:player_kills'] ?? 0;
                final int mobKills = custom['minecraft:mob_kills'] ?? 0;

                final int totalSeconds = playtimeTicks ~/ 20;
                final int hours = totalSeconds ~/ 3600;
                final int minutes = (totalSeconds % 3600) ~/ 60;

                resultStats['playtime'] =
                    hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
                resultStats['deaths'] = deaths;
                resultStats['playerKills'] = playerKills;
                resultStats['mobKills'] = mobKills;
              }
            }
          }
        } catch (_) {}
      }

      // 2. Read Player Dat
      final File datFile = File(
        path.join(serverPath, levelName, 'playerdata', '$uuid.dat'),
      );
      if (await datFile.exists()) {
        try {
          final Uint8List compressedBytes = await datFile.readAsBytes();
          final List<int> decompressed = gzip.decode(compressedBytes);
          final Uint8List decompressedBytes = Uint8List.fromList(decompressed);
          final Map<String, dynamic> nbt =
              NbtReader(decompressedBytes).parseRoot();

          final dynamic xpLevelVal = nbt['XpLevel'];
          if (xpLevelVal is num) {
            resultStats['xpLevel'] = xpLevelVal.toInt();
          }

          final dynamic healthVal = nbt['Health'];
          if (healthVal is num) {
            resultStats['health'] = healthVal.toDouble();
          }

          final dynamic posList = nbt['Pos'];
          if (posList is List<dynamic> && posList.length >= 3) {
            final double x = (posList[0] as num).toDouble();
            final double y = (posList[1] as num).toDouble();
            final double z = (posList[2] as num).toDouble();
            resultStats['coordinates'] =
                '${x.round()}, ${y.round()}, ${z.round()}';
          }

          final dynamic inv = nbt['Inventory'];
          if (inv is List<dynamic>) {
            for (final dynamic item in inv) {
              if (item is Map<String, dynamic>) {
                inventoryItems.add(<String, dynamic>{
                  'id': item['id'] as String? ?? '',
                  'Count': (item['Count'] as num?)?.toInt() ?? 1,
                  'Slot': (item['Slot'] as num?)?.toInt() ?? 0,
                });
              }
            }
          }

          final dynamic ender = nbt['EnderItems'];
          if (ender is List<dynamic>) {
            for (final dynamic item in ender) {
              if (item is Map<String, dynamic>) {
                enderItems.add(<String, dynamic>{
                  'id': item['id'] as String? ?? '',
                  'Count': (item['Count'] as num?)?.toInt() ?? 1,
                  'Slot': (item['Slot'] as num?)?.toInt() ?? 0,
                });
              }
            }
          }
        } catch (_) {}
      }
    }

    return <String, dynamic>{
      'uuid': uuid,
      'stats': resultStats,
      'inventory': inventoryItems,
      'enderChest': enderItems,
    };
  }
}

class NbtReader {
  NbtReader(Uint8List bytes) : _data = ByteData.sublistView(bytes);

  final ByteData _data;
  int _offset = 0;

  int readByte() {
    final int val = _data.getUint8(_offset);
    _offset += 1;
    return val;
  }

  int readShort() {
    final int val = _data.getInt16(_offset, Endian.big);
    _offset += 2;
    return val;
  }

  int readInt() {
    final int val = _data.getInt32(_offset, Endian.big);
    _offset += 4;
    return val;
  }

  int readLong() {
    final int val = _data.getInt64(_offset, Endian.big);
    _offset += 8;
    return val;
  }

  double readFloat() {
    final double val = _data.getFloat32(_offset, Endian.big);
    _offset += 4;
    return val;
  }

  double readDouble() {
    final double val = _data.getFloat64(_offset, Endian.big);
    _offset += 8;
    return val;
  }

  String readString() {
    final int length = _data.getUint16(_offset, Endian.big);
    _offset += 2;
    if (length == 0) return '';
    final Uint8List bytes =
        Uint8List.view(_data.buffer, _data.offsetInBytes + _offset, length);
    _offset += length;
    return utf8.decode(bytes);
  }

  dynamic parseTag(int typeId) {
    switch (typeId) {
      case 0: // End
        return null;
      case 1: // Byte
        return readByte();
      case 2: // Short
        return readShort();
      case 3: // Int
        return readInt();
      case 4: // Long
        return readLong();
      case 5: // Float
        return readFloat();
      case 6: // Double
        return readDouble();
      case 7: // Byte Array
        final int len = readInt();
        final Uint8List bytes =
            Uint8List.view(_data.buffer, _data.offsetInBytes + _offset, len);
        _offset += len;
        return bytes;
      case 8: // String
        return readString();
      case 9: // List
        final int itemType = readByte();
        final int len = readInt();
        final List<dynamic> list = <dynamic>[];
        for (int i = 0; i < len; i++) {
          final dynamic val = parseTag(itemType);
          if (val != null) {
            list.add(val);
          }
        }
        return list;
      case 10: // Compound
        final Map<String, dynamic> map = <String, dynamic>{};
        while (true) {
          final int innerType = readByte();
          if (innerType == 0) {
            break;
          }
          final String name = readString();
          final dynamic val = parseTag(innerType);
          if (val != null) {
            map[name] = val;
          }
        }
        return map;
      case 11: // Int Array
        final int len = readInt();
        final List<int> list = <int>[];
        for (int i = 0; i < len; i++) {
          list.add(readInt());
        }
        return list;
      case 12: // Long Array
        final int len = readInt();
        final List<int> list = <int>[];
        for (int i = 0; i < len; i++) {
          list.add(readLong());
        }
        return list;
      default:
        throw Exception('Unknown NBT tag type $typeId');
    }
  }

  Map<String, dynamic> parseRoot() {
    if (_offset >= _data.lengthInBytes) return <String, dynamic>{};
    final int typeId = readByte();
    if (typeId != 10) {
      throw Exception('Root tag is not compound');
    }
    readString();
    return parseTag(10) as Map<String, dynamic>;
  }
}

class _FileCopyTask {
  const _FileCopyTask({required this.source, required this.destinationPath});

  final File source;
  final String destinationPath;
}
