class BifrostServer {
  const BifrostServer({
    required this.name,
    required this.version,
    required this.type,
    required this.memoryLabel,
    required this.path,
    this.serverUri,
    this.metadataUri,
    this.jarsUri,
    this.status = 'Offline',
    this.consoleLabel = 'Ready',
    this.runtimeMessage,
    this.tunnelStatus = 'Off',
    this.tunnelAddress,
    this.tunnelMessage,
    this.tunnelClaimUrl,
    this.isBusy = false,
    this.tunnelState = 'idle',
    this.tunnelPort,
  });

  final String name;
  final String version;
  final String type;
  final String memoryLabel;
  final String path;
  final String? serverUri;
  final String? metadataUri;
  final String? jarsUri;
  final String status;
  final String consoleLabel;
  final String? runtimeMessage;

  // Persisted tunnel fields (Playit).
  final String tunnelStatus;
  final String? tunnelAddress;
  final String? tunnelMessage;

  // Ephemeral — set when Playit agent outputs a first-run claim URL.
  final String? tunnelClaimUrl;

  final bool isBusy;

  // Ephemeral tunnel state — not persisted to disk.
  final String tunnelState;
  final int? tunnelPort;

  bool get isOnline => status == 'Running';
  bool get isTunnelOnline => tunnelStatus == 'Online';

  factory BifrostServer.fromStorageMap(Map<String, Object> map) {
    return BifrostServer(
      name: map['name'] as String? ?? 'Unknown',
      version: map['version'] as String? ?? 'Unknown',
      type: map['type'] as String? ?? 'Unknown',
      memoryLabel: map['memory'] as String? ?? '2.0 GB',
      path: map['path'] as String? ?? '',
      serverUri: map['serverUri'] as String?,
      metadataUri: map['metadataUri'] as String?,
      jarsUri: map['jarsUri'] as String?,
      status: map['status'] as String? ?? 'Offline',
      tunnelStatus: map['tunnelStatus'] as String? ?? 'Off',
      tunnelAddress: map['tunnelAddress'] as String?,
      tunnelMessage: map['tunnelMessage'] as String?,
    );
  }

  BifrostServer copyWith({
    String? name,
    String? version,
    String? type,
    String? memoryLabel,
    String? path,
    String? serverUri,
    String? metadataUri,
    String? jarsUri,
    String? status,
    String? consoleLabel,
    String? runtimeMessage,
    String? tunnelStatus,
    String? tunnelAddress,
    String? tunnelMessage,
    Object? tunnelClaimUrl = _sentinel,
    bool? isBusy,
    String? tunnelState,
    Object? tunnelPort = _sentinel,
  }) {
    return BifrostServer(
      name: name ?? this.name,
      version: version ?? this.version,
      type: type ?? this.type,
      memoryLabel: memoryLabel ?? this.memoryLabel,
      path: path ?? this.path,
      serverUri: serverUri ?? this.serverUri,
      metadataUri: metadataUri ?? this.metadataUri,
      jarsUri: jarsUri ?? this.jarsUri,
      status: status ?? this.status,
      consoleLabel: consoleLabel ?? this.consoleLabel,
      runtimeMessage: runtimeMessage ?? this.runtimeMessage,
      tunnelStatus: tunnelStatus ?? this.tunnelStatus,
      tunnelAddress: tunnelAddress ?? this.tunnelAddress,
      tunnelMessage: tunnelMessage ?? this.tunnelMessage,
      tunnelClaimUrl: tunnelClaimUrl == _sentinel
          ? this.tunnelClaimUrl
          : tunnelClaimUrl as String?,
      isBusy: isBusy ?? this.isBusy,
      tunnelState: tunnelState ?? this.tunnelState,
      tunnelPort: tunnelPort == _sentinel ? this.tunnelPort : tunnelPort as int?,
    );
  }

  static const Object _sentinel = Object();
}
