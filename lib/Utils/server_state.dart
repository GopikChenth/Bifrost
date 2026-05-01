enum ServerRuntimeStatus { idle, starting, running, stopping, error }

class ServerRuntimeState {
  const ServerRuntimeState({
    required this.status,
    required this.serverName,
    required this.serverPath,
    this.message,
  });

  final ServerRuntimeStatus status;
  final String serverName;
  final String serverPath;
  final String? message;

  bool get isBusy =>
      status == ServerRuntimeStatus.starting ||
      status == ServerRuntimeStatus.stopping;

  bool get isRunning => status == ServerRuntimeStatus.running;

  ServerRuntimeState copyWith({
    ServerRuntimeStatus? status,
    String? serverName,
    String? serverPath,
    String? message,
    bool clearMessage = false,
  }) {
    return ServerRuntimeState(
      status: status ?? this.status,
      serverName: serverName ?? this.serverName,
      serverPath: serverPath ?? this.serverPath,
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  factory ServerRuntimeState.idle({
    required String serverName,
    required String serverPath,
  }) {
    return ServerRuntimeState(
      status: ServerRuntimeStatus.idle,
      serverName: serverName,
      serverPath: serverPath,
    );
  }
}

class ServerLogEvent {
  ServerLogEvent({
    required this.serverPath,
    required this.message,
    this.isError = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String serverPath;
  final String message;
  final bool isError;
  final DateTime timestamp;
}
