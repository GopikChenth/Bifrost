import 'package:flutter/services.dart';

class JreServiceException implements Exception {
  const JreServiceException(this.message);

  final String message;

  @override
  String toString() => 'JreServiceException: $message';
}

class JreRuntimeInfo {
  const JreRuntimeInfo({
    required this.javaBinaryPath,
    required this.runtimeRootPath,
    required this.versionLabel,
  });

  final String javaBinaryPath;
  final String runtimeRootPath;
  final String versionLabel;
}

class JreSmokeTestResult {
  const JreSmokeTestResult({
    required this.exitCode,
    required this.output,
  });

  final int exitCode;
  final String output;
}

class JreRuntimeStatus {
  const JreRuntimeStatus({
    required this.javaBinaryPath,
    required this.javaBinaryExists,
    required this.javaHomePath,
    required this.javaHomeExists,
    required this.nativeLibraryDir,
  });

  final String javaBinaryPath;
  final bool javaBinaryExists;
  final String javaHomePath;
  final bool javaHomeExists;
  final String nativeLibraryDir;
}

class JreService {
  const JreService();

  static const MethodChannel _channel = MethodChannel('bifrost/jre');

  Future<bool> isInstalled() async {
    try {
      final bool? installed = await _channel.invokeMethod<bool>('isInstalled');
      return installed ?? false;
    } on MissingPluginException {
      throw const JreServiceException(
        'Android JRE integration is not connected yet.',
      );
    } on PlatformException catch (error) {
      throw JreServiceException(
        error.message ?? 'Unable to check the Android JRE runtime.',
      );
    }
  }

  Future<void> prepareBundledRuntimeHome() async {
    try {
      await _channel.invokeMethod<void>('prepareRuntimeHome');
    } on MissingPluginException {
      throw const JreServiceException(
        'Android JRE integration is not connected yet.',
      );
    } on PlatformException catch (error) {
      throw JreServiceException(
        error.message ?? 'Unable to prepare the bundled Android JRE home.',
      );
    }
  }

  Future<JreRuntimeStatus> getRuntimeStatus() async {
    try {
      final Map<Object?, Object?>? result =
          await _channel.invokeMapMethod<Object?, Object?>('getRuntimeStatus');

      if (result == null) {
        throw const JreServiceException(
          'The bundled Android JRE status returned no result.',
        );
      }

      return JreRuntimeStatus(
        javaBinaryPath: (result['javaBinaryPath'] as String?)?.trim() ?? '',
        javaBinaryExists: result['javaBinaryExists'] as bool? ?? false,
        javaHomePath: (result['javaHomePath'] as String?)?.trim() ?? '',
        javaHomeExists: result['javaHomeExists'] as bool? ?? false,
        nativeLibraryDir: (result['nativeLibraryDir'] as String?)?.trim() ?? '',
      );
    } on MissingPluginException {
      throw const JreServiceException(
        'Android JRE integration is not connected yet.',
      );
    } on PlatformException catch (error) {
      throw JreServiceException(
        error.message ?? 'Unable to inspect the bundled Android JRE status.',
      );
    }
  }

  Future<JreRuntimeInfo> resolveRuntime() async {
    try {
      final Map<Object?, Object?>? runtimeData =
          await _channel.invokeMapMethod<Object?, Object?>('resolveRuntime');

      if (runtimeData == null) {
        throw const JreServiceException(
          'Android JRE runtime returned no configuration.',
        );
      }

      final String javaBinaryPath =
          (runtimeData['javaBinaryPath'] as String?)?.trim() ?? '';
      final String runtimeRootPath =
          (runtimeData['runtimeRootPath'] as String?)?.trim() ?? '';
      final String versionLabel =
          (runtimeData['versionLabel'] as String?)?.trim() ?? '';

      if (javaBinaryPath.isEmpty || runtimeRootPath.isEmpty) {
        throw const JreServiceException(
          'Android JRE runtime information is incomplete.',
        );
      }

      return JreRuntimeInfo(
        javaBinaryPath: javaBinaryPath,
        runtimeRootPath: runtimeRootPath,
        versionLabel: versionLabel.isEmpty ? 'Unknown JRE' : versionLabel,
      );
    } on MissingPluginException {
      throw const JreServiceException(
        'Android JRE integration is not connected yet.',
      );
    } on PlatformException catch (error) {
      throw JreServiceException(
        error.message ?? 'Unable to resolve the Android JRE runtime.',
      );
    }
  }

  Future<JreSmokeTestResult> runSmokeTest() async {
    try {
      final Map<Object?, Object?>? result =
          await _channel.invokeMapMethod<Object?, Object?>('runSmokeTest');

      if (result == null) {
        throw const JreServiceException(
          'The bundled Android JRE smoke test returned no result.',
        );
      }

      return JreSmokeTestResult(
        exitCode: (result['exitCode'] as num?)?.toInt() ?? -1,
        output: (result['output'] as String?)?.trim() ?? '',
      );
    } on MissingPluginException {
      throw const JreServiceException(
        'Android JRE integration is not connected yet.',
      );
    } on PlatformException catch (error) {
      throw JreServiceException(
        error.message ?? 'Unable to run the bundled Android JRE smoke test.',
      );
    }
  }

  static String get bundledRuntimeGuidance =>
      'Bifröst needs a bundled Android JRE 21. Package the launcher and core JVM libraries in jniLibs and ship the runtime home as assets/jre-home.';
}
