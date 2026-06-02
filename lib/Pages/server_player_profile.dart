import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bifrost/Models/bifrost_server.dart';
import 'package:bifrost/Services/server_manager_service.dart';
import 'package:bifrost/Components/player_profile_card.dart';
import 'package:bifrost/Components/bifrost_bounce.dart';

class PlayerProfilePage extends StatefulWidget {
  const PlayerProfilePage({
    super.key,
    required this.playerName,
    required this.serverPath,
    required this.serverManager,
  });

  final String playerName;
  final String serverPath;
  final ServerManagerService serverManager;

  @override
  State<PlayerProfilePage> createState() => _PlayerProfilePageState();
}

class _PlayerProfilePageState extends State<PlayerProfilePage> {
  late String _activePlayerName;
  Map<String, dynamic>? _playerData;
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _activePlayerName = widget.playerName;
    _loadPlayerData();
  }

  Future<void> _loadPlayerData() async {
    setState(() {
      _isLoadingData = true;
    });
    final BifrostServer? server = widget.serverManager.serverByPath(widget.serverPath);
    if (server == null) {
      setState(() {
        _isLoadingData = false;
      });
      return;
    }
    try {
      final Map<String, dynamic> data = await widget.serverManager
          .readPlayerDataAndStats(server, _activePlayerName);
      setState(() {
        _playerData = data;
        _isLoadingData = false;
      });
    } catch (_) {
      setState(() {
        _playerData = null;
        _isLoadingData = false;
      });
    }
  }

  Future<void> _send(BuildContext context, String command) async {
    final BifrostServer? server = widget.serverManager.serverByPath(widget.serverPath);
    if (server == null || !server.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start the server before sending commands.'),
        ),
      );
      return;
    }
    final String? message = await widget.serverManager.sendServerCommand(
      server: server,
      command: command,
    );
    if (context.mounted && message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
    if (mounted) {
      _loadPlayerData();
    }
  }

  _InventoryItem? _getInventoryItem(int slotIndex) {
    if (_playerData == null) return null;
    final List<dynamic>? inv = _playerData!['inventory'] as List<dynamic>?;
    return _getItemFromList(inv, slotIndex);
  }

  _InventoryItem? _getEnderItem(int slotIndex) {
    if (_playerData == null) return null;
    final List<dynamic>? ender = _playerData!['enderChest'] as List<dynamic>?;
    return _getItemFromList(ender, slotIndex);
  }

  _InventoryItem? _getItemFromList(List<dynamic>? list, int slotIndex) {
    if (list == null) return null;
    for (final dynamic item in list) {
      if (item is Map && item['Slot'] == slotIndex) {
        final String fullId = item['id']?.toString() ?? '';
        if (fullId.isEmpty || fullId == 'minecraft:air') return null;
        final String cleanId = fullId.replaceFirst('minecraft:', '');
        
        final String displayName = cleanId
            .split('_')
            .map((String word) => word.isEmpty
                ? ''
                : '${word[0].toUpperCase()}${word.substring(1)}')
            .join(' ');

        Color color = Colors.grey;
        if (cleanId.contains('sword')) {
          color = Colors.blueGrey;
        } else if (cleanId.contains('pickaxe') ||
            cleanId.contains('helmet') ||
            cleanId.contains('chestplate') ||
            cleanId.contains('leggings') ||
            cleanId.contains('boots')) {
          color = Colors.cyan;
        } else if (cleanId.contains('shovel') ||
            cleanId.contains('axe') ||
            cleanId.contains('iron')) {
          color = Colors.grey.shade400;
        } else if (cleanId.contains('beef') ||
            cleanId.contains('food') ||
            cleanId.contains('apple')) {
          color = Colors.red.shade300;
        } else if (cleanId.contains('pearl')) {
          color = Colors.teal.shade900;
        } else if (cleanId.contains('wood') ||
            cleanId.contains('oak') ||
            cleanId.contains('planks')) {
          color = Colors.brown;
        } else if (cleanId.contains('torch') || cleanId.contains('gold')) {
          color = Colors.yellow.shade700;
        } else if (cleanId.contains('cobblestone') ||
            cleanId.contains('stone')) {
          color = Colors.grey;
        }

        return _InventoryItem(
          name: displayName,
          cleanId: cleanId,
          qty: item['Count'] as int? ?? 1,
          color: color,
        );
      }
    }
    return null;
  }

  void _showEnderChestDialog(BuildContext context, String serverVersion) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        final ThemeData theme = Theme.of(context);
        final ColorScheme colors = theme.colorScheme;
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: colors.surface,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.shopping_bag_rounded,
                          color: colors.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Ender Chest',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 9,
                    crossAxisSpacing: 5,
                    mainAxisSpacing: 5,
                  ),
                  itemCount: 27,
                  itemBuilder: (BuildContext context, int index) {
                    final _InventoryItem? item = _getEnderItem(index);
                    return _InventorySlot(
                      item: item,
                      serverVersion: serverVersion,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final BifrostServer? server = widget.serverManager.serverByPath(widget.serverPath);

    final RegExp versionRegex = RegExp(r'^\d+\.\d+(?:\.\d+)?');
    final String rawVersion = server?.version ?? '1.20.1';
    final String serverVersion = versionRegex.firstMatch(rawVersion)?.group(0) ?? '1.20.1';

    final Map<String, dynamic>? stats = _playerData?['stats'] as Map<String, dynamic>?;
    final double healthVal = (stats?['health'] as num?)?.toDouble() ?? 20.0;
    final int xpVal = (stats?['xpLevel'] as num?)?.toInt() ?? 0;
    final String coordVal = stats?['coordinates'] as String? ?? 'N/A';
    final String playtimeVal = stats?['playtime'] as String? ?? '0m';
    final int deathVal = (stats?['deaths'] as num?)?.toInt() ?? 0;
    final int playerKillsVal = (stats?['playerKills'] as num?)?.toInt() ?? 0;
    final int mobKillsVal = (stats?['mobKills'] as num?)?.toInt() ?? 0;
    final String? playerUuid = _playerData?['uuid'] as String?;
    final int inventoryCount =
        (_playerData?['inventory'] as List<dynamic>?)?.length ?? 0;
    final int enderChestCount =
        (_playerData?['enderChest'] as List<dynamic>?)?.length ?? 0;
    final String? playerDataPath = _playerData?['playerDataPath'] as String?;
    final String? inventorySource = _playerData?['inventorySource'] as String?;
    final bool liveInventoryChecked =
        _playerData?['liveInventoryChecked'] as bool? ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Player Profile'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isLoadingData ? null : _loadPlayerData,
            tooltip: 'Refresh profile & inventory',
          ),
        ],
      ),
      body: ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                // ---- Player Details Card ----
                PlayerProfileCard(
                  playerName: _activePlayerName,
                  uuid: playerUuid,
                  subtitle: server != null && server.isOnline
                      ? 'Live on the server right now'
                      : 'Offline player snapshot',
                  onTap: () {},
                ),

                if (_isLoadingData)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                else ...<Widget>[
                  // ---- Player Inventory (Unified Equipment & Main Grid) ----
                  _Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Player Inventory',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (inventoryCount == 0 && enderChestCount == 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              playerDataPath == null
                                  ? 'No saved playerdata .dat file was found for this player yet.'
                                  : inventorySource == 'live' || liveInventoryChecked
                                      ? 'Live inventory command returned no items.'
                                      : 'Saved playerdata was found, but its inventory list is empty.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        
                        // Upper Equipment / Avatar section (Minecraft Layout)
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              // Left: Armor Slots (Helmet to Boots)
                              Expanded(
                                flex: 1,
                                child: Column(
                                  children: <Widget>[
                                    AspectRatio(
                                      aspectRatio: 1.0,
                                      child: _InventorySlot(
                                        item: _getInventoryItem(103), // Helmet
                                        emptyIcon: Icons.hdr_strong_outlined,
                                        serverVersion: serverVersion,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    AspectRatio(
                                      aspectRatio: 1.0,
                                      child: _InventorySlot(
                                        item: _getInventoryItem(102), // Chestplate
                                        emptyIcon: Icons.accessibility_new_rounded,
                                        serverVersion: serverVersion,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    AspectRatio(
                                      aspectRatio: 1.0,
                                      child: _InventorySlot(
                                        item: _getInventoryItem(101), // Leggings
                                        emptyIcon: Icons.airline_seat_legroom_extra_rounded,
                                        serverVersion: serverVersion,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    AspectRatio(
                                      aspectRatio: 1.0,
                                      child: _InventorySlot(
                                        item: _getInventoryItem(100), // Boots
                                        emptyIcon: Icons.roller_skating_outlined,
                                        serverVersion: serverVersion,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(flex: 1),
                              
                              // Center: Green Area showing Player Name and 128x128 Head Avatar
                              Expanded(
                                flex: 5,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade900.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.green.shade700.withValues(alpha: 0.4),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: <Widget>[
                                      Text(
                                        _activePlayerName,
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          color: Colors.green.shade300,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: 128,
                                        height: 128,
                                        child: playerUuid != null && playerUuid.isNotEmpty
                                            ? Image.network(
                                                'https://crafatar.com/avatars/$playerUuid?size=128&overlay',
                                                fit: BoxFit.contain,
                                                errorBuilder: (BuildContext context, Object error,
                                                    StackTrace? stackTrace) {
                                                  return Image.network(
                                                    'https://minotar.net/avatar/$_activePlayerName/128.png',
                                                    fit: BoxFit.contain,
                                                    errorBuilder: (BuildContext context, Object error,
                                                        StackTrace? stackTrace) {
                                                      return Center(
                                                        child: Icon(
                                                          Icons.face_outlined,
                                                          color: Colors.green.shade400,
                                                          size: 48,
                                                        ),
                                                      );
                                                    },
                                                  );
                                                },
                                              )
                                            : Image.network(
                                                'https://minotar.net/avatar/$_activePlayerName/128.png',
                                                fit: BoxFit.contain,
                                                errorBuilder: (BuildContext context, Object error,
                                                    StackTrace? stackTrace) {
                                                  return Center(
                                                    child: Icon(
                                                      Icons.face_outlined,
                                                      color: Colors.green.shade400,
                                                      size: 48,
                                                    ),
                                                  );
                                                },
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const Spacer(flex: 1),
                              
                              // Right: Ender Chest Slot at the top, Off-hand Slot at the bottom
                              Expanded(
                                flex: 1,
                                child: Column(
                                  children: <Widget>[
                                    AspectRatio(
                                      aspectRatio: 1.0,
                                      child: _EnderChestSlot(
                                        onTap: () => _showEnderChestDialog(context, serverVersion),
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    const Spacer(),
                                    AspectRatio(
                                      aspectRatio: 1.0,
                                      child: _InventorySlot(
                                        item: _getInventoryItem(-106), // Off-hand
                                        emptyIcon: Icons.shield_outlined,
                                        serverVersion: serverVersion,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Divider(thickness: 1.5),
                        ),
                        
                        // 9x3 main inventory slots (9 to 35)
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 9,
                            crossAxisSpacing: 5,
                            mainAxisSpacing: 5,
                          ),
                          itemCount: 27,
                          itemBuilder: (BuildContext context, int index) {
                            final _InventoryItem? item = _getInventoryItem(index + 9);
                            return _InventorySlot(
                              item: item,
                              serverVersion: serverVersion,
                            );
                          },
                        ),
                        
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Divider(thickness: 1.5),
                        ),
                        
                        // 9x1 hotbar slots (0 to 8)
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 9,
                            crossAxisSpacing: 5,
                            mainAxisSpacing: 5,
                          ),
                          itemCount: 9,
                          itemBuilder: (BuildContext context, int index) {
                            final _InventoryItem? item = _getInventoryItem(index);
                            return _InventorySlot(
                              item: item,
                              isHotbar: true,
                              serverVersion: serverVersion,
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  // ---- Commands Panel ----
                  _Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Server Actions',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: BifrostBounce(
                                child: FilledButton.icon(
                                  onPressed: server != null && server.isOnline
                                      ? () => _send(context, 'kill $_activePlayerName')
                                      : null,
                                  icon: const Icon(Icons.dangerous_rounded, size: 18),
                                  label: const Text('Kill'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: colors.errorContainer,
                                    foregroundColor: colors.onErrorContainer,
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: BifrostBounce(
                                child: FilledButton.icon(
                                  onPressed: server != null && server.isOnline
                                      ? () => _send(
                                            context,
                                            'effect give $_activePlayerName instant_health 1 255 true',
                                          )
                                      : null,
                                  icon: const Icon(Icons.favorite_rounded, size: 18),
                                  label: const Text('Heal'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: colors.primaryContainer,
                                    foregroundColor: colors.onPrimaryContainer,
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: BifrostBounce(
                                child: FilledButton.icon(
                                  onPressed: server != null && server.isOnline
                                      ? () => _send(context, 'clear $_activePlayerName')
                                      : null,
                                  icon: const Icon(Icons.inventory_2_rounded, size: 18),
                                  label: const Text('Clear Inv'),
                                  style: FilledButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ---- Stats Panel ----
                  _Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Statistics',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _StatTile(
                                icon: Icons.schedule_rounded,
                                label: 'Playtime',
                                value: playtimeVal,
                              ),
                            ),
                            Expanded(
                              child: _StatTile(
                                icon: Icons.dangerous_rounded,
                                label: 'Deaths',
                                value: deathVal.toString(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _StatTile(
                                icon: Icons.military_tech_rounded,
                                label: 'XP Level',
                                value: xpVal.toString(),
                              ),
                            ),
                            Expanded(
                              child: _StatTile(
                                icon: Icons.explore_rounded,
                                label: 'Coordinates',
                                value: coordVal,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _StatTile(
                                icon: Icons.favorite_rounded,
                                label: 'Health',
                                value: '${healthVal.round()} / 20 HP',
                              ),
                            ),
                            Expanded(
                              child: _StatTile(
                                icon: Icons.person_off_rounded,
                                label: 'Player Kills',
                                value: playerKillsVal.toString(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _StatTile(
                                icon: Icons.pets_rounded,
                                label: 'Mob Kills',
                                value: mobKillsVal.toString(),
                              ),
                            ),
                            const Spacer(),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _InventoryItem {
  const _InventoryItem({
    required this.name,
    required this.cleanId,
    required this.qty,
    required this.color,
  });

  final String name;
  final String cleanId;
  final int qty;
  final Color color;
}

class _InventorySlot extends StatelessWidget {
  const _InventorySlot({
    this.item,
    this.isHotbar = false,
    this.emptyIcon,
    required this.serverVersion,
  });

  final _InventoryItem? item;
  final bool isHotbar;
  final IconData? emptyIcon;
  final String serverVersion;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        final String text = item != null ? '${item!.name} (x${item!.qty})' : 'Empty Slot';
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(text),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Tooltip(
        message: item != null ? '${item!.name} (x${item!.qty})' : 'Empty Slot',
        child: Container(
          decoration: BoxDecoration(
            color: isHotbar 
                ? colors.surfaceContainerHigh 
                : colors.surfaceContainerHighest.withValues(alpha: 0.5),
            border: Border.all(
              color: isHotbar ? colors.primary.withValues(alpha: 0.5) : colors.outlineVariant,
              width: isHotbar ? 1.5 : 1.0,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: item == null
              ? (emptyIcon != null 
                  ? Center(
                      child: Icon(
                        emptyIcon,
                        size: 18,
                        color: colors.onSurfaceVariant.withValues(alpha: 0.3),
                      ),
                    )
                  : const SizedBox.shrink())
              : Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    CachedItemImage(
                      cleanId: item!.cleanId,
                      serverVersion: serverVersion,
                      fallbackColor: item!.color,
                      fallbackName: item!.name,
                    ),
                    if (item!.qty > 1)
                      Positioned(
                        bottom: 2,
                        right: 4,
                        child: Text(
                          item!.qty.toString(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            shadows: <Shadow>[
                              Shadow(
                                color: Colors.black,
                                offset: Offset(1, 1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _EnderChestSlot extends StatelessWidget {
  const _EnderChestSlot({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Tooltip(
      message: 'Ender Chest',
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
          border: Border.all(
            color: colors.outlineVariant,
            width: 1.0,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Image.network(
                  'https://raw.githubusercontent.com/PrismarineJS/minecraft-assets/master/data/1.20.1/items/ender_chest.png',
                  width: 28,
                  height: 28,
                  fit: BoxFit.contain,
                  errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                    return Image.network(
                      'https://raw.githubusercontent.com/InventivetalentDev/minecraft-assets/1.20.1/assets/minecraft/textures/item/ender_chest.png',
                      width: 28,
                      height: 28,
                      fit: BoxFit.contain,
                      errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                        return Center(
                          child: Icon(
                            Icons.shopping_bag_rounded,
                            size: 20,
                            color: colors.primary,
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: child,
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: <Widget>[
          Icon(icon, color: colors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CachedItemImage extends StatefulWidget {
  const CachedItemImage({
    super.key,
    required this.cleanId,
    required this.serverVersion,
    required this.fallbackColor,
    required this.fallbackName,
  });

  final String cleanId;
  final String serverVersion;
  final Color fallbackColor;
  final String fallbackName;

  @override
  State<CachedItemImage> createState() => _CachedItemImageState();
}

class _CachedItemImageState extends State<CachedItemImage> {
  File? _localFile;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initLocalFile();
  }

  @override
  void didUpdateWidget(CachedItemImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cleanId != widget.cleanId ||
        oldWidget.serverVersion != widget.serverVersion) {
      _initLocalFile();
    }
  }

  Future<void> _initLocalFile() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _localFile = null;
    });

    try {
      final Directory supportDir = await getApplicationSupportDirectory();
      final String cachePath = path.join(
        supportDir.path,
        'item_textures',
        widget.serverVersion,
        '${widget.cleanId}.png',
      );
      final File file = File(cachePath);

      if (await file.exists()) {
        if (mounted) {
          setState(() {
            _localFile = file;
            _isLoading = false;
          });
        }
        return;
      }

      // If not exists locally, attempt to download
      final bool downloaded = await _downloadTexture(file);
      if (downloaded && await file.exists()) {
        if (mounted) {
          setState(() {
            _localFile = file;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _hasError = true;
            _isLoading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  String _getClosestPrismarineVersion(String serverVersion) {
    final List<String> supported = <String>[
      '1.21.11', '1.21.10', '1.21.9', '1.21.8', '1.21.7', '1.21.6', '1.21.5', '1.21.4', '1.21.1',
      '1.20.2', '1.19.1', '1.18.1', '1.17.1', '1.16.4', '1.16.1', '1.15.2', '1.14.4', '1.13.2', '1.13',
      '1.12', '1.11.2', '1.10', '1.9', '1.8.8'
    ];

    if (supported.contains(serverVersion)) {
      return serverVersion;
    }

    final List<int> parts = serverVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    if (parts.isEmpty) return '1.20.2';

    final int major = parts[0];
    final int minor = parts.length > 1 ? parts[1] : 0;
    final int patch = parts.length > 2 ? parts[2] : 0;

    final List<String> sameMinor = supported.where((v) {
      final List<int> p = v.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      return p.length >= 2 && p[0] == major && p[1] == minor;
    }).toList();

    if (sameMinor.isNotEmpty) {
      sameMinor.sort((a, b) {
        final List<int> pA = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
        final List<int> pB = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
        final int patchA = pA.length > 2 ? pA[2] : 0;
        final int patchB = pB.length > 2 ? pB[2] : 0;
        return (patchA - patch).abs().compareTo((patchB - patch).abs());
      });
      return sameMinor.first;
    }

    final List<String> sortedByMinor = List<String>.from(supported);
    sortedByMinor.sort((a, b) {
      final List<int> pA = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final List<int> pB = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final int minorA = pA.length > 1 ? pA[1] : 0;
      final int minorB = pB.length > 1 ? pB[1] : 0;
      return (minorA - minor).abs().compareTo((minorB - minor).abs());
    });

    return sortedByMinor.first;
  }

  Future<bool> _downloadTexture(File destinationFile) async {
    // 1. Primary: assets.mcasset.cloud
    final String primaryUrl =
        'https://assets.mcasset.cloud/${widget.serverVersion}/assets/minecraft/textures/item/${widget.cleanId}.png';
    // 2. Secondary: PrismarineJS/minecraft-assets (uses closest matching available version folder)
    final String prismarineVersion = _getClosestPrismarineVersion(widget.serverVersion);
    final String secondaryUrl =
        'https://raw.githubusercontent.com/PrismarineJS/minecraft-assets/master/data/$prismarineVersion/items/${widget.cleanId}.png';

    final List<String> urls = <String>[primaryUrl, secondaryUrl];

    final HttpClient client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);

    for (final String url in urls) {
      try {
        final Uri uri = Uri.parse(url);
        final HttpClientRequest request = await client.getUrl(uri);
        final HttpClientResponse response = await request.close();

        if (response.statusCode == 200) {
          await destinationFile.parent.create(recursive: true);
          final List<int> bytes = await response.expand((List<int> chunk) => chunk).toList();
          await destinationFile.writeAsBytes(bytes);
          client.close();
          return true;
        }
      } catch (_) {
        // Fallback to next URL
      }
    }

    client.close();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Stack(
        alignment: Alignment.center,
        children: <Widget>[
          _fallbackWidget(),
          const Positioned(
            right: 0,
            bottom: 0,
            child: SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(strokeWidth: 1.4),
            ),
          ),
        ],
      );
    }

    if (_hasError || _localFile == null) {
      return _fallbackWidget();
    }

    return Image.file(
      _localFile!,
      width: 28,
      height: 28,
      fit: BoxFit.contain,
    );
  }

  Widget _fallbackWidget() {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: widget.fallbackColor.withValues(alpha: 0.7),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          widget.fallbackName.isNotEmpty ? widget.fallbackName[0] : '?',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
