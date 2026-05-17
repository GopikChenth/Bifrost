import 'package:bifrost/Models/bifrost_server.dart';
import 'package:bifrost/Services/server_manager_service.dart';
import 'package:flutter/material.dart';

class WorldOptionsPage extends StatefulWidget {
  const WorldOptionsPage({
    super.key,
    required this.serverPath,
    required this.serverManager,
  });

  final String serverPath;
  final ServerManagerService serverManager;

  @override
  State<WorldOptionsPage> createState() => _WorldOptionsPageState();
}

class _WorldOptionsPageState extends State<WorldOptionsPage> {
  final TextEditingController _seedController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hardcore = false;
  String _difficulty = 'easy';
  String? _message;
  final Map<String, bool> _boolRules = <String, bool>{
    'spawn_wandering_traders': true,
    'block_drops': true,
    'reduced_debug_info': false,
    'show_death_messages': true,
    'spawn_monsters': true,
    'spawner_blocks_work': true,
    'tnt_explodes': true,
    'immediate_respawn': false,
    'player_movement_check': true,
    'block_explosion_drop_decay': true,
    'forgive_dead_players': true,
    'fall_damage': true,
    'send_command_feedback': true,
    'global_sound_events': true,
    'elytra_movement_check': true,
    'freeze_damage': true,
    'natural_health_regeneration': true,
    'mob_drops': true,
    'mob_griefing': true,
    'log_admin_commands': true,
    'spawn_mobs': true,
    'pvp': true,
    'spectators_generate_chunks': true,
    'advance_weather': true,
    'drowning_damage': true,
    'command_block_output': true,
    'locator_bar': true,
    'show_advancement_messages': true,
    'raids': true,
    'spawn_phantoms': true,
    'limited_crafting': false,
    'allow_entering_nether_using_portals': true,
    'lava_source_conversion': false,
    'tnt_explosion_drop_decay': false,
    'universal_anger': false,
    'keep_inventory': false,
    'spawn_patrols': true,
    'fire_damage': true,
    'advance_time': true,
    'entity_drops': true,
    'command_blocks_work': true,
    'spawn_wardens': true,
    'water_source_conversion': true,
    'projectiles_can_break_blocks': true,
    'ender_pearls_vanish_on_death': true,
  };
  final Map<String, int> _numberRules = <String, int>{
    'max_entity_cramming': 24,
    'fire_spread_radius_around_player': 128,
    'players_nether_portal_default_delay': 80,
    'players_sleeping_percentage': 100,
    'max_command_sequence_length': 65536,
    'players_nether_portal_creative_delay': 0,
    'max_block_modifications': 32768,
    'max_command_forks': 65536,
    'respawn_radius': 10,
    'max_snow_accumulation_height': 1,
    'random_tick_speed': 3,
  };

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _seedController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    final BifrostServer? server = widget.serverManager.serverByPath(widget.serverPath);
    if (server == null) {
      return;
    }
    try {
      final Map<String, String> properties = await widget.serverManager.readServerProperties(server);
      if (!mounted) {
        return;
      }
      setState(() {
        _seedController.text = properties['level-seed'] ?? '';
        _difficulty = _choice(properties['difficulty'], <String>['peaceful', 'easy', 'normal', 'hard'], 'easy');
        _hardcore = (properties['hardcore'] ?? 'false').toLowerCase() == 'true';
        _isLoading = false;
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

  String _choice(String? value, List<String> values, String fallback) {
    final String normalized = value?.toLowerCase() ?? fallback;
    return values.contains(normalized) ? normalized : fallback;
  }

  Future<void> _setProperty(String key, String value) async {
    final BifrostServer? server = widget.serverManager.serverByPath(widget.serverPath);
    if (server == null) {
      return;
    }
    setState(() {
      _isSaving = true;
      _message = null;
    });
    final String? message = await widget.serverManager.updateServerProperty(
      server: server,
      key: key,
      value: value,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isSaving = false;
      _message = message;
    });
  }

  Future<void> _sendGamerule(String name, String value) async {
    final BifrostServer? server = widget.serverManager.serverByPath(widget.serverPath);
    if (server == null) {
      return;
    }
    if (!server.isOnline) {
      setState(() {
        _message = 'Start the server before changing gamerules.';
      });
      return;
    }
    setState(() {
      _isSaving = true;
      _message = null;
    });
    final String? message = await widget.serverManager.sendServerCommand(
      server: server,
      command: 'gamerule $name $value',
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isSaving = false;
      _message = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('World Options')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                if (_message != null) ...<Widget>[
                  _MessagePanel(message: _message!),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _OptionPanel(
                        title: 'Seed',
                        footer: 'level-seed: ${_seedController.text.trim().isEmpty ? 'random' : _seedController.text.trim()}',
                        child: TextField(
                          controller: _seedController,
                          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                          keyboardType: TextInputType.number,
                          onSubmitted: (String value) => _setProperty('level-seed', value.trim()),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _OptionPanel(
                        title: 'Hardcore',
                        footer: 'hardcore: $_hardcore',
                        trailing: Switch(
                          value: _hardcore,
                          onChanged: _isSaving
                              ? null
                              : (bool value) {
                                  setState(() => _hardcore = value);
                                  _setProperty('hardcore', value ? 'true' : 'false');
                                },
                        ),
                      ),
                    ),
                  ],
                ),
                _OptionPanel(
                  title: 'Difficulty',
                  footer: 'difficulty: $_difficulty',
                  trailing: DropdownButton<String>(
                    value: _difficulty,
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(value: 'peaceful', child: Text('Peaceful')),
                      DropdownMenuItem<String>(value: 'easy', child: Text('Easy')),
                      DropdownMenuItem<String>(value: 'normal', child: Text('Normal')),
                      DropdownMenuItem<String>(value: 'hard', child: Text('Hard')),
                    ],
                    onChanged: _isSaving
                        ? null
                        : (String? value) {
                            if (value != null) {
                              setState(() => _difficulty = value);
                              _setProperty('difficulty', value);
                            }
                          },
                  ),
                ),
                _ChipPanel(title: 'Enabled features', footer: 'enabled_features: minecraft:vanilla', chips: const <String>['Vanilla']),
                _ChipPanel(title: 'Enabled datapacks', footer: 'enabled: vanilla', chips: const <String>['Vanilla']),
                _ChipPanel(title: 'Disabled datapacks', footer: 'disabled: minecart_improvements, redstone_experiments, trade_rebalance', chips: const <String>['Minecart Improvements', 'Redstone Experiments', 'Trade Rebalance']),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Icon(Icons.construction_rounded, color: colors.primary),
                    const SizedBox(width: 8),
                    Text('Gamerules', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    if (_isSaving) ...<Widget>[
                      const SizedBox(width: 10),
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                for (final MapEntry<String, bool> entry in _boolRules.entries)
                  _BoolRuleTile(
                    name: entry.key,
                    value: entry.value,
                    onChanged: (bool value) {
                      setState(() => _boolRules[entry.key] = value);
                      _sendGamerule(entry.key, value ? 'true' : 'false');
                    },
                  ),
                for (final MapEntry<String, int> entry in _numberRules.entries)
                  _NumberRuleTile(
                    name: entry.key,
                    value: entry.value,
                    onChanged: (int value) {
                      setState(() => _numberRules[entry.key] = value);
                      _sendGamerule(entry.key, value.toString());
                    },
                  ),
              ],
            ),
    );
  }
}

class _OptionPanel extends StatelessWidget {
  const _OptionPanel({required this.title, required this.footer, this.child, this.trailing});

  final String title;
  final String footer;
  final Widget? child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(children: <Widget>[Expanded(child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))), if (trailing != null) trailing!]),
          if (child != null) ...<Widget>[const SizedBox(height: 8), child!],
          const SizedBox(height: 6),
          Text(footer, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

class _ChipPanel extends StatelessWidget {
  const _ChipPanel({required this.title, required this.footer, required this.chips});

  final String title;
  final String footer;
  final List<String> chips;

  @override
  Widget build(BuildContext context) {
    return _OptionPanel(
      title: title,
      footer: footer,
      child: Wrap(spacing: 8, runSpacing: 8, children: <Widget>[for (final String chip in chips) Chip(label: Text(chip))]),
    );
  }
}

class _BoolRuleTile extends StatelessWidget {
  const _BoolRuleTile({required this.name, required this.value, required this.onChanged});

  final String name;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _OptionPanel(
      title: name,
      footer: 'minecraft:$name: $value',
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }
}

class _NumberRuleTile extends StatelessWidget {
  const _NumberRuleTile({required this.name, required this.value, required this.onChanged});

  final String name;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return _OptionPanel(
      title: name,
      footer: 'minecraft:$name: $value',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(onPressed: () => onChanged(value > 0 ? value - 1 : 0), icon: const Icon(Icons.remove_rounded)),
          Text(value.toString()),
          IconButton(onPressed: () => onChanged(value + 1), icon: const Icon(Icons.add_rounded)),
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
      decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
      child: Text(message, style: TextStyle(color: colors.onSurfaceVariant)),
    );
  }
}
