import 'dart:async';
import 'dart:io';

import 'package:bifrost/Components/add_server_window.dart';
import 'package:bifrost/Models/bifrost_server.dart';
import 'package:bifrost/Services/google_drive_sync_service.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:bifrost/Services/paper_jar_service.dart';
import 'package:bifrost/Services/vanilla_jar_service.dart';
import 'package:bifrost/Services/server_storage_service.dart';
import 'package:bifrost/Services/local_runtime_service.dart';
import 'package:bifrost/Utils/local_runtime_models.dart';
import 'package:bifrost/Utils/zip_utility.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';


class ServerManagerService extends ChangeNotifier {
  static final ServerManagerService _instance = ServerManagerService._internal();

  factory ServerManagerService() {
    return _instance;
  }

  ServerManagerService._internal({
    OfficialServerDownloadService officialServerDownloadService =
        const OfficialServerDownloadService(),
    PaperJarService paperJarService = const PaperJarService(),
    ServerStorageService serverStorageService = const ServerStorageService(),
    LocalRuntimeService localRuntimeService = const LocalRuntimeService(),
  }) : _officialServerDownloadService = officialServerDownloadService,
       _paperJarService = paperJarService,
       _serverStorageService = serverStorageService,
       _localRuntimeService = localRuntimeService {
    _localRuntimeService.setNotificationCallback(
      onStart: () {
        if (_lastStartedServerPath != null) {
          final BifrostServer? server = serverByPath(_lastStartedServerPath!);
          if (server != null) {
            startServer(server);
          }
        }
      },
      onStop: () {
        if (_lastStartedServerPath != null) {
          final BifrostServer? server = serverByPath(_lastStartedServerPath!);
          if (server != null) {
            stopServer(server);
          }
        }
      },
    );
  }

  static bool enableAndroidNotificationForTesting = false;

  final OfficialServerDownloadService _officialServerDownloadService;
  final PaperJarService _paperJarService;
  final ServerStorageService _serverStorageService;
  final LocalRuntimeService _localRuntimeService;

  final List<BifrostServer> _servers = <BifrostServer>[];
  final Map<String, String> _consoleOutputByServerPath = <String, String>{};
  final Map<String, Set<String>> _knownPlayersByServerPath =
      <String, Set<String>>{};
  Timer? _serverStatusPollTimer;
  DateTime _lastProgressNotify = DateTime(0);

  final Map<String, Set<String>> _onlinePlayersByServerPath = <String, Set<String>>{};
  final Map<String, int> _serverMemoryUsageMb = <String, int>{};
  final Map<String, int> _playtimeSecondsByServerPath = <String, int>{};
  final Map<String, DateTime?> _lastSyncTimeByServerPath = <String, DateTime?>{};
  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  String? _lastStartedServerPath;
  String? get lastStartedServerPath => _lastStartedServerPath;

  Future<void> _loadLastStartedServerPath() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _lastStartedServerPath = prefs.getString('last_started_server_path');
    notifyListeners();
  }

  Future<void> _saveLastStartedServerPath(String path) async {
    _lastStartedServerPath = path;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_started_server_path', path);
  }

  void _updateNativeNotification(BifrostServer server) {
    if (Platform.isAndroid || enableAndroidNotificationForTesting) {
      _localRuntimeService.updateNotification(
        name: server.name,
        type: server.type,
        version: server.version,
        status: server.status,
      );
    }
  }

  bool isLoadingServers = true;

  bool isCreatingServer = false;
  bool _isCreateCancelled = false;
  String? activeDownloadServerName;
  String? activeDownloadFileName;
  int downloadedBytes = 0;
  int? totalDownloadBytes;
  String? lastErrorMessage;

  void cancelCreateServer() {
    if (isCreatingServer) {
      _isCreateCancelled = true;
      notifyListeners();
    }
  }

  List<BifrostServer> get servers => List<BifrostServer>.unmodifiable(_servers);

  BifrostServer? serverByPath(String serverPath) {
    for (final BifrostServer server in _servers) {
      if (server.path == serverPath) {
        return server;
      }
    }
    return null;
  }

  String consoleOutputFor(String serverPath) {
    return _consoleOutputByServerPath[serverPath] ?? '';
  }

  List<String> knownPlayersFor(String serverPath) {
    final List<String> players =
        (_knownPlayersByServerPath[serverPath] ?? <String>{}).toList();
    players.sort(
      (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
    );
    return players;
  }

  List<String> onlinePlayersFor(String serverPath) {
    final List<String> players =
        (_onlinePlayersByServerPath[serverPath] ?? <String>{}).toList();
    players.sort(
      (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
    );
    return players;
  }

  int playtimeFor(String serverPath) {
    return _playtimeSecondsByServerPath[serverPath] ?? 0;
  }

  DateTime? lastSyncTimeFor(String serverPath) {
    return _lastSyncTimeByServerPath[serverPath];
  }

  int memoryUsageFor(String serverPath) {
    return _serverMemoryUsageMb[serverPath] ?? 0;
  }


  double? get downloadProgress {
    final int? total = totalDownloadBytes;
    if (total == null || total <= 0) {
      return null;
    }

    return (downloadedBytes / total).clamp(0, 1).toDouble();
  }

  Future<void> loadStoredServers() async {
    await _loadLastStartedServerPath();
    try {
      final List<Map<String, Object>> storedServers =
          await _serverStorageService.loadStoredServers();

      _servers
        ..clear()
        ..addAll(storedServers.map(BifrostServer.fromStorageMap));
      lastErrorMessage = null;

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      for (final BifrostServer server in _servers) {
        final String? syncTimeStr = prefs.getString('gdrive_last_sync_${server.path}');
        if (syncTimeStr != null) {
          _lastSyncTimeByServerPath[server.path] = DateTime.tryParse(syncTimeStr);
        }
      }
    } on ServerStorageException catch (error) {
      lastErrorMessage = error.message;
    } finally {
      isLoadingServers = false;
      notifyListeners();
    }
  }


  Future<String?> createServer(AddServerResult newServer) async {
    isCreatingServer = true;
    _isCreateCancelled = false;
    activeDownloadServerName = newServer.name;
    activeDownloadFileName = null;
    downloadedBytes = 0;
    totalDownloadBytes = null;
    lastErrorMessage = null;
    notifyListeners();

    ServerStorageResult? storageResult;
    try {
      if (_isCreateCancelled) {
        throw const ServerCreateCancelledException();
      }
      storageResult = await _serverStorageService
          .createServerStructure(newServer);
      if (_isCreateCancelled) {
        throw const ServerCreateCancelledException();
      }
      final _ResolvedServerDownload downloadResult =
          await _downloadServerJar(newServer, storageResult);
      if (_isCreateCancelled) {
        throw const ServerCreateCancelledException();
      }

      await _serverStorageService.writeDownloadMetadata(
        storage: storageResult,
        downloadMetadata: <String, Object?>{
          'project': downloadResult.artifact.projectName,
          'minecraftVersion': downloadResult.artifact.minecraftVersion,
          'fileName': downloadResult.artifact.fileName,
          'downloadUrl': downloadResult.artifact.downloadUrl.toString(),
          'sha1': downloadResult.artifact.sha1,
          'buildId': downloadResult.artifact.buildId,
          'channel': downloadResult.artifact.channel,
          'path': downloadResult.destinationFile.path,
        },
      );

      await loadStoredServers();
      return 'Created ${newServer.name} and downloaded ${downloadResult.artifact.fileName}';
    } catch (error) {
      if (storageResult != null) {
        try {
          await _serverStorageService.deleteServerDirectory(storageResult.serverDirectory.path);
        } catch (_) {}
      }
      if (_isCreateCancelled) {
        lastErrorMessage = 'Server creation cancelled.';
        return 'Server creation cancelled.';
      }
      if (error is OfficialServerDownloadException) {
        lastErrorMessage = error.message;
        return error.message;
      } else if (error is PaperJarDownloadException) {
        lastErrorMessage = error.message;
        return error.message;
      } else if (error is ServerStorageException) {
        lastErrorMessage = error.message;
        return error.message;
      } else {
        lastErrorMessage = 'Unable to create the selected server: $error';
        return lastErrorMessage;
      }
    } finally {
      isCreatingServer = false;
      activeDownloadServerName = null;
      activeDownloadFileName = null;
      downloadedBytes = 0;
      totalDownloadBytes = null;
      notifyListeners();
    }
  }

  Future<_ResolvedServerDownload> _downloadServerJar(
    AddServerResult newServer,
    ServerStorageResult storageResult,
  ) async {
    if (_isCreateCancelled) {
      throw const ServerCreateCancelledException();
    }
    if (newServer.serverType.toLowerCase() == 'paper') {
      final PaperJarArtifact artifact = await _paperJarService.resolveArtifact(
        newServer.version,
      );
      if (_isCreateCancelled) {
        throw const ServerCreateCancelledException();
      }
      activeDownloadFileName = artifact.fileName;
      notifyListeners();
      final PaperJarDownloadResult result = await _paperJarService
          .downloadResolvedArtifact(
            artifact: artifact,
            storage: storageResult,
            onProgress: (int receivedBytes, int? totalBytes) {
              if (_isCreateCancelled) {
                throw const ServerCreateCancelledException();
              }
              downloadedBytes = receivedBytes;
              totalDownloadBytes = totalBytes;
              final DateTime now = DateTime.now();
              if (now.difference(_lastProgressNotify).inMilliseconds > 16) {
                _lastProgressNotify = now;
                notifyListeners();
              }
            },
          );
      return _ResolvedServerDownload.fromPaper(result);
    }

    final OfficialServerArtifact artifact = await _officialServerDownloadService
        .resolveArtifact(newServer);
    if (_isCreateCancelled) {
      throw const ServerCreateCancelledException();
    }
    activeDownloadFileName = artifact.fileName;
    notifyListeners();
    final OfficialServerDownloadResult result =
        await _officialServerDownloadService.downloadResolvedArtifact(
          artifact: artifact,
          storage: storageResult,
          onProgress: (int receivedBytes, int? totalBytes) {
            if (_isCreateCancelled) {
              throw const ServerCreateCancelledException();
            }
            downloadedBytes = receivedBytes;
            totalDownloadBytes = totalBytes;
            final DateTime now = DateTime.now();
            if (now.difference(_lastProgressNotify).inMilliseconds > 16) {
              _lastProgressNotify = now;
              notifyListeners();
            }
          },
        );
    return _ResolvedServerDownload.fromOfficial(result);
  }

  Future<String?> deleteServer(BifrostServer server) async {
    try {
      if (server.path.trim().isNotEmpty) {
        await _serverStorageService.deleteServerDirectory(server.path);
      }
      if (_lastStartedServerPath == server.path) {
        _lastStartedServerPath = null;
        if (Platform.isAndroid || enableAndroidNotificationForTesting) {
          try {
            await _localRuntimeService.cancelNotification();
          } catch (_) {}
        }
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.remove('last_started_server_path');
      }
      await loadStoredServers();
      return 'Deleted ${server.name}';
    } on ServerStorageException catch (error) {
      lastErrorMessage = error.message;
      notifyListeners();
      return error.message;
    }
  }

  Future<void> testRuntime(BifrostServer server) async {
    if (server.path.trim().isEmpty) {
      return;
    }

    _updateServer(
      server.path,
      isBusy: true,
      consoleLabel: 'Testing JVM',
      runtimeMessage:
          'Preparing bundled runtime and running java -version using the local JVM launch model.',
    );

    try {
      final int runtimeMajor = _runtimeMajorForServer(server);
      final LocalRuntimeStatus preparedStatus = await _localRuntimeService
          .prepareBundledRuntimeHome(runtimeMajor: runtimeMajor);
      final LocalRuntimeTestResult testResult = await _localRuntimeService
          .runJavaVersion(
            workingDirectory: server.path,
            runtimeMajor: runtimeMajor,
          );

      final bool passed = testResult.exitCode == 0;
      _updateServer(
        server.path,
        isBusy: false,
        consoleLabel: passed ? 'Runtime OK' : 'Runtime Failed',
        runtimeMessage:
            'Local runtime test exit=${testResult.exitCode}. '
            'home=${testResult.status.runtimeHomeExists}, '
            'release=${testResult.status.releaseExists}, '
            'libjli=${testResult.status.libjliExists}, '
            'libjvm=${testResult.status.libjvmExists}, '
            'modules=${testResult.status.modulesExists}. '
            'Prepared Java $runtimeMajor home: ${preparedStatus.runtimeHome}.',
      );
    } on LocalRuntimeServiceException catch (error) {
      _updateServer(
        server.path,
        isBusy: false,
        consoleLabel: 'Runtime Error',
        runtimeMessage: error.message,
      );
    } catch (_) {
      _updateServer(
        server.path,
        isBusy: false,
        consoleLabel: 'Runtime Error',
        runtimeMessage: 'Unable to complete the local runtime test.',
      );
    }
  }

  Future<void> startServer(BifrostServer server) async {
    if (server.path.trim().isEmpty) {
      return;
    }

    await _saveLastStartedServerPath(server.path);
    _updateNativeNotification(server);

    _updateServer(
      server.path,
      isBusy: true,
      status: 'Starting',
      consoleLabel: 'Bootstrapping',
      runtimeMessage:
          'Preparing eula.txt, resolving the downloaded jar, and launching the local JVM.',
    );

    try {
      final ServerLaunchConfig launchConfig = await _serverStorageService
          .prepareServerLaunch(
            serverPath: server.path,
            memoryLabel: server.memoryLabel,
          );

      final int runtimeMajor = _runtimeMajorForServer(server);
      final LocalServerStatus status = await _localRuntimeService.startServer(
        serverPath: launchConfig.serverDirectory.path,
        jarPath: launchConfig.jarFilePath,
        maxRamMb: launchConfig.maxRamMb,
        runtimeMajor: runtimeMajor,
      );

      _applyServerStatus(
        serverPath: server.path,
        status: status,
        fallbackMessage:
            'Launching ${launchConfig.jarFilePath} with Java $runtimeMajor and ${launchConfig.maxRamMb} MB.',
      );
      _startServerStatusPolling(server: server);
    } on ServerStorageException catch (error) {
      _updateServer(
        server.path,
        isBusy: false,
        status: 'Error',
        consoleLabel: 'Launch Failed',
        runtimeMessage: error.message,
      );
    } on LocalRuntimeServiceException catch (error) {
      _updateServer(
        server.path,
        isBusy: false,
        status: 'Error',
        consoleLabel: 'Launch Failed',
        runtimeMessage: error.message,
      );
    } catch (_) {
      _updateServer(
        server.path,
        isBusy: false,
        status: 'Error',
        consoleLabel: 'Launch Failed',
        runtimeMessage: 'Unable to start the local server runtime.',
      );
    }
  }

  Future<void> stopServer(BifrostServer server) async {
    if (server.path.trim().isEmpty) {
      return;
    }

    _updateServer(
      server.path,
      isBusy: true,
      status: 'Stopping',
      consoleLabel: 'Stopping',
      runtimeMessage: 'Sending graceful stop command to the local server JVM.',
    );

    try {
      final LocalServerStatus status = await _localRuntimeService.stopServer();
      _applyServerStatus(serverPath: server.path, status: status);
      _startServerStatusPolling(server: server);
    } on LocalRuntimeServiceException catch (error) {
      _updateServer(
        server.path,
        isBusy: false,
        status: 'Error',
        consoleLabel: 'Stop Failed',
        runtimeMessage: error.message,
      );
    } catch (_) {
      _updateServer(
        server.path,
        isBusy: false,
        status: 'Error',
        consoleLabel: 'Stop Failed',
        runtimeMessage: 'Unable to stop the local server runtime.',
      );
    }
  }

  Future<void> restartServer(BifrostServer server) async {
    if (server.path.trim().isEmpty) {
      return;
    }

    _updateServer(
      server.path,
      isBusy: true,
      status: 'Restarting',
      consoleLabel: 'Restarting',
      runtimeMessage: 'Stopping the server before launching it again.',
    );

    try {
      if (server.isOnline || server.isBusy) {
        await _localRuntimeService.stopServer();
        await _waitForServerIdle();
      }

      final BifrostServer latestServer = serverByPath(server.path) ?? server;
      await startServer(latestServer.copyWith(isBusy: false));
    } on LocalRuntimeServiceException catch (error) {
      _updateServer(
        server.path,
        isBusy: false,
        status: 'Error',
        consoleLabel: 'Restart Failed',
        runtimeMessage: error.message,
      );
    } on ServerStorageException catch (error) {
      _updateServer(
        server.path,
        isBusy: false,
        status: 'Error',
        consoleLabel: 'Restart Failed',
        runtimeMessage: error.message,
      );
    } catch (_) {
      _updateServer(
        server.path,
        isBusy: false,
        status: 'Error',
        consoleLabel: 'Restart Failed',
        runtimeMessage: 'Unable to restart the server.',
      );
    }
  }

  Future<void> refreshServerStatusFor(String serverPath) async {
    try {
      final LocalServerStatus status = await _localRuntimeService
          .getServerStatus();
      final String? activeServerPath = status.activeServerPath;
      final String targetServerPath =
          _servers.any(
            (BifrostServer server) => server.path == activeServerPath,
          )
          ? activeServerPath!
          : serverPath;
      _applyServerStatus(serverPath: targetServerPath, status: status);
    } catch (_) {
      // A dashboard/terminal refresh should not surface transient channel errors.
    }
  }

  Future<String?> sendServerCommand({
    required BifrostServer server,
    required String command,
  }) async {
    final String trimmedCommand = command.trim();
    if (trimmedCommand.isEmpty) {
      return null;
    }

    try {
      final LocalServerStatus status = await _localRuntimeService
          .sendServerCommand(trimmedCommand);
      _applyServerStatus(serverPath: server.path, status: status);
      return 'Sent: $trimmedCommand';
    } on LocalRuntimeServiceException catch (error) {
      _updateServer(server.path, runtimeMessage: error.message);
      return error.message;
    }
  }

  Future<Map<String, String>> readServerProperties(BifrostServer server) {
    return _serverStorageService.readServerProperties(server.path);
  }

  Future<String> resolveWorldDirectoryPath(BifrostServer server) {
    return _serverStorageService.resolveWorldDirectoryPath(server.path);
  }

  Future<String?> exportWorldBackup(BifrostServer server) async {
    try {
      final String destination = await _serverStorageService.exportWorldBackup(
        server.path,
      );
      return 'World exported to $destination';
    } on ServerStorageException catch (error) {
      _updateServer(server.path, runtimeMessage: error.message);
      return error.message;
    }
  }



  Future<String?> importWorldFromDirectory({
    required BifrostServer server,
    required String sourcePath,
  }) async {
    if (server.isOnline || server.isBusy) {
      return 'Stop the server before uploading a world.';
    }
    try {
      await _serverStorageService.importWorldFromDirectory(
        serverPath: server.path,
        sourcePath: sourcePath,
      );
      return 'World uploaded from $sourcePath';
    } on ServerStorageException catch (error) {
      _updateServer(server.path, runtimeMessage: error.message);
      return error.message;
    }
  }

  Future<String?> regenerateWorld(BifrostServer server) async {
    if (server.isOnline || server.isBusy) {
      return 'Stop the server before regenerating the world.';
    }
    try {
      final String seed = await _serverStorageService
          .regenerateWorldWithRandomSeed(server.path);
      return 'World regenerated with seed $seed';
    } on ServerStorageException catch (error) {
      _updateServer(server.path, runtimeMessage: error.message);
      return error.message;
    }
  }

  Future<Map<String, List<String>>> readPlayerAccessLists(
    BifrostServer server,
  ) {
    return _serverStorageService.readPlayerAccessLists(server.path);
  }

  Future<void> addPlayerAccessEntryOffline({
    required BifrostServer server,
    required String storageKey,
    required String value,
  }) async {
    await _serverStorageService.addPlayerAccessEntryOffline(
      serverPath: server.path,
      storageKey: storageKey,
      value: value,
    );
    notifyListeners();
  }

  Future<void> removePlayerAccessEntryOffline({
    required BifrostServer server,
    required String storageKey,
    required String value,
  }) async {
    await _serverStorageService.removePlayerAccessEntryOffline(
      serverPath: server.path,
      storageKey: storageKey,
      value: value,
    );
    notifyListeners();
  }

  Future<List<String>> readPlayedPlayers(BifrostServer server) async {
    return _serverStorageService.readPlayedPlayers(server.path);
  }

  Future<Map<String, dynamic>> readPlayerDataAndStats(
    BifrostServer server,
    String playerName,
  ) async {
    return _serverStorageService.readPlayerDataAndStats(
      server.path,
      playerName,
    );
  }


  Future<bool> isEulaAccepted(BifrostServer server) async {
    try {
      return await _serverStorageService.isEulaAccepted(server.path);
    } on ServerStorageException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> acceptEula(BifrostServer server) async {
    try {
      await _serverStorageService.acceptEula(server.path);
      return null;
    } on ServerStorageException catch (error) {
      _updateServer(server.path, runtimeMessage: error.message);
      return error.message;
    }
  }

  Future<String?> updateServerProperty({
    required BifrostServer server,
    required String key,
    required String value,
  }) async {
    try {
      await _serverStorageService.updateServerProperty(
        serverPath: server.path,
        key: key,
        value: value,
      );
      final String message =
          'Updated $key=$value. Restart the server to apply it.';
      _updateServer(server.path, runtimeMessage: message);
      return message;
    } on ServerStorageException catch (error) {
      _updateServer(server.path, runtimeMessage: error.message);
      return error.message;
    }
  }

  Future<String?> updateOnlineMode({
    required BifrostServer server,
    required bool enabled,
  }) async {
    try {
      await _serverStorageService.updateServerProperty(
        serverPath: server.path,
        key: 'online-mode',
        value: enabled ? 'true' : 'false',
      );
      final String message = enabled
          ? 'Online authentication enabled. Restart the server to apply it.'
          : 'Online authentication disabled. Restart the server to apply it.';
      _updateServer(server.path, runtimeMessage: message);
      return message;
    } on ServerStorageException catch (error) {
      _updateServer(server.path, runtimeMessage: error.message);
      return error.message;
    }
  }

  Future<void> _waitForServerIdle() async {
    for (var attempt = 0; attempt < 45; attempt++) {
      final LocalServerStatus status = await _localRuntimeService
          .getServerStatus();
      if (!status.isBusy) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    throw const LocalRuntimeServiceException(
      'Timed out waiting for the server to stop.',
    );
  }

  int _runtimeMajorForServer(BifrostServer server) {
    final String serverType = server.type.toLowerCase();
    final _MinecraftVersionParts versionParts = _minecraftVersionParts(
      server.version,
    );
    if (serverType == 'paper' &&
        versionParts.featureVersion == 26 &&
        versionParts.minorVersion < 1) {
      return 21;
    }
    if (serverType == 'paper' && versionParts.featureVersion < 26) {
      return 21;
    }
    return _runtimeMajorForFeatureVersion(versionParts.featureVersion);
  }

  static final RegExp _digitPattern = RegExp(r'\d+');

  _MinecraftVersionParts _minecraftVersionParts(String version) {
    final List<int> parts = _digitPattern
        .allMatches(version)
        .map((RegExpMatch match) => int.tryParse(match.group(0) ?? '') ?? 0)
        .where((int value) => value > 0)
        .toList();
    if (parts.isEmpty) {
      return const _MinecraftVersionParts(featureVersion: 20, minorVersion: 0);
    }

    if (parts.first == 1 && parts.length > 1) {
      return _MinecraftVersionParts(
        featureVersion: parts[1],
        minorVersion: parts.length > 2 ? parts[2] : 0,
      );
    }

    return _MinecraftVersionParts(
      featureVersion: parts.first,
      minorVersion: parts.length > 1 ? parts[1] : 0,
    );
  }

  int _runtimeMajorForFeatureVersion(int minecraftFeatureVersion) {
    if (minecraftFeatureVersion >= 26) {
      return 25;
    }
    if (minecraftFeatureVersion >= 20) {
      return 21;
    }
    if (minecraftFeatureVersion >= 18) {
      return 17;
    }
    return 8;
  }

  void _startServerStatusPolling({required BifrostServer server}) {
    _serverStatusPollTimer?.cancel();
    _serverStatusPollTimer = Timer.periodic(const Duration(seconds: 2), (
      Timer timer,
    ) async {
      try {
        final LocalServerStatus status = await _localRuntimeService
            .getServerStatus();
        final String? activeServerPath = status.activeServerPath;
        final String? targetServerPath =
            _servers.any(
              (BifrostServer server) => server.path == activeServerPath,
            )
            ? activeServerPath
            : server.path;
        if (targetServerPath != null) {
          _applyServerStatus(serverPath: targetServerPath, status: status);
          if (status.state == 'running') {
            final Set<String>? onlinePlayers = _onlinePlayersByServerPath[targetServerPath];
            if (onlinePlayers != null && onlinePlayers.isNotEmpty) {
              final int newPlaytime = (_playtimeSecondsByServerPath[targetServerPath] ?? 0) + 2;
              _playtimeSecondsByServerPath[targetServerPath] = newPlaytime;
              notifyListeners();

              if (newPlaytime >= 300) {
                _playtimeSecondsByServerPath[targetServerPath] = 0;
                final SharedPreferences prefs = await SharedPreferences.getInstance();
                final bool autoSyncEnabled = prefs.getBool('gdrive_autosync_$targetServerPath') ?? false;
                final GoogleSignInAccount? user = GoogleDriveSyncService.instance.currentUser;
                if (autoSyncEnabled && user != null) {
                  final BifrostServer? targetServer = serverByPath(targetServerPath);
                  if (targetServer != null) {
                    syncWorldToGoogleDrive(targetServer);
                  }
                }
              }
            }
          }
        }

        if (!status.isBusy) {
          timer.cancel();
        }
      } catch (_) {
        timer.cancel();
      }
    });
  }

  void _applyServerStatus({
    required String serverPath,
    required LocalServerStatus status,
    String? fallbackMessage,
  }) {
    final String statusLabel = switch (status.state) {
      'starting' => 'Starting',
      'running' => 'Running',
      'stopping' => 'Stopping',
      'stopped' => 'Stopped',
      'error' => 'Error',
      _ => 'Offline',
    };

    final String consoleLabel = switch (status.state) {
      'starting' => 'Bootstrapping',
      'running' => 'Live',
      'stopping' => 'Stopping',
      'stopped' => 'Stopped',
      'error' => 'Crashed',
      _ => 'Ready',
    };

    _updateServer(
      serverPath,
      status: statusLabel,
      consoleLabel: consoleLabel,
      runtimeMessage: status.lastMessage ?? fallbackMessage,
      isBusy: status.isBusy,
    );
    _serverMemoryUsageMb[serverPath] = status.memoryUsageMb;
    if (status.consoleOutput.trim().isNotEmpty) {
      _consoleOutputByServerPath[serverPath] = _capConsoleOutput(
        status.consoleOutput,
      );
      _rememberPlayersFromConsole(serverPath, status.consoleOutput);
      _updateOnlinePlayersFromConsole(serverPath, status.consoleOutput);
    }
  }

  void _updateOnlinePlayersFromConsole(String serverPath, String consoleOutput) {
    final Set<String> online = _onlinePlayersByServerPath.putIfAbsent(
      serverPath,
      () => <String>{},
    );

    final RegExp joinPattern = RegExp(r'\]:\s+([A-Za-z0-9_]{3,16}) joined the game\b');
    final RegExp leavePattern = RegExp(r'\]:\s+([A-Za-z0-9_]{3,16}) left the game\b');

    for (final String line in consoleOutput.split('\n')) {
      final RegExpMatch? joinMatch = joinPattern.firstMatch(line);
      if (joinMatch != null) {
        final String? player = joinMatch.group(1);
        if (player != null && player.trim().isNotEmpty) {
          online.add(player.trim());
        }
      }
      final RegExpMatch? leaveMatch = leavePattern.firstMatch(line);
      if (leaveMatch != null) {
        final String? player = leaveMatch.group(1);
        if (player != null && player.trim().isNotEmpty) {
          online.remove(player.trim());
        }
      }
    }
  }


  static const int _maxConsoleLines = 500;

  String _capConsoleOutput(String consoleOutput) {
    final List<String> lines = consoleOutput.split('\n');
    if (lines.length <= _maxConsoleLines) {
      return consoleOutput;
    }
    return lines.sublist(lines.length - _maxConsoleLines).join('\n');
  }

  static final List<RegExp> _playerPatterns = <RegExp>[
    RegExp(r'\]:\s+([A-Za-z0-9_]{3,16}) joined the game\b'),
    RegExp(r'\]:\s+([A-Za-z0-9_]{3,16}) left the game\b'),
    RegExp(r'UUID of player ([A-Za-z0-9_]{3,16}) is\b'),
  ];

  void _rememberPlayersFromConsole(String serverPath, String consoleOutput) {
    final Set<String> players = _knownPlayersByServerPath.putIfAbsent(
      serverPath,
      () => <String>{},
    );

    for (final String line in consoleOutput.split('\n')) {
      for (final RegExp pattern in _playerPatterns) {
        final String? player = pattern.firstMatch(line)?.group(1);
        if (player != null && player.trim().isNotEmpty) {
          players.add(player.trim());
          break;
        }
      }
    }
  }

  void _updateServer(
    String serverPath, {
    String? status,
    String? consoleLabel,
    String? runtimeMessage,
    bool? isBusy,
  }) {
    final int index = _servers.indexWhere(
      (BifrostServer server) => server.path == serverPath,
    );
    if (index == -1) {
      return;
    }

    _servers[index] = _servers[index].copyWith(
      status: status,
      consoleLabel: consoleLabel,
      runtimeMessage: runtimeMessage,
      isBusy: isBusy,
    );
    if (_lastStartedServerPath == serverPath) {
      _updateNativeNotification(_servers[index]);
    }
    notifyListeners();
  }

  Future<String?> syncWorldToGoogleDrive(BifrostServer server) async {
    if (_isSyncing) {
      return 'Sync already in progress.';
    }

    _isSyncing = true;
    notifyListeners();

    File? zipFile;
    try {
      final String worldPath = await resolveWorldDirectoryPath(server);
      final Directory worldDir = Directory(worldPath);
      if (!await worldDir.exists()) {
        throw Exception('World directory does not exist at $worldPath');
      }

      final Directory cacheDir = await getTemporaryDirectory();
      zipFile = File('${cacheDir.path}/bifrost_sync_${server.name.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}.zip');

      if (server.isOnline) {
        await sendServerCommand(server: server, command: 'save-all flush');
        await Future<void>.delayed(const Duration(seconds: 3));
        await sendServerCommand(server: server, command: 'save-off');
      }

      await ZipUtility.zipDirectory(worldDir, zipFile);

      if (server.isOnline) {
        await sendServerCommand(server: server, command: 'save-on');
      }

      final String fileId = await GoogleDriveSyncService.instance.uploadWorldSyncFile(
        serverName: server.name,
        zipFile: zipFile,
        localWorldPath: worldPath,
      );

      final DateTime now = DateTime.now();
      _lastSyncTimeByServerPath[server.path] = now;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('gdrive_last_sync_${server.path}', now.toIso8601String());

      return 'Successfully backed up world to Google Drive! File ID: $fileId';
    } catch (e) {
      if (server.isOnline) {
        await sendServerCommand(server: server, command: 'save-on');
      }
      return 'Failed to sync to Google Drive: ${e.toString()}';
    } finally {
      if (zipFile != null && zipFile.existsSync()) {
        try {
          zipFile.deleteSync();
        } catch (_) {}
      }
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<String?> downloadAndSyncWorldFromGoogleDrive(BifrostServer server, String fileId) async {
    if (_isSyncing) {
      return 'Sync already in progress.';
    }

    _isSyncing = true;
    notifyListeners();

    File? zipFile;
    try {
      if (server.isOnline || server.isBusy) {
        await stopServer(server);
        int waitAttempts = 0;
        while (server.isOnline && waitAttempts < 10) {
          await Future<void>.delayed(const Duration(seconds: 1));
          waitAttempts++;
        }
        if (server.isOnline) {
          throw Exception('Could not stop server automatically. Please stop the server manually before syncing.');
        }
      }

      final Directory cacheDir = await getTemporaryDirectory();
      zipFile = File('${cacheDir.path}/bifrost_sync_download_${server.name.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}.zip');

      await GoogleDriveSyncService.instance.downloadWorldSyncFile(
        fileId: fileId,
        destinationFile: zipFile,
      );

      final String worldPath = await resolveWorldDirectoryPath(server);
      final Directory worldDir = Directory(worldPath);

      if (await worldDir.exists()) {
        try {
          await exportWorldBackup(server);
        } catch (_) {}
        await worldDir.delete(recursive: true);
      }

      await ZipUtility.unzipFile(zipFile, worldDir);

      final DateTime now = DateTime.now();
      _lastSyncTimeByServerPath[server.path] = now;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('gdrive_last_sync_${server.path}', now.toIso8601String());

      return 'Successfully downloaded and synced world from Google Drive!';
    } catch (e) {
      return 'Failed to download and sync: ${e.toString()}';
    } finally {
      if (zipFile != null && zipFile.existsSync()) {
        try {
          zipFile.deleteSync();
        } catch (_) {}
      }
      _isSyncing = false;
      notifyListeners();
    }
  }

  void resetForTesting() {
    _servers.clear();
    _consoleOutputByServerPath.clear();
    _knownPlayersByServerPath.clear();
    _onlinePlayersByServerPath.clear();
    _playtimeSecondsByServerPath.clear();
    _lastSyncTimeByServerPath.clear();
    isLoadingServers = true;
    _lastStartedServerPath = null;
    isCreatingServer = false;
    _isCreateCancelled = false;
    activeDownloadServerName = null;
    activeDownloadFileName = null;
    downloadedBytes = 0;
    totalDownloadBytes = null;
    lastErrorMessage = null;
  }

  @override
  // ignore: must_call_super
  void dispose() {
    _serverStatusPollTimer?.cancel();
    // Do not call super.dispose() as this is a global singleton
    // and must remain usable after pages are disposed.
  }
}


class _ResolvedServerArtifact {
  const _ResolvedServerArtifact({
    required this.projectName,
    required this.minecraftVersion,
    required this.fileName,
    required this.downloadUrl,
    this.sha1,
    this.buildId,
    this.channel,
  });

  final String projectName;
  final String minecraftVersion;
  final String fileName;
  final Uri downloadUrl;
  final String? sha1;
  final int? buildId;
  final String? channel;
}

class _ResolvedServerDownload {
  const _ResolvedServerDownload({
    required this.artifact,
    required this.destinationFile,
  });

  factory _ResolvedServerDownload.fromOfficial(
    OfficialServerDownloadResult result,
  ) {
    return _ResolvedServerDownload(
      artifact: _ResolvedServerArtifact(
        projectName: result.artifact.projectName,
        minecraftVersion: result.artifact.minecraftVersion,
        fileName: result.artifact.fileName,
        downloadUrl: result.artifact.downloadUrl,
        sha1: result.artifact.sha1,
        buildId: result.artifact.buildId,
        channel: result.artifact.channel,
      ),
      destinationFile: result.destinationFile,
    );
  }

  factory _ResolvedServerDownload.fromPaper(PaperJarDownloadResult result) {
    return _ResolvedServerDownload(
      artifact: _ResolvedServerArtifact(
        projectName: 'paper',
        minecraftVersion: result.artifact.minecraftVersion,
        fileName: result.artifact.fileName,
        downloadUrl: result.artifact.downloadUrl,
        sha1: result.artifact.sha256,
        buildId: result.artifact.buildId,
        channel: result.artifact.channel,
      ),
      destinationFile: result.destinationFile,
    );
  }

  final _ResolvedServerArtifact artifact;
  final File destinationFile;
}

class _MinecraftVersionParts {
  const _MinecraftVersionParts({
    required this.featureVersion,
    required this.minorVersion,
  });

  final int featureVersion;
  final int minorVersion;
}

class ServerCreateCancelledException implements Exception {
  const ServerCreateCancelledException();
  @override
  String toString() => 'ServerCreateCancelledException: The server creation was cancelled by the user.';
}
