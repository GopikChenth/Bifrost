class BifrostServer {
  const BifrostServer({
    required this.name,
    required this.version,
    required this.type,
    required this.memoryLabel,
    required this.path,
    this.status = 'Offline',
    this.consoleLabel = 'Ready',
    this.runtimeMessage,
    this.isBusy = false,
  });

  final String name;
  final String version;
  final String type;
  final String memoryLabel;
  final String path;
  final String status;
  final String consoleLabel;
  final String? runtimeMessage;
  final bool isBusy;

  bool get isOnline => status == 'Running';

  factory BifrostServer.fromStorageMap(Map<String, Object> map) {
    return BifrostServer(
      name: map['name'] as String? ?? 'Unknown',
      version: map['version'] as String? ?? 'Unknown',
      type: map['type'] as String? ?? 'Unknown',
      memoryLabel: map['memory'] as String? ?? '2.0 GB',
      path: map['path'] as String? ?? '',
      status: map['status'] as String? ?? 'Offline',
    );
  }

  BifrostServer copyWith({
    String? name,
    String? version,
    String? type,
    String? memoryLabel,
    String? path,
    String? status,
    String? consoleLabel,
    String? runtimeMessage,
    bool? isBusy,
  }) {
    return BifrostServer(
      name: name ?? this.name,
      version: version ?? this.version,
      type: type ?? this.type,
      memoryLabel: memoryLabel ?? this.memoryLabel,
      path: path ?? this.path,
      status: status ?? this.status,
      consoleLabel: consoleLabel ?? this.consoleLabel,
      runtimeMessage: runtimeMessage ?? this.runtimeMessage,
      isBusy: isBusy ?? this.isBusy,
    );
  }
}
