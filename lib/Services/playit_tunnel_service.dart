import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bifrost/Models/tunnel_status.dart';
import 'package:bifrost/Utils/settings_repository.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class PlayitTunnelException implements Exception {
  const PlayitTunnelException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PlayitTunnelService {
  PlayitTunnelService({
    SettingsRepository settingsRepository = const SettingsRepository(),
  }) : _settingsRepository = settingsRepository;

  final SettingsRepository _settingsRepository;
  static const MethodChannel _nativePackageChannel = MethodChannel(
    'bifrost/native_package',
  );

  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  String _logOutput = '';
  String? _publicAddress;
  String? _claimUrl;

  bool get isRunning => _process != null;

  String get logOutput => _logOutput;

  Future<bool> shouldAutoStart() async {
    final PlayitTunnelSettings settings =
        await _settingsRepository.loadPlayitTunnelSettings();
    return settings.enabled && settings.autoStart;
  }

  Future<TunnelStatus> start({
    required String serverPath,
    required String serverName,
    int localPort = 25565,
  }) async {
    final PlayitTunnelSettings settings =
        await _settingsRepository.loadPlayitTunnelSettings();

    if (!settings.enabled) {
      return TunnelStatus.disabled;
    }

    final String executablePath = await _resolveExecutablePath(settings);
    if (executablePath.isEmpty) {
      throw const PlayitTunnelException(
        'Playit is enabled, but no bundled or selected agent executable was found.',
      );
    }

    final File executable = File(executablePath);
    if (!await executable.exists()) {
      throw PlayitTunnelException(
        'Playit agent was not found at $executablePath.',
      );
    }

    if (_process != null) {
      return _currentStatus(
        state: 'running',
        message: 'Playit tunnel is already running.',
      );
    }

    _logOutput = '';
    _publicAddress = null;
    _claimUrl = null;
    final Directory workingDirectory = await _playitWorkingDirectory(
      serverName: serverName,
      serverPath: serverPath,
    );

    try {
      final Process process = await Process.start(
        executablePath,
        const <String>[],
        workingDirectory: workingDirectory.path,
        runInShell: false,
        environment: <String, String>{
          'PLAYIT_LOCAL_IP': '127.0.0.1',
          'PLAYIT_LOCAL_PORT': localPort.toString(),
        },
      );
      _process = process;
      _listenToProcess(process);

      unawaited(
        process.exitCode.then((int exitCode) {
          _appendLog('Playit agent exited with code $exitCode');
          _process = null;
        }),
      );

      return _currentStatus(
        state: 'starting',
        message:
            'Playit agent started. Claim it in the Playit dashboard if this is the first run.',
      );
    } on ProcessException catch (error) {
      throw PlayitTunnelException(
        'Unable to start Playit agent: ${error.message}',
      );
    } on FileSystemException catch (error) {
      throw PlayitTunnelException(
        'Unable to prepare Playit working directory: ${error.message}',
      );
    }
  }

  Future<String> _resolveExecutablePath(PlayitTunnelSettings settings) async {
    final String selectedPath = settings.executablePath.trim();
    if (selectedPath.isNotEmpty) {
      return selectedPath;
    }

    try {
      final String? nativeLibraryDir = await _nativePackageChannel
          .invokeMethod<String>('getNativeLibraryDir');
      if (nativeLibraryDir == null || nativeLibraryDir.trim().isEmpty) {
        return '';
      }
      return path.join(nativeLibraryDir, 'libplayit.so');
    } on PlatformException {
      return '';
    }
  }

  Future<TunnelStatus> stop() async {
    final Process? process = _process;
    if (process == null) {
      return _currentStatus(
        state: 'stopped',
        message: 'Playit tunnel is already stopped.',
      );
    }

    process.kill(ProcessSignal.sigterm);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (_process != null) {
      process.kill(ProcessSignal.sigkill);
    }
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _process = null;

    return _currentStatus(
      state: 'stopped',
      message: 'Playit tunnel stopped.',
    );
  }

  TunnelStatus status() {
    return _currentStatus(
      state: _process == null ? 'stopped' : 'running',
      message: _process == null
          ? 'Playit tunnel is stopped.'
          : 'Playit tunnel process is running.',
    );
  }

  void _listenToProcess(Process process) {
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleOutputLine);
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleOutputLine);
  }

  void _handleOutputLine(String line) {
    _appendLog(line);
    _claimUrl ??= _extractClaimUrl(line);
    _publicAddress ??= _extractPublicAddress(line);
  }

  void _appendLog(String line) {
    final String normalizedLine = line.trimRight();
    if (normalizedLine.isEmpty) {
      return;
    }

    _logOutput = <String>[
      if (_logOutput.trim().isNotEmpty) _logOutput.trimRight(),
      normalizedLine,
    ].join('\n');

    const int maxLength = 20000;
    if (_logOutput.length > maxLength) {
      _logOutput = _logOutput.substring(_logOutput.length - maxLength);
    }
  }

  String? _extractClaimUrl(String line) {
    final RegExp claimPattern = RegExp(
      r'https://(?:www\.)?playit\.gg/[^\s]+',
      caseSensitive: false,
    );
    return claimPattern.firstMatch(line)?.group(0);
  }

  String? _extractPublicAddress(String line) {
    final RegExp hostnamePattern = RegExp(
      r'\b[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*'
      r'(?:\.joinmc\.link|\.ply\.gg|\.playit\.plus|\.playit\.gg)'
      r'(?::\d{2,5})?\b',
      caseSensitive: false,
    );
    final String? hostname = hostnamePattern.firstMatch(line)?.group(0);
    if (hostname != null) {
      return hostname;
    }

    final RegExp ipPortPattern = RegExp(
      r'\b(?:\d{1,3}\.){3}\d{1,3}:\d{2,5}\b',
    );
    return ipPortPattern.firstMatch(line)?.group(0);
  }

  TunnelStatus _currentStatus({
    required String state,
    required String message,
  }) {
    return TunnelStatus(
      state: _publicAddress == null && state == 'running' ? 'starting' : state,
      publicAddress: _publicAddress,
      claimUrl: _claimUrl,
      message: _publicAddress == null && _claimUrl != null
          ? 'Claim the Playit agent: $_claimUrl'
          : message,
      logOutput: _logOutput,
    );
  }

  Future<Directory> _playitWorkingDirectory({
    required String serverName,
    required String serverPath,
  }) async {
    final Directory supportDirectory = await getApplicationSupportDirectory();
    final String safeName = _safeDirectoryName(
      serverName.trim().isEmpty ? serverPath : serverName,
    );
    final Directory directory = Directory(
      path.join(supportDirectory.path, 'playit', safeName),
    );
    return directory.create(recursive: true);
  }

  String _safeDirectoryName(String value) {
    final String cleaned = value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    if (cleaned.isEmpty) {
      return 'server';
    }
    return cleaned.length > 64 ? cleaned.substring(0, 64) : cleaned;
  }
}
