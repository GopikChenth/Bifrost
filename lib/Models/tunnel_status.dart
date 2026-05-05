class TunnelStatus {
  const TunnelStatus({
    required this.state,
    this.publicAddress,
    this.claimUrl,
    this.message,
    this.logOutput = '',
  });

  final String state;
  final String? publicAddress;
  final String? claimUrl;
  final String? message;
  final String logOutput;

  bool get isRunning => state == 'running';
  bool get isStarting => state == 'starting';
  bool get isBusy => isStarting || isRunning;

  TunnelStatus copyWith({
    String? state,
    String? publicAddress,
    String? claimUrl,
    String? message,
    String? logOutput,
  }) {
    return TunnelStatus(
      state: state ?? this.state,
      publicAddress: publicAddress ?? this.publicAddress,
      claimUrl: claimUrl ?? this.claimUrl,
      message: message ?? this.message,
      logOutput: logOutput ?? this.logOutput,
    );
  }

  static const TunnelStatus disabled = TunnelStatus(
    state: 'disabled',
    message: 'Playit tunnel is disabled.',
  );

  static const TunnelStatus stopped = TunnelStatus(
    state: 'stopped',
    message: 'Playit tunnel is stopped.',
  );
}
