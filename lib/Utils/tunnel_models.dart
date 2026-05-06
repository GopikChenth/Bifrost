class TunnelStatus {
  const TunnelStatus({
    required this.state,
    required this.remotePort,
    required this.message,
  });

  final String state;
  final int? remotePort;
  final String? message;

  bool get isActive => state == 'active';
  bool get isBusy => state == 'starting';

  String? get shareAddress =>
      remotePort != null ? 'bore.pub:$remotePort' : null;

  factory TunnelStatus.fromMap(Map<Object?, Object?> map) {
    return TunnelStatus(
      state: map['state'] as String? ?? 'idle',
      remotePort: map['remotePort'] as int?,
      message: map['message'] as String?,
    );
  }
}
