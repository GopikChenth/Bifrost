class ServerLaunchConfig {
  const ServerLaunchConfig({
    required this.executablePath,
    required this.arguments,
    required this.workingDirectory,
    required this.minMemoryFlag,
    required this.maxMemoryFlag,
    required this.jarPath,
  });

  final String executablePath;
  final List<String> arguments;
  final String workingDirectory;
  final String minMemoryFlag;
  final String maxMemoryFlag;
  final String jarPath;

  factory ServerLaunchConfig.forJar({
    required String javaBinaryPath,
    required String javaHomePath,
    required String workingDirectory,
    required String jarPath,
    required String allocatedMemoryLabel,
  }) {
    final String maxMemoryFlag = _buildMemoryFlag(
      allocatedMemoryLabel,
      prefix: '-Xmx',
    );
    final String minMemoryFlag = _buildMinMemoryFlag(allocatedMemoryLabel);

    return ServerLaunchConfig(
      executablePath: javaBinaryPath,
      workingDirectory: workingDirectory,
      jarPath: jarPath,
      minMemoryFlag: minMemoryFlag,
      maxMemoryFlag: maxMemoryFlag,
      arguments: <String>[
        minMemoryFlag,
        maxMemoryFlag,
        '-Djava.home=$javaHomePath',
        '-jar',
        jarPath,
        'nogui',
      ],
    );
  }

  static String _buildMinMemoryFlag(String allocatedMemoryLabel) {
    final int allocatedMb = _parseMemoryLabelToMb(allocatedMemoryLabel);
    final int minimumMb = allocatedMb >= 2048 ? 1024 : 512;
    return '-Xms${minimumMb}M';
  }

  static String _buildMemoryFlag(
    String allocatedMemoryLabel, {
    required String prefix,
  }) {
    final int allocatedMb = _parseMemoryLabelToMb(allocatedMemoryLabel);

    if (allocatedMb % 1024 == 0) {
      return '$prefix${allocatedMb ~/ 1024}G';
    }

    return '$prefix${allocatedMb}M';
  }

  static int _parseMemoryLabelToMb(String memoryLabel) {
    final String normalized = memoryLabel.trim().toUpperCase();
    final double numericValue = double.tryParse(
          normalized.replaceAll(RegExp(r'[^0-9.]'), ''),
        ) ??
        0;

    if (normalized.endsWith('GB')) {
      return ((numericValue * 1024).round().clamp(512, 65536) as num).toInt();
    }

    if (normalized.endsWith('MB')) {
      return (numericValue.round().clamp(512, 65536) as num).toInt();
    }

    return 1024;
  }
}
