import 'package:bifrost/Components/server_navigation_drawer.dart';
import 'package:bifrost/Components/player_profile_card.dart';
import 'package:bifrost/Models/bifrost_server.dart';
import 'package:bifrost/Pages/server_settings_page.dart';
import 'package:bifrost/Pages/server_page.dart';
import 'package:bifrost/Pages/server_terminal_page.dart';
import 'package:bifrost/Pages/server_world_page.dart';
import 'package:bifrost/Services/server_manager_service.dart';
import 'package:flutter/material.dart';

class ServerPlayersPage extends StatefulWidget {
  const ServerPlayersPage({
    super.key,
    required this.serverPath,
    required this.serverManager,
  });

  final String serverPath;
  final ServerManagerService serverManager;

  @override
  State<ServerPlayersPage> createState() => _ServerPlayersPageState();
}

class _ServerPlayersPageState extends State<ServerPlayersPage> {
  final TextEditingController _whitelistController = TextEditingController();
  final TextEditingController _opController = TextEditingController();
  final TextEditingController _banController = TextEditingController();
  final TextEditingController _banIpController = TextEditingController();
  final TextEditingController _playerController = TextEditingController();
  final TextEditingController _teleportXController = TextEditingController();
  final TextEditingController _teleportYController = TextEditingController();
  final TextEditingController _teleportZController = TextEditingController();

  bool _isLoading = true;
  bool _isSending = false;
  bool _deleteExperience = false;
  bool _deleteInventory = false;
  bool _deleteEnderChest = false;
  bool _deletePlayerData = false;
  bool _deleteStatistics = false;
  bool _deleteAdvancements = false;
  Map<String, List<String>> _lists = const <String, List<String>>{};
  final List<String> _pendingWhitelist = <String>[];
  final List<String> _pendingOps = <String>[];
  final List<String> _pendingBans = <String>[];
  final List<String> _pendingIpBans = <String>[];
  String? _selectedPlayer;
  String _selectedGameMode = 'survival';
  String? _message;

  @override
  void initState() {
    super.initState();
    widget.serverManager.addListener(_refresh);
    _loadLists();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _goHome() {
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
  }

  Future<void> _loadLists() async {
    final BifrostServer? server = widget.serverManager.serverByPath(
      widget.serverPath,
    );
    if (server == null) {
      return;
    }

    try {
      final Map<String, List<String>> lists = await widget.serverManager
          .readPlayerAccessLists(server);
      if (!mounted) {
        return;
      }
      final List<String> knownPlayers = _knownPlayersFrom(lists);
      setState(() {
        _lists = lists;
        _selectedPlayer ??= knownPlayers.isNotEmpty ? knownPlayers.first : null;
        _playerController.text = _selectedPlayer ?? _playerController.text;
        _isLoading = false;
        _message = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _message = error.toString();
      });
    }
  }

  Future<void> _sendCommand(
    BifrostServer server,
    String command, {
    TextEditingController? controller,
  }) async {
    if (!server.isOnline) {
      setState(() {
        _message = 'Start the server before changing player lists.';
      });
      return;
    }

    setState(() {
      _isSending = true;
      _message = null;
    });

    final String? message = await widget.serverManager.sendServerCommand(
      server: server,
      command: command,
    );

    if (!mounted) {
      return;
    }

    controller?.clear();
    setState(() {
      _isSending = false;
      _message = message;
    });
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _loadLists();
  }

  void _addPendingEntry({
    required TextEditingController controller,
    required List<String> target,
  }) {
    final String value = controller.text.trim();
    if (value.isEmpty) {
      return;
    }

    final bool exists = target.any(
      (String current) => current.toLowerCase() == value.toLowerCase(),
    );
    if (exists) {
      controller.clear();
      return;
    }

    setState(() {
      target.add(value);
      controller.clear();
    });
  }

  void _removePendingEntry({
    required List<String> target,
    required String value,
  }) {
    setState(() {
      target.remove(value);
    });
  }

  Future<void> _applyPendingEntries({
    required BifrostServer server,
    required List<String> target,
    required String Function(String value) commandFor,
  }) async {
    if (target.isEmpty) {
      return;
    }
    if (!server.isOnline) {
      setState(() {
        _message = 'Start the server before changing player lists.';
      });
      return;
    }

    final List<String> entries = List<String>.from(target);
    setState(() {
      _isSending = true;
      _message = null;
    });

    String? lastMessage;
    for (final String entry in entries) {
      lastMessage = await widget.serverManager.sendServerCommand(
        server: server,
        command: commandFor(entry),
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      target.clear();
      _isSending = false;
      _message = lastMessage ?? 'Updated ${entries.length} entries.';
    });
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _loadLists();
  }

  Future<void> _sendCommands(
    BifrostServer server,
    List<String> commands,
  ) async {
    final List<String> trimmedCommands = commands
        .map((String command) => command.trim())
        .where((String command) => command.isNotEmpty)
        .toList();
    if (trimmedCommands.isEmpty) {
      return;
    }
    if (!server.isOnline) {
      setState(() {
        _message = 'Start the server before sending player commands.';
      });
      return;
    }

    setState(() {
      _isSending = true;
      _message = null;
    });

    String? lastMessage;
    for (final String command in trimmedCommands) {
      lastMessage = await widget.serverManager.sendServerCommand(
        server: server,
        command: command,
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isSending = false;
      _message = lastMessage ?? 'Sent ${trimmedCommands.length} commands.';
    });
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _loadLists();
  }

  void _selectPlayer(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }
    setState(() {
      _selectedPlayer = trimmed;
      _playerController.text = trimmed;
    });
  }

  Future<void> _runDeleteActions(BifrostServer server) async {
    final String? player = _activePlayer;
    if (player == null) {
      setState(() {
        _message = 'Enter or select a player first.';
      });
      return;
    }

    final List<String> commands = <String>[];
    if (_deleteExperience) {
      commands.add('experience set $player 0 points');
      commands.add('experience set $player 0 levels');
    }
    if (_deleteInventory) {
      commands.add('clear $player');
    }
    if (_deleteEnderChest ||
        _deletePlayerData ||
        _deleteStatistics ||
        _deleteAdvancements) {
      commands.add(
        'say Bifrost: file-level player deletion requires stopping the server first.',
      );
    }

    if (commands.isEmpty) {
      setState(() {
        _message = 'Choose at least one player data option.';
      });
      return;
    }

    await _sendCommands(server, commands);
  }

  @override
  void dispose() {
    _playerController.dispose();
    _whitelistController.dispose();
    _opController.dispose();
    _banController.dispose();
    _banIpController.dispose();
    _teleportXController.dispose();
    _teleportYController.dispose();
    _teleportZController.dispose();
    widget.serverManager.removeListener(_refresh);
    super.dispose();
  }

  String? get _activePlayer {
    final String typedPlayer = _playerController.text.trim();
    if (typedPlayer.isNotEmpty) {
      return typedPlayer;
    }
    return _selectedPlayer?.trim().isNotEmpty == true ? _selectedPlayer : null;
  }

  List<String> _knownPlayersFrom(Map<String, List<String>> lists) {
    final Set<String> knownPlayers = <String>{};
    for (final String key in <String>['whitelist', 'ops', 'bannedPlayers']) {
      for (final String value in lists[key] ?? const <String>[]) {
        if (value.trim().isNotEmpty) {
          knownPlayers.add(value.trim());
        }
      }
    }
    knownPlayers.addAll(
      widget.serverManager.knownPlayersFor(widget.serverPath),
    );
    return knownPlayers.toList()..sort(
      (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
    );
  }


  bool _containsValue(String key, String player) {
    return (_lists[key] ?? const <String>[]).any(
      (String value) => value.toLowerCase() == player.toLowerCase(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final BifrostServer? server = widget.serverManager.serverByPath(
      widget.serverPath,
    );

    if (server == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Players')),
        body: const Center(child: Text('Server no longer exists.')),
      );
    }

    return Scaffold(
      endDrawer: ServerNavigationDrawer(
        server: server,
        selectedIndex: ServerDrawerIndex.players,
        onOpenDashboard: () {
          Navigator.of(context).pop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<ServerPage>(
              builder: (BuildContext context) {
                return ServerPage(
                  serverPath: server.path,
                  serverManager: widget.serverManager,
                );
              },
            ),
          );
        },
        onOpenTerminal: () {
          Navigator.of(context).pop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<TerminalPage>(
              builder: (BuildContext context) {
                return TerminalPage(
                  serverPath: server.path,
                  serverManager: widget.serverManager,
                );
              },
            ),
          );
        },
        onOpenPlayers: () {
          Navigator.of(context).pop();
        },
        onOpenWorld: () {
          Navigator.of(context).pop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<WorldPage>(
              builder: (BuildContext context) {
                return WorldPage(
                  serverPath: server.path,
                  serverManager: widget.serverManager,
                );
              },
            ),
          );
        },
        onOpenSettings: () {
          Navigator.of(context).pop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<ServerSettingsPage>(
              builder: (BuildContext context) {
                return ServerSettingsPage(
                  serverPath: server.path,
                  serverManager: widget.serverManager,
                );
              },
            ),
          );
        },
      ),
      appBar: AppBar(
        leading: IconButton(
          onPressed: _goHome,
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to servers',
        ),
        title: Text('${server.name} Players'),
        actions: <Widget>[
          IconButton(
            onPressed: _isLoading ? null : _loadLists,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh lists',
          ),
          Builder(
            builder: (BuildContext context) {
              return IconButton(
                onPressed: () {
                  Scaffold.of(context).openEndDrawer();
                },
                icon: const Icon(Icons.menu_rounded),
                tooltip: 'Server menu',
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _message != null
                      ? Padding(
                          key: ValueKey<String>(_message!),
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _MessagePanel(message: _message!),
                        )
                      : const SizedBox.shrink(key: ValueKey<String>('no-msg')),
                ),
                _AccessSectionGrid(
                  whitelistCount: _lists['whitelist']?.length ?? 0,
                  opCount: _lists['ops']?.length ?? 0,
                  blacklistCount: _lists['bannedPlayers']?.length ?? 0,
                  bannedIpCount: _lists['bannedIps']?.length ?? 0,
                  onOpen: (PlayerAccessMode mode) async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<PlayerAccessListPage>(
                        builder: (BuildContext context) {
                          return PlayerAccessListPage(
                            mode: mode,
                            serverPath: server.path,
                            serverManager: widget.serverManager,
                          );
                        },
                      ),
                    );
                    await _loadLists();
                  },
                ),
                _PlayerProfilesSection(
                  players: _knownPlayersFrom(_lists),
                  onOpenPlayer: (String player) async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<PlayerProfilePage>(
                        builder: (BuildContext context) {
                          return PlayerProfilePage(
                            playerName: player,
                            serverPath: server.path,
                            serverManager: widget.serverManager,
                          );
                        },
                      ),
                    );
                    await _loadLists();
                  },
                ),
              ],
            ),
    );
  }
}

enum PlayerAccessMode {
  whitelist,
  op,
  blacklist,
  bannedIp;

  String get title {
    return switch (this) {
      PlayerAccessMode.whitelist => 'Whitelist',
      PlayerAccessMode.op => 'OP',
      PlayerAccessMode.blacklist => 'Blacklist',
      PlayerAccessMode.bannedIp => 'Banned IP',
    };
  }

  String get storageKey {
    return switch (this) {
      PlayerAccessMode.whitelist => 'whitelist',
      PlayerAccessMode.op => 'ops',
      PlayerAccessMode.blacklist => 'bannedPlayers',
      PlayerAccessMode.bannedIp => 'bannedIps',
    };
  }

  String get hint {
    return this == PlayerAccessMode.bannedIp ? 'IP address' : 'Player name';
  }

  IconData get icon {
    return switch (this) {
      PlayerAccessMode.whitelist => Icons.person_add_alt_1_rounded,
      PlayerAccessMode.op => Icons.admin_panel_settings_rounded,
      PlayerAccessMode.blacklist => Icons.person_off_rounded,
      PlayerAccessMode.bannedIp => Icons.public_off_rounded,
    };
  }

  String addCommand(String value) {
    return switch (this) {
      PlayerAccessMode.whitelist => 'whitelist add $value',
      PlayerAccessMode.op => 'op $value',
      PlayerAccessMode.blacklist => 'ban $value',
      PlayerAccessMode.bannedIp => 'ban-ip $value',
    };
  }

  String removeCommand(String value) {
    return switch (this) {
      PlayerAccessMode.whitelist => 'whitelist remove $value',
      PlayerAccessMode.op => 'deop $value',
      PlayerAccessMode.blacklist => 'pardon $value',
      PlayerAccessMode.bannedIp => 'pardon-ip $value',
    };
  }
}

class _AccessSectionGrid extends StatelessWidget {
  const _AccessSectionGrid({
    required this.whitelistCount,
    required this.opCount,
    required this.blacklistCount,
    required this.bannedIpCount,
    required this.onOpen,
  });

  final int whitelistCount;
  final int opCount;
  final int blacklistCount;
  final int bannedIpCount;
  final ValueChanged<PlayerAccessMode> onOpen;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.45,
      children: <Widget>[
        _AccessSectionTile(
          mode: PlayerAccessMode.whitelist,
          count: whitelistCount,
          onTap: () => onOpen(PlayerAccessMode.whitelist),
        ),
        _AccessSectionTile(
          mode: PlayerAccessMode.op,
          count: opCount,
          onTap: () => onOpen(PlayerAccessMode.op),
        ),
        _AccessSectionTile(
          mode: PlayerAccessMode.blacklist,
          count: blacklistCount,
          onTap: () => onOpen(PlayerAccessMode.blacklist),
        ),
        _AccessSectionTile(
          mode: PlayerAccessMode.bannedIp,
          count: bannedIpCount,
          onTap: () => onOpen(PlayerAccessMode.bannedIp),
        ),
      ],
    );
  }
}

class _AccessSectionTile extends StatefulWidget {
  const _AccessSectionTile({
    required this.mode,
    required this.count,
    required this.onTap,
  });

  final PlayerAccessMode mode;
  final int count;
  final VoidCallback onTap;

  @override
  State<_AccessSectionTile> createState() => _AccessSectionTileState();
}

class _AccessSectionTileState extends State<_AccessSectionTile> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return AnimatedScale(
      scale: _scale,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutBack,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _scale = 0.95),
        onTapUp: (_) => setState(() => _scale = 1.0),
        onTapCancel: () => setState(() => _scale = 1.0),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.mode.icon, color: colors.onPrimaryContainer, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      widget.mode.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${widget.count} entries',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerProfilesSection extends StatelessWidget {
  const _PlayerProfilesSection({
    required this.players,
    required this.onOpenPlayer,
  });

  final List<String> players;
  final ValueChanged<String> onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Player profiles',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          if (players.isEmpty)
            const _Panel(
              child: Text(
                'No player profiles found yet. Add a player in Whitelist, OP, or Blacklist to create a profile shortcut.',
              ),
            )
          else
            for (final String player in players)
              PlayerProfileCard(
                playerName: player,
                subtitle: 'Tap to view inventory, stats, and controls',
                onTap: () => onOpenPlayer(player),
              ),
        ],
      ),
    );
  }
}

class PlayerAccessListPage extends StatefulWidget {
  const PlayerAccessListPage({
    super.key,
    required this.mode,
    required this.serverPath,
    required this.serverManager,
  });

  final PlayerAccessMode mode;
  final String serverPath;
  final ServerManagerService serverManager;

  @override
  State<PlayerAccessListPage> createState() => _PlayerAccessListPageState();
}

class _PlayerAccessListPageState extends State<PlayerAccessListPage> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = true;
  bool _isSending = false;
  List<String> _values = const <String>[];
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final BifrostServer? server = widget.serverManager.serverByPath(
      widget.serverPath,
    );
    if (server == null) {
      return;
    }
    try {
      final Map<String, List<String>> lists = await widget.serverManager
          .readPlayerAccessLists(server);
      if (!mounted) {
        return;
      }
      setState(() {
        _values = lists[widget.mode.storageKey] ?? const <String>[];
        _isLoading = false;
        _message = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _message = error.toString();
      });
    }
  }

  Future<void> _send(String command) async {
    final BifrostServer? server = widget.serverManager.serverByPath(
      widget.serverPath,
    );
    if (server == null) {
      return;
    }
    if (!server.isOnline) {
      setState(() {
        _message = 'Start the server before changing ${widget.mode.title}.';
      });
      return;
    }
    setState(() {
      _isSending = true;
      _message = null;
    });
    final String? message = await widget.serverManager.sendServerCommand(
      server: server,
      command: command,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isSending = false;
      _message = message;
    });
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _load();
  }

  Future<void> _addEntry() async {
    final String value = _controller.text.trim();
    if (value.isEmpty) {
      return;
    }
    _controller.clear();
    await _send(widget.mode.addCommand(value));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mode.title),
        actions: <Widget>[
          IconButton(
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                if (_message != null) ...<Widget>[
                  _MessagePanel(message: _message!),
                  const SizedBox(height: 10),
                ],
                _Panel(
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: InputDecoration(
                            labelText: widget.mode.hint,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _addEntry(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _isSending ? null : _addEntry,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                ),
                if (_values.isEmpty)
                  _Panel(child: Text('No ${widget.mode.title} entries yet.'))
                else
                  for (final String value in _values)
                    _Panel(
                      child: Row(
                        children: <Widget>[
                          Icon(widget.mode.icon),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              value,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            onPressed: _isSending
                                ? null
                                : () => _send(widget.mode.removeCommand(value)),
                            icon: const Icon(Icons.delete_rounded),
                            color: Colors.red.shade700,
                          ),
                        ],
                      ),
                    ),
              ],
            ),
    );
  }
}

class PlayerProfilePage extends StatelessWidget {
  const PlayerProfilePage({
    super.key,
    required this.playerName,
    required this.serverPath,
    required this.serverManager,
  });

  final String playerName;
  final String serverPath;
  final ServerManagerService serverManager;

  Future<void> _send(BuildContext context, String command) async {
    final BifrostServer? server = serverManager.serverByPath(serverPath);
    if (server == null || !server.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start the server before sending commands.'),
        ),
      );
      return;
    }
    final String? message = await serverManager.sendServerCommand(
      server: server,
      command: command,
    );
    if (context.mounted && message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(playerName)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          PlayerProfileCard(
            playerName: playerName,
            subtitle: 'Individual profile controls',
            onTap: () {},
          ),
          _Panel(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: () => _send(context, 'kill $playerName'),
                  icon: const Icon(Icons.dangerous_rounded),
                  label: const Text('Kill'),
                ),
                FilledButton.icon(
                  onPressed: () => _send(
                    context,
                    'effect give $playerName instant_health 1 255 true',
                  ),
                  icon: const Icon(Icons.favorite_rounded),
                  label: const Text('Heal'),
                ),
                FilledButton.icon(
                  onPressed: () => _send(context, 'clear $playerName'),
                  icon: const Icon(Icons.inventory_2_rounded),
                  label: const Text('Clear inventory'),
                ),
              ],
            ),
          ),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Inventory',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 9,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: 27,
                  itemBuilder: (BuildContext context, int index) {
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'NBT inventory parsing will be wired here later.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Stats',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                        value: 'No data',
                      ),
                    ),
                    Expanded(
                      child: _StatTile(
                        icon: Icons.dangerous_rounded,
                        label: 'Deaths',
                        value: 'No data',
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
}

class _PlayerControlDashboard extends StatelessWidget {
  const _PlayerControlDashboard({
    required this.server,
    required this.selectedPlayer,
    required this.knownPlayers,
    required this.playerController,
    required this.teleportXController,
    required this.teleportYController,
    required this.teleportZController,
    required this.selectedGameMode,
    required this.isSending,
    required this.whitelisted,
    required this.banned,
    required this.isOperator,
    required this.deleteExperience,
    required this.deleteInventory,
    required this.deleteEnderChest,
    required this.deletePlayerData,
    required this.deleteStatistics,
    required this.deleteAdvancements,
    required this.onSelectPlayer,
    required this.onGameModeChanged,
    required this.onKill,
    required this.onHeal,
    required this.onStarve,
    required this.onFeed,
    required this.onToggleWhitelist,
    required this.onToggleBan,
    required this.onToggleOperator,
    required this.onTeleport,
    required this.onDeleteExperienceChanged,
    required this.onDeleteInventoryChanged,
    required this.onDeleteEnderChestChanged,
    required this.onDeletePlayerDataChanged,
    required this.onDeleteStatisticsChanged,
    required this.onDeleteAdvancementsChanged,
    required this.onSelectAllDeleteChanged,
    required this.onDeletePlayerData,
  });

  final BifrostServer server;
  final String? selectedPlayer;
  final List<String> knownPlayers;
  final TextEditingController playerController;
  final TextEditingController teleportXController;
  final TextEditingController teleportYController;
  final TextEditingController teleportZController;
  final String selectedGameMode;
  final bool isSending;
  final bool whitelisted;
  final bool banned;
  final bool isOperator;
  final bool deleteExperience;
  final bool deleteInventory;
  final bool deleteEnderChest;
  final bool deletePlayerData;
  final bool deleteStatistics;
  final bool deleteAdvancements;
  final ValueChanged<String> onSelectPlayer;
  final ValueChanged<String> onGameModeChanged;
  final VoidCallback onKill;
  final VoidCallback onHeal;
  final VoidCallback onStarve;
  final VoidCallback onFeed;
  final VoidCallback onToggleWhitelist;
  final VoidCallback onToggleBan;
  final VoidCallback onToggleOperator;
  final VoidCallback onTeleport;
  final ValueChanged<bool> onDeleteExperienceChanged;
  final ValueChanged<bool> onDeleteInventoryChanged;
  final ValueChanged<bool> onDeleteEnderChestChanged;
  final ValueChanged<bool> onDeletePlayerDataChanged;
  final ValueChanged<bool> onDeleteStatisticsChanged;
  final ValueChanged<bool> onDeleteAdvancementsChanged;
  final ValueChanged<bool> onSelectAllDeleteChanged;
  final VoidCallback onDeletePlayerData;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool allDeleteSelected =
        deleteExperience &&
        deleteInventory &&
        deleteEnderChest &&
        deletePlayerData &&
        deleteStatistics &&
        deleteAdvancements;

    return Column(
      children: <Widget>[
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Player details',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.person_rounded,
                      color: colors.primary,
                      size: 38,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: playerController,
                      decoration: InputDecoration(
                        labelText: 'Player name',
                        hintText: 'Exact username',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        suffixIcon: IconButton(
                          onPressed: isSending
                              ? null
                              : () => onSelectPlayer(playerController.text),
                          icon: const Icon(Icons.check_rounded),
                        ),
                      ),
                      onSubmitted: onSelectPlayer,
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedGameMode,
                      items: const <DropdownMenuItem<String>>[
                        DropdownMenuItem<String>(
                          value: 'survival',
                          child: Text('Survival'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'creative',
                          child: Text('Creative'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'adventure',
                          child: Text('Adventure'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'spectator',
                          child: Text('Spectator'),
                        ),
                      ],
                      onChanged: isSending
                          ? null
                          : (String? value) {
                              if (value != null) {
                                onGameModeChanged(value);
                              }
                            },
                    ),
                  ),
                ],
              ),
              if (knownPlayers.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final String player in knownPlayers)
                      ChoiceChip(
                        label: Text(player),
                        selected:
                            selectedPlayer?.toLowerCase() ==
                            player.toLowerCase(),
                        onSelected: isSending
                            ? null
                            : (_) {
                                onSelectPlayer(player);
                              },
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Health and experience',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: 0,
                  minHeight: 12,
                  color: colors.primary,
                  backgroundColor: colors.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _CommandButton(
                      label: 'Kill',
                      icon: Icons.dangerous_rounded,
                      color: const Color(0xFFE97152),
                      onPressed: isSending ? null : onKill,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CommandButton(
                      label: 'Heal',
                      icon: Icons.favorite_rounded,
                      color: const Color(0xFF25D18A),
                      onPressed: isSending ? null : onHeal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _CommandButton(
                      label: 'Starve',
                      icon: Icons.no_food_rounded,
                      color: const Color(0xFFE97152),
                      onPressed: isSending ? null : onStarve,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CommandButton(
                      label: 'Feed',
                      icon: Icons.restaurant_rounded,
                      color: const Color(0xFF25D18A),
                      onPressed: isSending ? null : onFeed,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Control',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              _SwitchRow(
                label: 'Whitelisted',
                icon: Icons.person_add_alt_1_rounded,
                value: whitelisted,
                enabled: selectedPlayer != null && !isSending,
                onPressed: onToggleWhitelist,
              ),
              _SwitchRow(
                label: 'Banned',
                icon: Icons.person_off_rounded,
                value: banned,
                enabled: selectedPlayer != null && !isSending,
                onPressed: onToggleBan,
              ),
              _SwitchRow(
                label: 'Operator',
                icon: Icons.admin_panel_settings_rounded,
                value: isOperator,
                enabled: selectedPlayer != null && !isSending,
                onPressed: onToggleOperator,
              ),
            ],
          ),
        ),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Information',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _CoordinateField(
                      controller: teleportXController,
                      label: 'X',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CoordinateField(
                      controller: teleportYController,
                      label: 'Y',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CoordinateField(
                      controller: teleportZController,
                      label: 'Z',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: isSending ? null : onTeleport,
                  icon: const Icon(Icons.transfer_within_a_station_rounded),
                  label: const Text('Teleport'),
                ),
              ),
            ],
          ),
        ),
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
                children: const <Widget>[
                  Expanded(
                    child: _StatTile(
                      icon: Icons.schedule_rounded,
                      label: 'Playtime',
                      value: 'No data',
                    ),
                  ),
                  Expanded(
                    child: _StatTile(
                      icon: Icons.sports_kabaddi_rounded,
                      label: 'Player Kills',
                      value: 'No data',
                    ),
                  ),
                ],
              ),
              Row(
                children: const <Widget>[
                  Expanded(
                    child: _StatTile(
                      icon: Icons.dangerous_rounded,
                      label: 'Deaths',
                      value: 'No data',
                    ),
                  ),
                  Expanded(
                    child: _StatTile(
                      icon: Icons.speed_rounded,
                      label: 'KDR',
                      value: 'No data',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Delete player data',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _CheckPill(
                    label: 'Experience points',
                    value: deleteExperience,
                    onChanged: onDeleteExperienceChanged,
                  ),
                  _CheckPill(
                    label: 'Inventory',
                    value: deleteInventory,
                    onChanged: onDeleteInventoryChanged,
                  ),
                  _CheckPill(
                    label: 'Ender Chest',
                    value: deleteEnderChest,
                    onChanged: onDeleteEnderChestChanged,
                  ),
                  _CheckPill(
                    label: 'Player data file',
                    value: deletePlayerData,
                    onChanged: onDeletePlayerDataChanged,
                  ),
                  _CheckPill(
                    label: 'Statistics file',
                    value: deleteStatistics,
                    onChanged: onDeleteStatisticsChanged,
                  ),
                  _CheckPill(
                    label: 'Advancements file',
                    value: deleteAdvancements,
                    onChanged: onDeleteAdvancementsChanged,
                  ),
                  _CheckPill(
                    label: 'Select all',
                    value: allDeleteSelected,
                    onChanged: onSelectAllDeleteChanged,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Center(
                child: FilledButton.icon(
                  onPressed: isSending ? null : onDeletePlayerData,
                  icon: const Icon(Icons.delete_rounded),
                  label: const Text('Delete player data'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: child,
    );
  }
}

class _CommandButton extends StatelessWidget {
  const _CommandButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool value;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: value ? colors.primary : colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Switch(value: value, onChanged: enabled ? (_) => onPressed() : null),
        ],
      ),
    );
  }
}

class _CoordinateField extends StatelessWidget {
  const _CoordinateField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
        signed: true,
        decimal: true,
      ),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
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
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: <Widget>[
          Icon(icon, color: colors.primary, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
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

class _CheckPill extends StatelessWidget {
  const _CheckPill({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label),
      selected: value,
      avatar: Icon(
        value ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
      ),
      selectedColor: colors.primaryContainer,
      onSelected: onChanged,
    );
  }
}

class _PlayerAccessCard extends StatelessWidget {
  const _PlayerAccessCard({
    required this.title,
    required this.subtitle,
    required this.values,
    required this.pendingValues,
    required this.controller,
    required this.hintText,
    required this.addLabel,
    required this.applyLabel,
    required this.removeLabel,
    required this.isSending,
    required this.onAddPending,
    required this.onRemovePending,
    required this.onApplyPending,
    required this.onRemoveSaved,
  });

  final String title;
  final String subtitle;
  final List<String> values;
  final List<String> pendingValues;
  final TextEditingController controller;
  final String hintText;
  final String addLabel;
  final String applyLabel;
  final String removeLabel;
  final bool isSending;
  final VoidCallback onAddPending;
  final ValueChanged<String> onRemovePending;
  final VoidCallback onApplyPending;
  final ValueChanged<String> onRemoveSaved;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: hintText,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: isSending
                      ? null
                      : (String value) {
                          final String trimmed = value.trim();
                          if (trimmed.isNotEmpty) {
                            onAddPending();
                          }
                        },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: isSending
                    ? null
                    : () {
                        final String trimmed = controller.text.trim();
                        if (trimmed.isNotEmpty) {
                          onAddPending();
                        }
                      },
                child: Text(addLabel),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (pendingValues.isNotEmpty) ...<Widget>[
            Text(
              'Pending',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String value in pendingValues)
                  InputChip(
                    label: Text(value),
                    onDeleted: isSending
                        ? null
                        : () {
                            onRemovePending(value);
                          },
                    deleteIcon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: isSending ? null : onApplyPending,
                icon: const Icon(Icons.done_all_rounded),
                label: Text(applyLabel),
              ),
            ),
            const Divider(height: 22),
          ],
          if (values.isEmpty)
            Text(
              'No saved entries yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String value in values)
                  InputChip(
                    label: Text(value),
                    onDeleted: isSending
                        ? null
                        : () {
                            onRemoveSaved(value);
                          },
                    deleteIcon: const Icon(Icons.close_rounded),
                    deleteButtonTooltipMessage: removeLabel,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(message, style: TextStyle(color: colors.onSurfaceVariant)),
    );
  }
}
