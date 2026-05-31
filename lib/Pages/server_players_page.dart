import 'package:bifrost/Components/server_navigation_drawer.dart';
import 'package:bifrost/Components/player_profile_card.dart';
import 'package:bifrost/Models/bifrost_server.dart';
import 'package:bifrost/Pages/server_settings_page.dart';
import 'package:bifrost/Pages/server_page.dart';
import 'package:bifrost/Pages/server_terminal_page.dart';
import 'package:bifrost/Pages/server_world_page.dart';
import 'package:bifrost/Services/server_manager_service.dart';
import 'package:bifrost/Pages/server_player_profile.dart';
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
  bool _isLoading = true;
  Map<String, List<String>> _lists = const <String, List<String>>{};
  List<String> _usercachePlayers = const <String>[];
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
      final List<String> playedPlayers = await widget.serverManager
          .readPlayedPlayers(server);
      if (!mounted) {
        return;
      }
      setState(() {
        _lists = lists;
        _usercachePlayers = playedPlayers;
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

  @override
  void dispose() {
    widget.serverManager.removeListener(_refresh);
    super.dispose();
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
    knownPlayers.addAll(_usercachePlayers);
    knownPlayers.addAll(
      widget.serverManager.knownPlayersFor(widget.serverPath),
    );
    return knownPlayers.toList()..sort(
      (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
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
      child: Material(
        color: colors.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: colors.outlineVariant),
        ),
        child: InkWell(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _scale = 0.95),
          onTapUp: (_) => setState(() => _scale = 1.0),
          onTapCancel: () => setState(() => _scale = 1.0),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    widget.mode.icon,
                    color: colors.onPrimaryContainer,
                    size: 20,
                  ),
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
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
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

  Future<void> _modifyEntry(String value, bool isAdd) async {
    final BifrostServer? server = widget.serverManager.serverByPath(
      widget.serverPath,
    );
    if (server == null) {
      return;
    }

    setState(() {
      _isSending = true;
      _message = null;
    });

    try {
      if (server.isOnline) {
        final String command = isAdd
            ? widget.mode.addCommand(value)
            : widget.mode.removeCommand(value);
        final String? message = await widget.serverManager.sendServerCommand(
          server: server,
          command: command,
        );
        setState(() {
          _message = message;
        });
      } else {
        if (isAdd) {
          await widget.serverManager.addPlayerAccessEntryOffline(
            server: server,
            storageKey: widget.mode.storageKey,
            value: value,
          );
          setState(() {
            _message = 'Added $value offline successfully.';
          });
        } else {
          await widget.serverManager.removePlayerAccessEntryOffline(
            server: server,
            storageKey: widget.mode.storageKey,
            value: value,
          );
          setState(() {
            _message = 'Removed $value offline successfully.';
          });
        }
      }
    } catch (error) {
      setState(() {
        _message = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
      await _load();
    }
  }

  Future<void> _addEntry() async {
    final String value = _controller.text.trim();
    if (value.isEmpty) {
      return;
    }
    _controller.clear();
    await _modifyEntry(value, true);
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
                                : () => _modifyEntry(value, false),
                            icon: const Icon(Icons.delete_rounded),
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ],
                      ),
                    ),
              ],
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
