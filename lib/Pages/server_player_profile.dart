import 'package:flutter/material.dart';
import 'package:bifrost/Models/bifrost_server.dart';
import 'package:bifrost/Services/server_manager_service.dart';
import 'package:bifrost/Components/player_profile_card.dart';

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
      if (item is Map<String, dynamic> && item['Slot'] == slotIndex) {
        final String fullId = item['id'] as String? ?? '';
        if (fullId.isEmpty) return null;
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final BifrostServer? server = widget.serverManager.serverByPath(widget.serverPath);

    final Map<String, dynamic>? stats = _playerData?['stats'] as Map<String, dynamic>?;
    final double healthVal = (stats?['health'] as num?)?.toDouble() ?? 20.0;
    final int xpVal = (stats?['xpLevel'] as num?)?.toInt() ?? 0;
    final String coordVal = stats?['coordinates'] as String? ?? 'N/A';
    final String playtimeVal = stats?['playtime'] as String? ?? '0m';
    final int deathVal = (stats?['deaths'] as num?)?.toInt() ?? 0;
    final int playerKillsVal = (stats?['playerKills'] as num?)?.toInt() ?? 0;
    final int mobKillsVal = (stats?['mobKills'] as num?)?.toInt() ?? 0;
    final String? playerUuid = _playerData?['uuid'] as String?;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Player Profile'),
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
                          const SizedBox(width: 8),
                          Expanded(
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
                          const SizedBox(width: 8),
                          Expanded(
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
                        ],
                      ),
                    ],
                  ),
                ),

                if (_isLoadingData)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                else ...<Widget>[
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
                                value: '${healthVal.toStringAsFixed(1)} / 20.0 HP',
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

                  // ---- Equipment Section (Armor & Off-hand) ----
                  _Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Equipment & Armor',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            // Armor column
                            Column(
                              children: <Widget>[
                                SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: _InventorySlot(
                                    item: _getInventoryItem(103), // Helmet
                                    emptyIcon: Icons.hdr_strong_outlined,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: _InventorySlot(
                                    item: _getInventoryItem(102), // Chestplate
                                    emptyIcon: Icons.accessibility_new_rounded,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: _InventorySlot(
                                    item: _getInventoryItem(101), // Leggings
                                    emptyIcon: Icons.airline_seat_legroom_extra_rounded,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: _InventorySlot(
                                    item: _getInventoryItem(100), // Boots
                                    emptyIcon: Icons.roller_skating_outlined,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 24),
                            // Offhand column
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Left Hand / Off-hand',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: _InventorySlot(
                                    item: _getInventoryItem(-106), // Off-hand
                                    emptyIcon: Icons.shield_outlined,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ---- Minecraft Stylized Inventory Grid ----
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
                        const SizedBox(height: 12),
                        
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
                            return _InventorySlot(item: item);
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
                            return _InventorySlot(item: item, isHotbar: true);
                          },
                        ),
                      ],
                    ),
                  ),

                  // ---- Collapsible Ender Chest Grid ----
                  _Panel(
                    child: ExpansionTile(
                      leading: Icon(Icons.shopping_bag_rounded, color: colors.primary),
                      title: Text(
                        'Ender Chest',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      subtitle: Text(
                        'Collapsible inter-dimensional storage',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(top: 12, bottom: 4),
                      children: <Widget>[
                        // 9x3 ender chest slots (0 to 26)
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
                            return _InventorySlot(item: item);
                          },
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
  const _InventorySlot({this.item, this.isHotbar = false, this.emptyIcon});

  final _InventoryItem? item;
  final bool isHotbar;
  final IconData? emptyIcon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    
    return Tooltip(
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
                  Image.network(
                    'https://raw.githubusercontent.com/PrismarineJS/minecraft-assets/master/data/1.20.1/items/${item!.cleanId}.png',
                    width: 28,
                    height: 28,
                    fit: BoxFit.contain,
                    errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                      return Image.network(
                        'https://raw.githubusercontent.com/InventivetalentDev/minecraft-assets/1.20.1/assets/minecraft/textures/item/${item!.cleanId}.png',
                        width: 28,
                        height: 28,
                        fit: BoxFit.contain,
                        errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                          return Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: item!.color.withValues(alpha: 0.7),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                item!.name[0],
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
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
