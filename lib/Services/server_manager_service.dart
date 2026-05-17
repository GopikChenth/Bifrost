import 'dart:async';
import 'dart:io';

import 'package:bifrost/Components/add_server_window.dart';
import 'package:bifrost/Models/bifrost_server.dart';
import 'package:bifrost/Services/paper_jar_service.dart';
import 'package:bifrost/Services/vanilla_jar_service.dart';
import 'package:bifrost/Services/server_storage_service.dart';
import 'package:bifrost/Services/local_runtime_service.dart';
import 'package:bifrost/Utils/local_runtime_models.dart';
import 'package:flutter/foundation.dart';

class ServerManagerService extends ChangeNotifier {
  ServerManagerService({
    OfficialServerDownloadService officialServerDownloadService =
        const OfficialServerDownloadService(),
    PaperJarService paperJarService = const PaperJarService(),
    ServerStorageService serverStorageService = const ServerStorageService(),
    LocalRuntimeService localRuntimeService = const LocalRuntimeService(),
  }) : _officialServerDownloadService = officialServerDownloadService,
       _paperJarService = paperJarService,
       _serverStorageService = serverStorageService,
       _localRuntimeService = localRuntimeService;

  final OfficialServerDownloadService _officialServerDownloadService;
  final PaperJarService _paperJarService;
  final ServerStorageService _serverStorageService;
  final LocalRuntimeService _localRuntimeService;

  final List<BifrostServer> _servers = <BifrostServer>[];
  final Map<String, String> _consoleOutputByServerPath = <String, String>{};
  final Map<String, Set<String>> _knownPlayersByServerPath =
      <String, Set<String>>{};
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

  List<String> knownPlayersFor(String serverPath) {
    final List<String> players =
        (_knownPlayersByServerPath[serverPath] ?? <String>{}).toList();
    players.sort(
      (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
    );
    return players;
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
      final _ResolvedServerDownload downloadResult =
          await _downloadServerJar(newServer, storageResult);

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
    } on PaperJarDownloadException catch (error) {
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

  Future<_ResolvedServerDownload> _downloadServerJar(
    AddServerResult newServer,
    ServerStorageResult storageResult,
  ) async {
    if (newServer.serverType.toLowerCase() == 'paper') {
      final PaperJarArtifact artifact = await _paperJarService.resolveArtifact(
        newServer.version,
      );
      activeDownloadFileName = artifact.fileName;
      notifyListeners();
      final PaperJarDownloadResult result = await _paperJarService
          .downloadResolvedArtifact(
            artifact: artifact,
            storage: storageResult,
            onProgress: (int receivedBytes, int? totalBytes) {
              downloadedBytes = receivedBytes;
              totalDownloadBytes = totalBytes;
              notifyListeners();
            },
          );
      return _ResolvedServerDownload.fromPaper(result);
    }

    final OfficialServerArtifact artifact = await _officialServerDownloadService
        .resolveArtifact(newServer);
    activeDownloadFileName = artifact.fileName;
    notifyListeners();
    final OfficialServerDownloadResult result =
        await _officialServerDownloadService.downloadResolvedArtifact(
          artifact: artifact,
          storage: storageResult,
          onProgress: (int receivedBytes, int? totalBytes) {
            downloadedBytes = receivedBytes;
            totalDownloadBytes = totalBytes;
            notifyListeners();
          },
        );
    return _ResolvedServerDownload.fromOfficial(result);
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

  Future<String?> syncWorldBackup(BifrostServer server) async {
    try {
      final Map<String, Object?>? directory = await _serverStorageService
          .pickBackupDirectory();
      final String? treeUri = directory?['uri'] as String?;
      if (treeUri == null || treeUri.trim().isEmpty) {
        return 'Backup sync cancelled.';
      }
      final String destination = await _serverStorageService
          .syncWorldBackupToTree(serverPath: server.path, treeUri: treeUri);
      return 'World backup synced to $destination';
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

  Future<bool> isEulaAccepted(BifrostServer server) async {
    try {
      return await _serverStorageService.isEulaAccepted(
        server.path,
        serverUri: server.serverUri,
      );
    } on ServerStorageException {
      return false;
    } catch (_) {
      // SAF permission revoked, binder failure, or other transient error.
      // Treat as "not accepted" so the EULA dialog is shown instead of crashing.
      return false;
    }
  }

  Future<String?> acceptEula(BifrostServer server) async {
    try {
      await _serverStorageService.acceptEula(
        server.path,
        serverUri: server.serverUri,
      );
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

  int _runtimeMajorForVersion(String version) {
    return _runtimeMajorForFeatureVersion(_minecraftFeatureVersion(version));
  }

  int _minecraftFeatureVersion(String version) {
    return _minecraftVersionParts(version).featureVersion;
  }

  _MinecraftVersionParts _minecraftVersionParts(String version) {
    final List<int> parts = RegExp(r'\d+')
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
            // Skip SAF sync if the exit code is negative (signal kill).
            // After a JVM crash the binder system is degraded and SAF
            // operations flood logcat with FAILED BINDER TRANSACTION.
            final int? exitCode = status.lastExitCode;
            if (exitCode == null || exitCode >= 0) {
              await _syncRuntimeMirrorAfterStop(server);
            }
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
    } on ServerStorageException {
      // SAF permission stale or sync failed — non-fatal.
      // Server data is safe in the runtime mirror.
      _updateServer(
        server.path,
        status: 'Stopped',
        consoleLabel: 'Stopped',
        runtimeMessage: 'Server stopped. File sync to external storage was skipped '
            '(storage permission may need to be re-selected in Settings).',
        isBusy: false,
      );
    } catch (_) {
      // After a JVM crash, Android's binder IPC can be degraded.
      _updateServer(
        server.path,
        status: 'Stopped',
        consoleLabel: 'Stopped',
        runtimeMessage: 'Server stopped. File sync was skipped due to a runtime error.',
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
      _rememberPlayersFromConsole(serverPath, status.consoleOutput);
    }
  }

  void _rememberPlayersFromConsole(String serverPath, String consoleOutput) {
    final Set<String> players = _knownPlayersByServerPath.putIfAbsent(
      serverPath,
      () => <String>{},
    );
    final List<RegExp> patterns = <RegExp>[
      RegExp(r'\]:\s+([A-Za-z0-9_]{3,16}) joined the game\b'),
      RegExp(r'\]:\s+([A-Za-z0-9_]{3,16}) left the game\b'),
      RegExp(r'UUID of player ([A-Za-z0-9_]{3,16}) is\b'),
    ];

    for (final String line in consoleOutput.split('\n')) {
      for (final RegExp pattern in patterns) {
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
    notifyListeners();
  }

  @override
  void dispose() {
    _serverStatusPollTimer?.cancel();
    super.dispose();
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
