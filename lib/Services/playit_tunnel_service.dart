import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:bifrost/Models/tunnel_status.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class PlayitTunnelException implements Exception {
  const PlayitTunnelException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Manages the bundled Playit agent lifecycle.
///
/// The agent binary is shipped as `libplayit.so` in jniLibs and is
/// automatically extracted to [applicationInfo.nativeLibraryDir] by the
/// Android package manager — no user configuration required.
class PlayitTunnelService {
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

  /// Always auto-starts with the server — no user toggle needed.
  Future<bool> shouldAutoStart() async => true;

  Future<TunnelStatus> start({
    required String serverPath,
    required String serverName,
    int localPort = 25565,
  }) async {
    final String executablePath = await _resolveBundledExecutablePath();
    dev.log('Resolved executable: $executablePath', name: 'bifrost.playit');

    if (executablePath.isEmpty) {
      dev.log('ERROR: executable path is empty', name: 'bifrost.playit');
      throw const PlayitTunnelException(
        'Playit agent not found. Ensure libplayit.so is present in jniLibs/arm64-v8a/.',
      );
    }

    final File executable = File(executablePath);
    if (!await executable.exists()) {
      dev.log('ERROR: file does not exist at $executablePath', name: 'bifrost.playit');
      throw PlayitTunnelException(
        'Playit agent was not found at $executablePath.',
      );
    }

    if (_process != null) {
      dev.log('Already running, skipping start.', name: 'bifrost.playit');
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
      dev.log('Process started (pid ${process.pid}), workdir: ${workingDirectory.path}', name: 'bifrost.playit');
      _listenToProcess(process);

      unawaited(
        process.exitCode.then((int exitCode) {
          dev.log('Process exited with code $exitCode', name: 'bifrost.playit');
          _appendLog('[playit exited with code $exitCode]');
          _process = null;
        }),
      );

      return _currentStatus(
        state: 'starting',
        message:
            'Playit agent started. If this is your first run, visit the claim URL shown below.',
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
    dev.log(line, name: 'bifrost.playit');
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
          ? 'Claim your agent at: $_claimUrl'
          : message,
      logOutput: _logOutput,
    );
  }

  /// Returns the path to [libplayit.so] in the app's native library directory.
  /// Android extracts this automatically from jniLibs — no manual copy needed.
  Future<String> _resolveBundledExecutablePath() async {
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
