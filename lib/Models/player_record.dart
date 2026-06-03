class PlayerRecord {
  const PlayerRecord({
    this.name,
    this.uuid,
    this.source = 'unknown',
  });

  final String? name;
  final String? uuid;
  final String source;

  String get displayName {
    final String? cleanName = name?.trim();
    if (cleanName != null && cleanName.isNotEmpty) {
      return cleanName;
    }
    final String? cleanUuid = uuid?.trim();
    if (cleanUuid != null && cleanUuid.isNotEmpty) {
      return cleanUuid;
    }
    return 'Unknown player';
  }

  String get lookupKey {
    final String? cleanUuid = uuid?.trim();
    if (cleanUuid != null && cleanUuid.isNotEmpty) {
      return cleanUuid;
    }
    return displayName;
  }

  bool get hasName => name != null && name!.trim().isNotEmpty;
  bool get hasUuid => uuid != null && uuid!.trim().isNotEmpty;

  String get normalizedKey {
    if (hasUuid) {
      return uuid!.replaceAll('-', '').toLowerCase();
    }
    return displayName.toLowerCase();
  }

  PlayerRecord merge(PlayerRecord other) {
    return PlayerRecord(
      name: hasName ? name : other.name,
      uuid: hasUuid ? uuid : other.uuid,
      source: source == 'unknown' ? other.source : source,
    );
  }
}
