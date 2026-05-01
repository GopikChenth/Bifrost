import 'dart:async';

import 'package:bifrost/Services/android_process_service.dart';
import 'package:bifrost/Services/foreground_server_service.dart';
import 'package:bifrost/Services/jre_service.dart';
import 'package:bifrost/Services/server_install_service.dart';
import 'package:bifrost/Utils/server_launch_config.dart';
import 'package:bifrost/Utils/server_state.dart';
import 'package:flutter/foundation.dart';

class ServerProcessManagerException implements Exception {
  const ServerProcessManagerException(this.message);

  final String message;

  @override
  String toString() => 'ServerProcessManagerException: $message';
}

class ServerProcessManager {
  ServerProcessManager({
    JreService? jreService,
    ServerInstallService? serverInstallService,
    ForegroundServerService? foregroundServerService,
    AndroidProcessService? androidProcessService,
  }) : _jreService = jreService ?? const JreService(),
       _serverInstallService = serverInstallService ?? const ServerInstallService(),
       _foregroundServerService =
           foregroundServerService ?? const ForegroundServerService(),
       _androidProcessService =
           androidProcessService ?? const AndroidProcessService() {
    _processSubscription = _androidProcessService.events.listen(
      _handleProcessEvent,
      onError: (Object error, StackTrace stackTrace) {
        _logController.add(
          ServerLogEvent(
            serverPath: 'runtime',
            message: error.toString(),
            isError: true,
          ),
        );
      },
    );
  }

  final JreService _jreService;
  final ServerInstallService _serverInstallService;
  final ForegroundServerService _foregroundServerService;
  final AndroidProcessService _androidProcessService;
  final Map<String, ValueNotifier<ServerRuntimeState>> _stateByServerPath =
      <String, ValueNotifier<ServerRuntimeState>>{};
  final Map<String, String> _lastProcessMessageByServerPath = <String, String>{};
  final StreamController<ServerLogEvent> _logController =
      StreamController<ServerLogEvent>.broadcast();

  late final StreamSubscription<AndroidProcessEvent> _processSubscription;

  Stream<ServerLogEvent> get logs => _logController.stream;

  ValueListenable<ServerRuntimeState> stateFor({
    required String serverName,
    required String serverPath,
  }) {
    return _stateByServerPath.putIfAbsent(
      serverPath,
      () => ValueNotifier<ServerRuntimeState>(
        ServerRuntimeState.idle(
          serverName: serverName,
          serverPath: serverPath,
        ),
      ),
    );
  }

  Future<void> startServer({
    required String serverName,
    required String serverPath,
  }) async {
    final ValueNotifier<ServerRuntimeState> stateNotifier =
        _stateByServerPath.putIfAbsent(
          serverPath,
          () => ValueNotifier<ServerRuntimeState>(
            ServerRuntimeState.idle(
              serverName: serverName,
              serverPath: serverPath,
            ),
          ),
        );

    stateNotifier.value = stateNotifier.value.copyWith(
      status: ServerRuntimeStatus.starting,
      clearMessage: true,
    );

    try {
      await _jreService.prepareBundledRuntimeHome();
      final JreRuntimeStatus runtimeStatus = await _jreService.getRuntimeStatus();
      _logController.add(
        ServerLogEvent(
          serverPath: serverPath,
          message:
              'Runtime status: java=${runtimeStatus.javaBinaryExists} at ${runtimeStatus.javaBinaryPath}, home=${runtimeStatus.javaHomeExists} at ${runtimeStatus.javaHomePath}',
        ),
      );

      if (!await _jreService.isInstalled()) {
        await _failStart(
          stateNotifier,
          'Bundled Android JRE missing. java=${runtimeStatus.javaBinaryExists} at ${runtimeStatus.javaBinaryPath}; home=${runtimeStatus.javaHomeExists} at ${runtimeStatus.javaHomePath}; nativeLibDir=${runtimeStatus.nativeLibraryDir}',
        );
        return;
      }

      final JreRuntimeInfo runtime = await _jreService.resolveRuntime();
      final JreSmokeTestResult smokeTest = await _jreService.runSmokeTest();
      if (smokeTest.exitCode != 0) {
        await _failStart(
          stateNotifier,
          smokeTest.output.isEmpty
              ? 'Bundled Android JRE smoke test failed with exit code ${smokeTest.exitCode}.'
              : smokeTest.output,
        );
        return;
      }

      _logController.add(
        ServerLogEvent(
          serverPath: serverPath,
          message: smokeTest.output.isEmpty
              ? 'Bundled Android JRE smoke test passed.'
              : smokeTest.output,
        ),
      );

      final PreparedServerInstall install = await _serverInstallService
          .prepareServer(serverPath: serverPath);

      final ServerLaunchConfig launchConfig = ServerLaunchConfig.forJar(
        javaBinaryPath: runtime.javaBinaryPath,
        javaHomePath: runtime.runtimeRootPath,
        workingDirectory: install.serverPath,
        jarPath: install.jarFile.path,
        allocatedMemoryLabel: install.allocatedRam,
      );

      await _foregroundServerService.start(
        ForegroundServerNotification(
          serverName: install.serverName,
          statusText: 'Starting Minecraft server',
        ),
      );

      await _androidProcessService.startProcess(
        AndroidProcessStartRequest(
          serverPath: install.serverPath,
          serverName: install.serverName,
          executablePath: launchConfig.executablePath,
          arguments: launchConfig.arguments,
          workingDirectory: launchConfig.workingDirectory,
        ),
      );

      stateNotifier.value = stateNotifier.value.copyWith(
        status: ServerRuntimeStatus.running,
        clearMessage: true,
      );

      _logController.add(
        ServerLogEvent(
          serverPath: install.serverPath,
          message:
              'Launch requested with ${runtime.versionLabel} using ${launchConfig.jarPath}',
        ),
      );
    } on JreServiceException catch (error) {
      await _failStart(stateNotifier, error.message);
    } on ServerInstallException catch (error) {
      await _failStart(stateNotifier, error.message);
    } on ForegroundServerServiceException catch (error) {
      await _failStart(stateNotifier, error.message);
    } on AndroidProcessServiceException catch (error) {
      await _failStart(stateNotifier, error.message);
    } catch (error) {
      await _failStart(
        stateNotifier,
        'Unable to start the selected server: $error',
      );
    }
  }

  Future<void> stopServer({
    required String serverName,
    required String serverPath,
  }) async {
    final ValueNotifier<ServerRuntimeState> stateNotifier =
        _stateByServerPath.putIfAbsent(
          serverPath,
          () => ValueNotifier<ServerRuntimeState>(
            ServerRuntimeState.idle(
              serverName: serverName,
              serverPath: serverPath,
            ),
          ),
        );

    stateNotifier.value = stateNotifier.value.copyWith(
      status: ServerRuntimeStatus.stopping,
      clearMessage: true,
    );

    try {
      await _androidProcessService.sendCommand(
        serverPath: serverPath,
        command: 'stop',
      );
      await _androidProcessService.stopProcess(serverPath: serverPath);
      await _foregroundServerService.stop();

      stateNotifier.value = stateNotifier.value.copyWith(
        status: ServerRuntimeStatus.idle,
        clearMessage: true,
      );
    } on ForegroundServerServiceException catch (error) {
      stateNotifier.value = stateNotifier.value.copyWith(
        status: ServerRuntimeStatus.error,
        message: error.message,
      );
      rethrow;
    } on AndroidProcessServiceException catch (error) {
      stateNotifier.value = stateNotifier.value.copyWith(
        status: ServerRuntimeStatus.error,
        message: error.message,
      );
      rethrow;
    }
  }

  Future<void> sendCommand({
    required String serverPath,
    required String command,
  }) {
    return _androidProcessService.sendCommand(
      serverPath: serverPath,
      command: command,
    );
  }

  Future<void> _failStart(
    ValueNotifier<ServerRuntimeState> stateNotifier,
    String message,
  ) async {
    try {
      await _foregroundServerService.stop();
    } catch (_) {}

    stateNotifier.value = stateNotifier.value.copyWith(
      status: ServerRuntimeStatus.error,
      message: message,
    );

    _logController.add(
      ServerLogEvent(
        serverPath: stateNotifier.value.serverPath,
        message: message,
        isError: true,
      ),
    );
  }

  void _handleProcessEvent(AndroidProcessEvent event) {
    final ValueNotifier<ServerRuntimeState>? stateNotifier =
        _stateByServerPath[event.serverPath];

    switch (event.type) {
      case AndroidProcessEventType.stdout:
        final String message = event.message ?? '';
        if (message.trim().isNotEmpty) {
          _lastProcessMessageByServerPath[event.serverPath] = message;
        }
        _logController.add(
          ServerLogEvent(
            serverPath: event.serverPath,
            message: message,
          ),
        );
        return;
      case AndroidProcessEventType.stderr:
        final String message = event.message ?? '';
        if (message.trim().isNotEmpty) {
          _lastProcessMessageByServerPath[event.serverPath] = message;
        }
        _logController.add(
          ServerLogEvent(
            serverPath: event.serverPath,
            message: message,
            isError: true,
          ),
        );
        return;
      case AndroidProcessEventType.started:
        if (stateNotifier != null) {
          stateNotifier.value = stateNotifier.value.copyWith(
            status: ServerRuntimeStatus.running,
            clearMessage: true,
          );
        }
        return;
      case AndroidProcessEventType.exited:
        if (stateNotifier != null) {
          final bool cleanExit = (event.exitCode ?? 0) == 0;
          final String? lastMessage =
              _lastProcessMessageByServerPath[event.serverPath];
          stateNotifier.value = stateNotifier.value.copyWith(
            status: cleanExit
                ? ServerRuntimeStatus.idle
                : ServerRuntimeStatus.error,
            message: cleanExit
                ? null
                : (lastMessage != null && lastMessage.trim().isNotEmpty
                      ? 'Server exited with code ${event.exitCode}: $lastMessage'
                      : 'Server exited with code ${event.exitCode}'),
            clearMessage: cleanExit,
          );
        }
        if ((event.exitCode ?? 0) == 0) {
          _lastProcessMessageByServerPath.remove(event.serverPath);
        }
        _foregroundServerService.stop().catchError((Object _) {});
        return;
    }
  }

  Future<void> dispose() async {
    await _processSubscription.cancel();
    await _logController.close();

    for (final ValueNotifier<ServerRuntimeState> notifier
        in _stateByServerPath.values) {
      notifier.dispose();
    }

    _stateByServerPath.clear();
    _lastProcessMessageByServerPath.clear();
  }
}
