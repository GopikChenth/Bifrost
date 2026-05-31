class LocalRuntimeStatus {
  const LocalRuntimeStatus({
    required this.runtimeRoot,
    required this.runtimeHome,
    required this.runtimeHomeExists,
    required this.releaseExists,
    required this.libDir,
    required this.libDirExists,
    required this.libjliExists,
    required this.libjvmExists,
    required this.modulesExists,
  });

  final String runtimeRoot;
  final String runtimeHome;
  final bool runtimeHomeExists;
  final bool releaseExists;
  final String libDir;
  final bool libDirExists;
  final bool libjliExists;
  final bool libjvmExists;
  final bool modulesExists;

  factory LocalRuntimeStatus.fromMap(Map<Object?, Object?> map) {
    return LocalRuntimeStatus(
      runtimeRoot: map['runtimeRoot'] as String? ?? '',
      runtimeHome: map['runtimeHome'] as String? ?? '',
      runtimeHomeExists: map['runtimeHomeExists'] as bool? ?? false,
      releaseExists: map['releaseExists'] as bool? ?? false,
      libDir: map['libDir'] as String? ?? '',
      libDirExists: map['libDirExists'] as bool? ?? false,
      libjliExists: map['libjliExists'] as bool? ?? false,
      libjvmExists: map['libjvmExists'] as bool? ?? false,
      modulesExists: map['modulesExists'] as bool? ?? false,
    );
  }
}

class LocalRuntimeTestResult {
  const LocalRuntimeTestResult({
    required this.exitCode,
    required this.status,
  });

  final int exitCode;
  final LocalRuntimeStatus status;

  factory LocalRuntimeTestResult.fromMap(Map<Object?, Object?> map) {
    return LocalRuntimeTestResult(
      exitCode: map['exitCode'] as int? ?? -1,
      status: LocalRuntimeStatus.fromMap(
        map['runtimeStatus'] as Map<Object?, Object?>? ?? <Object?, Object?>{},
      ),
    );
  }
}

class LocalServerStatus {
  const LocalServerStatus({
    required this.state,
    required this.activeServerPath,
    required this.lastExitCode,
    required this.lastMessage,
    required this.consoleOutput,
    required this.memoryUsageMb,
  });

  final String state;
  final String? activeServerPath;
  final int? lastExitCode;
  final String? lastMessage;
  final String consoleOutput;
  final int memoryUsageMb;

  bool get isBusy =>
      state == 'starting' || state == 'stopping';

  factory LocalServerStatus.fromMap(Map<Object?, Object?> map) {
    return LocalServerStatus(
      state: map['state'] as String? ?? 'idle',
      activeServerPath: map['activeServerPath'] as String?,
      lastExitCode: map['lastExitCode'] as int?,
      lastMessage: map['lastMessage'] as String?,
      consoleOutput: map['consoleOutput'] as String? ?? '',
      memoryUsageMb: map['memoryUsageMb'] as int? ?? 0,
    );
  }
}

class LocalConsoleOutput {
  const LocalConsoleOutput({
    required this.output,
    required this.totalWritten,
    required this.reset,
  });

  final String output;
  final int totalWritten;
  final bool reset;

  factory LocalConsoleOutput.fromMap(Map<Object?, Object?> map) {
    return LocalConsoleOutput(
      output: map['output'] as String? ?? '',
      totalWritten: map['totalWritten'] as int? ?? 0,
      reset: map['reset'] as bool? ?? false,
    );
  }
}
