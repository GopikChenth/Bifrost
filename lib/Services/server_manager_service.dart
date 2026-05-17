import 'dart:async';

import 'package:bifrost/Components/add_server_window.dart';
import 'package:bifrost/Models/bifrost_server.dart';
import 'package:bifrost/Services/official_server_download_service.dart';
import 'package:bifrost/Services/server_storage_service.dart';
import 'package:bifrost/Services/local_runtime_service.dart';
import 'package:bifrost/Utils/local_runtime_models.dart';
import 'package:flutter/foundation.dart';

class ServerManagerService extends ChangeNotifier {
  ServerManagerService({
    OfficialServerDownloadService officialServerDownloadService =
        const OfficialServerDownloadService(),
    ServerStorageService serverStorageService = const ServerStorageService(),
    LocalRuntimeService localRuntimeService = const LocalRuntimeService(),
  }) : _officialServerDownloadService = officialServerDownloadService,
       _serverStorageService = serverStorageService,
       _localRuntimeService = localRuntimeService;

  final OfficialServerDownloadService _officialServerDownloadService;
  final ServerStorageService _serverStorageService;
  final LocalRuntimeService _localRuntimeService;

  final List<BifrostServer> _servers = <BifrostServer>[];
  final Map<String, String> _consoleOutputByServerPath = <String, String>{};
  Timer? _serverStatusPollTimer;

  bool isLoadingServers = true;
  bool isCreatingServer = false;
  String? activeDownloadServerName;
  String? activeDownloadFileName;
  int downloadedBytes = 0;
  int? totalDownloadBytes;
  String? lastErrorMessage;

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

  double? get downloadProgress {
    final int? total = totalDownloadBytes;
    if (total == null || total <= 0) {
      return null;
    }

    return (downloadedBytes / total).clamp(0, 1).toDouble();
  }

  Future<void> loadStoredServers() async {
    try {
      final List<Map<String, Object>> storedServers =
          await _serverStorageService.loadStoredServers();

      _servers
        ..clear()
        ..addAll(storedServers.map(BifrostServer.fromStorageMap));
      lastErrorMessage = null;
    } on ServerStorageException catch (error) {
      lastErrorMessage = error.message;
    } finally {
      isLoadingServers = false;
      notifyListeners();
    }
  }

  Future<String?> createServer(AddServerResult newServer) async {
    isCreatingServer = true;
    activeDownloadServerName = newServer.name;
    activeDownloadFileName = null;
    downloadedBytes = 0;
    totalDownloadBytes = null;
    lastErrorMessage = null;
    notifyListeners();

    try {
      final ServerStorageResult storageResult = await _serverStorageService
          .createServerStructure(newServer);
      final OfficialServerArtifact artifact =
          await _officialServerDownloadService.resolveArtifact(newServer);

      activeDownloadFileName = artifact.fileName;
      notifyListeners();

      final OfficialServerDownloadResult downloadResult =
          await _officialServerDownloadService.downloadResolvedArtifact(
            artifact: artifact,
            storage: storageResult,
            onProgress: (int receivedBytes, int? totalBytes) {
              downloadedBytes = receivedBytes;
              totalDownloadBytes = totalBytes;
              notifyListeners();
            },
          );

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
    } on OfficialServerDownloadException catch (error) {
      lastErrorMessage = error.message;
      return error.message;
    } on ServerStorageException catch (error) {
      lastErrorMessage = error.message;
      return error.message;
    } catch (error) {
      lastErrorMessage = 'Unable to create the selected server: $error';
      return lastErrorMessage;
    } finally {
      isCreatingServer = false;
      activeDownloadServerName = null;
      activeDownloadFileName = null;
      downloadedBytes = 0;
      totalDownloadBytes = null;
      notifyListeners();
    }
  }

  Future<String?> deleteServer(BifrostServer server) async {
    try {
      if (server.path.trim().isNotEmpty) {
        await _serverStorageService.deleteServerDirectory(
          server.path,
          serverUri: server.serverUri,
        );
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
      final int runtimeMajor = _runtimeMajorForVersion(server.version);
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
            serverUri: server.serverUri,
          );

      final int runtimeMajor = _runtimeMajorForVersion(server.version);
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
        await _serverStorageService.syncRuntimeMirrorToServer(
          serverPath: server.path,
          serverUri: server.serverUri,
        );
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

  Future<Map<String, List<String>>> readPlayerAccessLists(
    BifrostServer server,
  ) {
    return _serverStorageService.readPlayerAccessLists(server.path);
  }

  Future<bool> isEulaAccepted(BifrostServer server) {
    return _serverStorageService.isEulaAccepted(server.path);
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

  int _runtimeMajorForVersion(String version) {
    final List<int> parts = RegExp(r'\d+')
        .allMatches(version)
        .map((RegExpMatch match) => int.tryParse(match.group(0) ?? '') ?? 0)
        .where((int value) => value > 0)
        .toList();
    if (parts.isEmpty) {
      return 21;
    }

    final int minecraftFeatureVersion = parts.first == 1 && parts.length > 1
        ? parts[1]
        : parts.first;
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
    var syncStarted = false;
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
        }
        if (!status.isBusy) {
          if (!syncStarted && status.state == 'stopped') {
            syncStarted = true;
            await _syncRuntimeMirrorAfterStop(server);
          }
          timer.cancel();
        }
      } catch (_) {
        timer.cancel();
      }
    });
  }

  Future<void> _syncRuntimeMirrorAfterStop(BifrostServer server) async {
    try {
      await _serverStorageService.syncRuntimeMirrorToServer(
        serverPath: server.path,
        serverUri: server.serverUri,
      );
      _updateServer(
        server.path,
        runtimeMessage: 'Server stopped and files were synced.',
      );
    } on ServerStorageException catch (error) {
      _updateServer(
        server.path,
        status: 'Error',
        consoleLabel: 'Sync Failed',
        runtimeMessage: error.message,
        isBusy: false,
      );
    }
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
    if (status.consoleOutput.trim().isNotEmpty) {
      _consoleOutputByServerPath[serverPath] = status.consoleOutput;
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
    notifyListeners();
  }

  @override
  void dispose() {
    _serverStatusPollTimer?.cancel();
    super.dispose();
  }
}
