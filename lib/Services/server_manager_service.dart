import 'dart:async';

import 'package:bifrost/Components/add_server_window.dart';
import 'package:bifrost/Models/bifrost_server.dart';
import 'package:bifrost/Service/official_server_download_service.dart';
import 'package:bifrost/Service/server_storage_service.dart';
import 'package:bifrost/Services/local_runtime_service.dart';
import 'package:bifrost/Services/playit_tunnel_service.dart';
import 'package:bifrost/Utils/local_runtime_models.dart';
import 'package:bifrost/Models/tunnel_status.dart';
import 'package:flutter/foundation.dart';

class ServerManagerService extends ChangeNotifier {
  ServerManagerService({
    OfficialServerDownloadService officialServerDownloadService =
        const OfficialServerDownloadService(),
    ServerStorageService serverStorageService = const ServerStorageService(),
    LocalRuntimeService localRuntimeService = const LocalRuntimeService(),
    PlayitTunnelService? playitTunnelService,
  }) : _officialServerDownloadService = officialServerDownloadService,
       _serverStorageService = serverStorageService,
       _localRuntimeService = localRuntimeService,
       _playitTunnelService = playitTunnelService ?? PlayitTunnelService();

  final OfficialServerDownloadService _officialServerDownloadService;
  final ServerStorageService _serverStorageService;
  final LocalRuntimeService _localRuntimeService;
  final PlayitTunnelService _playitTunnelService;

  final List<BifrostServer> _servers = <BifrostServer>[];
  final Map<String, String> _consoleOutputByServerPath = <String, String>{};
  final Map<String, String> _tunnelOutputByServerPath = <String, String>{};
  final Set<String> _tunnelAutoStartAttempted = <String>{};
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

  String tunnelOutputFor(String serverPath) {
    return _tunnelOutputByServerPath[serverPath] ?? '';
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
      final LocalRuntimeStatus preparedStatus =
          await _localRuntimeService.prepareBundledRuntimeHome();
      final LocalRuntimeTestResult testResult =
          await _localRuntimeService.runJavaVersion(
        workingDirectory: server.path,
      );

      final bool passed = testResult.exitCode == 0;
      _updateServer(
        server.path,
        isBusy: false,
        consoleLabel: passed ? 'Runtime OK' : 'Runtime Failed',
        runtimeMessage: 'Local runtime test exit=${testResult.exitCode}. '
            'home=${testResult.status.runtimeHomeExists}, '
            'release=${testResult.status.releaseExists}, '
            'libjli=${testResult.status.libjliExists}, '
            'libjvm=${testResult.status.libjvmExists}, '
            'modules=${testResult.status.modulesExists}. '
            'Prepared home: ${preparedStatus.runtimeHome}.',
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
      final ServerLaunchConfig launchConfig =
          await _serverStorageService.prepareServerLaunch(
        serverPath: server.path,
        memoryLabel: server.memoryLabel,
        serverUri: server.serverUri,
      );

      final LocalServerStatus status = await _localRuntimeService.startServer(
        serverPath: launchConfig.serverDirectory.path,
        jarPath: launchConfig.jarFilePath,
        maxRamMb: launchConfig.maxRamMb,
      );

      _applyServerStatus(
        serverPath: server.path,
        status: status,
        fallbackMessage:
            'Launching ${launchConfig.jarFilePath} with ${launchConfig.maxRamMb} MB.',
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
      await _playitTunnelService.stop();
      final LocalServerStatus status = await _localRuntimeService.stopServer();
      _applyServerStatus(serverPath: server.path, status: status);
      _applyTunnelStatus(
        serverPath: server.path,
        status: TunnelStatus.stopped,
      );
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
        await _playitTunnelService.stop();
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
      final LocalServerStatus status = await _localRuntimeService.getServerStatus();
      final String? activeServerPath = status.activeServerPath;
      final String targetServerPath =
          _servers.any((BifrostServer server) => server.path == activeServerPath)
          ? activeServerPath!
          : serverPath;
      _applyServerStatus(serverPath: targetServerPath, status: status);
      if (_playitTunnelService.isRunning) {
        _applyTunnelStatus(
          serverPath: targetServerPath,
          status: _playitTunnelService.status(),
        );
      }
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
      final LocalServerStatus status =
          await _localRuntimeService.sendServerCommand(trimmedCommand);
      _applyServerStatus(serverPath: server.path, status: status);
      return 'Sent: $trimmedCommand';
    } on LocalRuntimeServiceException catch (error) {
      _updateServer(
        server.path,
        runtimeMessage: error.message,
      );
      return error.message;
    }
  }

  Future<String?> startPlayitTunnel(BifrostServer server) async {
    if (server.path.trim().isEmpty) {
      return null;
    }

    _updateServer(
      server.path,
      tunnelStatus: 'Starting',
      tunnelMessage: 'Starting Playit tunnel agent.',
    );

    try {
      final TunnelStatus status = await _playitTunnelService.start(
        serverPath: server.path,
        serverName: server.name,
      );
      _applyTunnelStatus(serverPath: server.path, status: status);
      return status.publicAddress == null
          ? status.message
          : 'Playit address: ${status.publicAddress}';
    } on PlayitTunnelException catch (error) {
      _updateServer(
        server.path,
        tunnelStatus: 'Error',
        tunnelMessage: error.message,
      );
      return error.message;
    } catch (error) {
      const String message = 'Unable to start the Playit tunnel.';
      _updateServer(
        server.path,
        tunnelStatus: 'Error',
        tunnelMessage: '$message $error',
      );
      return message;
    }
  }

  Future<String?> stopPlayitTunnel(BifrostServer server) async {
    final TunnelStatus status = await _playitTunnelService.stop();
    _applyTunnelStatus(serverPath: server.path, status: status);
    return status.message;
  }

  Future<void> _waitForServerIdle() async {
    for (var attempt = 0; attempt < 45; attempt++) {
      final LocalServerStatus status = await _localRuntimeService.getServerStatus();
      if (!status.isBusy) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    throw const LocalRuntimeServiceException(
      'Timed out waiting for the server to stop.',
    );
  }

  void _startServerStatusPolling({required BifrostServer server}) {
    _serverStatusPollTimer?.cancel();
    var syncStarted = false;
    _serverStatusPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (Timer timer) async {
        try {
          final LocalServerStatus status =
              await _localRuntimeService.getServerStatus();
          final String? activeServerPath = status.activeServerPath;
          final String? targetServerPath =
              _servers.any((BifrostServer server) => server.path == activeServerPath)
              ? activeServerPath
              : server.path;
          if (targetServerPath != null) {
            _applyServerStatus(serverPath: targetServerPath, status: status);
          }
          if (targetServerPath != null &&
              status.state == 'running' &&
              !_tunnelAutoStartAttempted.contains(targetServerPath)) {
            _tunnelAutoStartAttempted.add(targetServerPath);
            final BifrostServer? currentServer = serverByPath(targetServerPath);
            if (currentServer != null) {
              await _autoStartPlayitTunnel(currentServer);
            }
          }
          if (targetServerPath != null && _playitTunnelService.isRunning) {
            _applyTunnelStatus(
              serverPath: targetServerPath,
              status: _playitTunnelService.status(),
            );
          }
          if (!status.isBusy) {
            if (!syncStarted && status.state == 'stopped') {
              _tunnelAutoStartAttempted.remove(server.path);
              syncStarted = true;
              await _syncRuntimeMirrorAfterStop(server);
            }
            timer.cancel();
          }
        } catch (_) {
          timer.cancel();
        }
      },
    );
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

  Future<void> _autoStartPlayitTunnel(BifrostServer server) async {
    try {
      if (!await _playitTunnelService.shouldAutoStart()) {
        return;
      }
      final TunnelStatus status = await _playitTunnelService.start(
        serverPath: server.path,
        serverName: server.name,
      );
      if (status.state != 'disabled') {
        _applyTunnelStatus(serverPath: server.path, status: status);
      }
    } on PlayitTunnelException catch (error) {
      _updateServer(
        server.path,
        tunnelStatus: 'Error',
        tunnelMessage: error.message,
      );
    } catch (_) {
      _updateServer(
        server.path,
        tunnelStatus: 'Error',
        tunnelMessage: 'Unable to auto-start the Playit tunnel.',
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

  void _applyTunnelStatus({
    required String serverPath,
    required TunnelStatus status,
  }) {
    final String tunnelStatus = switch (status.state) {
      'starting' => 'Starting',
      'running' => 'Online',
      'stopped' => 'Off',
      'disabled' => 'Off',
      'error' => 'Error',
      _ => 'Off',
    };

    _updateServer(
      serverPath,
      tunnelStatus: tunnelStatus,
      tunnelAddress: status.publicAddress,
      tunnelClaimUrl: status.claimUrl,
      tunnelMessage: status.publicAddress != null
          ? 'Connected via Playit tunnel.'
          : status.message,
    );
    if (status.logOutput.trim().isNotEmpty) {
      _tunnelOutputByServerPath[serverPath] = status.logOutput;
    }
  }

  void _updateServer(
    String serverPath, {
    String? status,
    String? consoleLabel,
    String? runtimeMessage,
    String? tunnelStatus,
    String? tunnelAddress,
    String? tunnelMessage,
    Object? tunnelClaimUrl = const Object(),
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
      tunnelStatus: tunnelStatus,
      tunnelAddress: tunnelAddress,
      tunnelMessage: tunnelMessage,
      tunnelClaimUrl: tunnelClaimUrl,
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
