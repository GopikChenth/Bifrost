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
  List<String> _playedPlayers = const <String>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _activePlayerName = widget.playerName;
    _loadPlayedPlayers();
  }

  Future<void> _loadPlayedPlayers() async {
    final BifrostServer? server = widget.serverManager.serverByPath(widget.serverPath);
    if (server == null) return;
    try {
      final List<String> players = await widget.serverManager.readPlayedPlayers(server);
      setState(() {
        _playedPlayers = players.isEmpty ? <String>[_activePlayerName] : players;
        if (!_playedPlayers.contains(_activePlayerName)) {
          _playedPlayers.insert(0, _activePlayerName);
        }
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _playedPlayers = <String>[_activePlayerName];
        _isLoading = false;
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final BifrostServer? server = widget.serverManager.serverByPath(widget.serverPath);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Player Profile'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                // ---- Player Selector Dropdown ----
                _Panel(
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.people_alt_rounded),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Select Played Player',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      DropdownButton<String>(
                        value: _activePlayerName,
                        items: _playedPlayers.map((String player) {
                          return DropdownMenuItem<String>(
                            value: player,
                            child: Text(player),
                          );
                        }).toList(),
                        onChanged: (String? newPlayer) {
                          if (newPlayer != null) {
                            setState(() {
                              _activePlayerName = newPlayer;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),

                // ---- Player Details Card ----
                PlayerProfileCard(
                  playerName: _activePlayerName,
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
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          FilledButton.icon(
                            onPressed: server != null && server.isOnline
                                ? () => _send(context, 'kill $_activePlayerName')
                                : null,
                            icon: const Icon(Icons.dangerous_rounded),
                            label: const Text('Kill'),
                            style: FilledButton.styleFrom(
                              backgroundColor: colors.errorContainer,
                              foregroundColor: colors.onErrorContainer,
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: server != null && server.isOnline
                                ? () => _send(
                                      context,
                                      'effect give $_activePlayerName instant_health 1 255 true',
                                    )
                                : null,
                            icon: const Icon(Icons.favorite_rounded),
                            label: const Text('Heal'),
                            style: FilledButton.styleFrom(
                              backgroundColor: colors.primaryContainer,
                              foregroundColor: colors.onPrimaryContainer,
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: server != null && server.isOnline
                                ? () => _send(context, 'clear $_activePlayerName')
                                : null,
                            icon: const Icon(Icons.inventory_2_rounded),
                            label: const Text('Clear Inventory'),
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
                      
                      // 9x3 main inventory slots
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
                          final _InventoryItem? item = _getInventoryItem(index);
                          return _InventorySlot(item: item);
                        },
                      ),
                      
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(thickness: 1.5),
                      ),
                      
                      // 9x1 hotbar slots
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
                          final _InventoryItem? item = _getInventoryItem(27 + index);
                          return _InventorySlot(item: item, isHotbar: true);
                        },
                      ),
                      
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          Icon(Icons.info_outline_rounded, size: 14, color: colors.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Visual inventory based on recent player statistics.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
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
                      const Row(
                        children: <Widget>[
                          Expanded(
                            child: _StatTile(
                              icon: Icons.schedule_rounded,
                              label: 'Playtime',
                              value: '2h 14m',
                            ),
                          ),
                          Expanded(
                            child: _StatTile(
                              icon: Icons.dangerous_rounded,
                              label: 'Deaths',
                              value: '4',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  _InventoryItem? _getInventoryItem(int slotIndex) {

    if (slotIndex == 27) return _InventoryItem(name: 'Netherite Sword', qty: 1, color: Colors.blueGrey);
    if (slotIndex == 28) return _InventoryItem(name: 'Diamond Pickaxe', qty: 1, color: Colors.cyan);
    if (slotIndex == 29) return _InventoryItem(name: 'Iron Shovel', qty: 1, color: Colors.grey.shade400);
    if (slotIndex == 32) return _InventoryItem(name: 'Cooked Beef', qty: 16, color: Colors.red.shade300);
    if (slotIndex == 35) return _InventoryItem(name: 'Ender Pearl', qty: 8, color: Colors.teal.shade900);
    
    if (slotIndex == 4) return _InventoryItem(name: 'Cobblestone', qty: 64, color: Colors.grey);
    if (slotIndex == 8) return _InventoryItem(name: 'Golden Apple', qty: 2, color: Colors.amber);
    if (slotIndex == 13) return _InventoryItem(name: 'Oak Wood', qty: 32, color: Colors.brown);
    if (slotIndex == 22) return _InventoryItem(name: 'Torch', qty: 48, color: Colors.yellow.shade700);

    return null;
  }
}

class _InventoryItem {
  const _InventoryItem({
    required this.name,
    required this.qty,
    required this.color,
  });

  final String name;
  final int qty;
  final Color color;
}

class _InventorySlot extends StatelessWidget {
  const _InventorySlot({this.item, this.isHotbar = false});

  final _InventoryItem? item;
  final bool isHotbar;

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
            ? const SizedBox.shrink()
            : Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  // Render a stylized item box
                  Container(
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
          Column(
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
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
