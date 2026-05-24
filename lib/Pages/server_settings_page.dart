import 'package:bifrost/Components/server_navigation_drawer.dart';
import 'package:bifrost/Models/bifrost_server.dart';
import 'package:bifrost/Pages/server_page.dart';
import 'package:bifrost/Pages/server_players_page.dart';
import 'package:bifrost/Pages/server_terminal_page.dart';
import 'package:bifrost/Pages/server_world_page.dart';
import 'package:bifrost/Services/server_manager_service.dart';
import 'package:bifrost/Utils/settings_repository.dart';
import 'package:flutter/material.dart';

class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({
    super.key,
    required this.serverPath,
    required this.serverManager,
  });

  final String serverPath;
  final ServerManagerService serverManager;

  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _slotsController = TextEditingController();
  final TextEditingController _resourcePackController = TextEditingController();
  final TextEditingController _spawnProtectionController =
      TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _onlineMode = true;
  bool _forceGamemode = false;
  bool _resourcePackRequired = false;
  bool _whitelist = false;
  bool _allowFlight = false;
  String _difficulty = 'easy';
  String _gamemode = 'survival';
  String? _errorMessage;

  late final AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    widget.serverManager.addListener(_refresh);
    _loadSettings();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _goHome() {
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
  }

  Future<void> _loadSettings() async {
    final BifrostServer? server = widget.serverManager.serverByPath(
      widget.serverPath,
    );
    if (server == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Server no longer exists.';
      });
      return;
    }

    try {
      final Map<String, String> properties = await widget.serverManager
          .readServerProperties(server);
      if (!mounted) {
        return;
      }
      setState(() {
        _onlineMode = _boolProperty(properties, 'online-mode', fallback: true);
        _forceGamemode = _boolProperty(properties, 'force-gamemode');
        _resourcePackRequired = _boolProperty(
          properties,
          'require-resource-pack',
        );
        _whitelist = _boolProperty(properties, 'white-list');
        _allowFlight = _boolProperty(properties, 'allow-flight');
        _difficulty = _choiceProperty(properties, 'difficulty', <String>[
          'peaceful',
          'easy',
          'normal',
          'hard',
        ], fallback: 'easy');
        _gamemode = _choiceProperty(properties, 'gamemode', <String>[
          'survival',
          'creative',
          'adventure',
          'spectator',
        ], fallback: 'survival');
        _slotsController.text = properties['max-players'] ?? '20';
        _resourcePackController.text = properties['resource-pack'] ?? '';
        _spawnProtectionController.text =
            properties['spawn-protection'] ?? '16';
        _isLoading = false;
        _errorMessage = null;
      });
      if (AppSettings.disableAnimations) {
        _entranceController.value = 1.0;
      } else {
        _entranceController.forward();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
  }

  bool _boolProperty(
    Map<String, String> properties,
    String key, {
    bool fallback = false,
  }) {
    final String? value = properties[key]?.toLowerCase();
    if (value == null) {
      return fallback;
    }
    return value == 'true';
  }

  String _choiceProperty(
    Map<String, String> properties,
    String key,
    List<String> choices, {
    required String fallback,
  }) {
    final String value = properties[key]?.toLowerCase() ?? fallback;
    return choices.contains(value) ? value : fallback;
  }

  Future<void> _setProperty({
    required BifrostServer server,
    required String key,
    required String value,
    required VoidCallback applyLocalValue,
  }) async {
    setState(() {
      _isSaving = true;
      applyLocalValue();
      _errorMessage = null;
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
      _errorMessage = message;
    });
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _saveTextProperty({
    required BifrostServer server,
    required String key,
    required TextEditingController controller,
    required String fallback,
  }) async {
    final String value = controller.text.trim().isEmpty
        ? fallback
        : controller.text.trim();
    controller.text = value;
    await _setProperty(
      server: server,
      key: key,
      value: value,
      applyLocalValue: () {},
    );
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _slotsController.dispose();
    _resourcePackController.dispose();
    _spawnProtectionController.dispose();
    widget.serverManager.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BifrostServer? server = widget.serverManager.serverByPath(
      widget.serverPath,
    );

    if (server == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Server Settings')),
        body: const Center(child: Text('Server no longer exists.')),
      );
    }

    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Scaffold(
      endDrawer: ServerNavigationDrawer(
        server: server,
        selectedIndex: ServerDrawerIndex.settings,
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
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<ServerPlayersPage>(
              builder: (BuildContext context) {
                return ServerPlayersPage(
                  serverPath: server.path,
                  serverManager: widget.serverManager,
                );
              },
            ),
          );
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
        },
      ),
      appBar: AppBar(
        leading: IconButton(
          onPressed: _goHome,
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to servers',
        ),
        title: Text('${server.name} Settings'),
        actions: <Widget>[
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _isSaving
                ? const Padding(
                    key: ValueKey<String>('saving'),
                    padding: EdgeInsets.only(right: 16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey<String>('idle')),
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
          : FadeTransition(
              opacity: _entranceController,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.05),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: _entranceController,
                  curve: Curves.easeOutCubic,
                )),
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: <Widget>[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: colors.primaryContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.security_rounded,
                                    color: colors.onPrimaryContainer,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Server Properties',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _SettingsSwitch(
                              title: 'Online Mode',
                              subtitle: _onlineMode
                                  ? 'Mojang/Microsoft verification enabled.'
                                  : 'Local/offline usernames can join.',
                              value: _onlineMode,
                              onChanged: _isSaving
                                  ? null
                                  : (bool value) {
                                      _setProperty(
                                        server: server,
                                        key: 'online-mode',
                                        value: value ? 'true' : 'false',
                                        applyLocalValue: () {
                                          _onlineMode = value;
                                        },
                                      );
                                    },
                            ),
                            _SettingsTextField(
                              label: 'Slots',
                              helper: 'Writes max-players.',
                              controller: _slotsController,
                              keyboardType: TextInputType.number,
                              onSave: _isSaving
                                  ? null
                                  : () {
                                      _saveTextProperty(
                                        server: server,
                                        key: 'max-players',
                                        controller: _slotsController,
                                        fallback: '20',
                                      );
                                    },
                            ),
                            _SettingsDropdown(
                              label: 'Difficulty',
                              value: _difficulty,
                              values: const <String>[
                                'peaceful',
                                'easy',
                                'normal',
                                'hard',
                              ],
                              onChanged: _isSaving
                                  ? null
                                  : (String? value) {
                                      if (value == null) {
                                        return;
                                      }
                                      _setProperty(
                                        server: server,
                                        key: 'difficulty',
                                        value: value,
                                        applyLocalValue: () {
                                          _difficulty = value;
                                        },
                                      );
                                    },
                            ),
                            _SettingsDropdown(
                              label: 'Gamemode',
                              value: _gamemode,
                              values: const <String>[
                                'survival',
                                'creative',
                                'adventure',
                                'spectator',
                              ],
                              onChanged: _isSaving
                                  ? null
                                  : (String? value) {
                                      if (value == null) {
                                        return;
                                      }
                                      _setProperty(
                                        server: server,
                                        key: 'gamemode',
                                        value: value,
                                        applyLocalValue: () {
                                          _gamemode = value;
                                        },
                                      );
                                    },
                            ),
                            _SettingsSwitch(
                              title: 'Force Gamemode',
                              subtitle:
                                  'Forces players into the configured gamemode.',
                              value: _forceGamemode,
                              onChanged: _isSaving
                                  ? null
                                  : (bool value) {
                                      _setProperty(
                                        server: server,
                                        key: 'force-gamemode',
                                        value: value ? 'true' : 'false',
                                        applyLocalValue: () {
                                          _forceGamemode = value;
                                        },
                                      );
                                    },
                            ),
                            _SettingsSwitch(
                              title: 'Whitelist',
                              subtitle: 'Only whitelisted players can join.',
                              value: _whitelist,
                              onChanged: _isSaving
                                  ? null
                                  : (bool value) {
                                      _setProperty(
                                        server: server,
                                        key: 'white-list',
                                        value: value ? 'true' : 'false',
                                        applyLocalValue: () {
                                          _whitelist = value;
                                        },
                                      );
                                    },
                            ),
                            _SettingsSwitch(
                              title: 'Fly',
                              subtitle:
                                  'Allows flight if the client/mod supports it.',
                              value: _allowFlight,
                              onChanged: _isSaving
                                  ? null
                                  : (bool value) {
                                      _setProperty(
                                        server: server,
                                        key: 'allow-flight',
                                        value: value ? 'true' : 'false',
                                        applyLocalValue: () {
                                          _allowFlight = value;
                                        },
                                      );
                                    },
                            ),
                            _SettingsTextField(
                              label: 'Spawn Protection',
                              helper: 'Blocks protected around world spawn.',
                              controller: _spawnProtectionController,
                              keyboardType: TextInputType.number,
                              onSave: _isSaving
                                  ? null
                                  : () {
                                      _saveTextProperty(
                                        server: server,
                                        key: 'spawn-protection',
                                        controller: _spawnProtectionController,
                                        fallback: '16',
                                      );
                                    },
                            ),
                            _SettingsSwitch(
                              title: 'Resource Pack Required',
                              subtitle:
                                  'Players must accept the configured pack.',
                              value: _resourcePackRequired,
                              onChanged: _isSaving
                                  ? null
                                  : (bool value) {
                                      _setProperty(
                                        server: server,
                                        key: 'require-resource-pack',
                                        value: value ? 'true' : 'false',
                                        applyLocalValue: () {
                                          _resourcePackRequired = value;
                                        },
                                      );
                                    },
                            ),
                            _SettingsTextField(
                              label: 'Resource Pack',
                              helper: 'Direct URL for the server resource pack.',
                              controller: _resourcePackController,
                              keyboardType: TextInputType.url,
                              onSave: _isSaving
                                  ? null
                                  : () {
                                      _saveTextProperty(
                                        server: server,
                                        key: 'resource-pack',
                                        controller: _resourcePackController,
                                        fallback: '',
                                      );
                                    },
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'These controls write to server.properties. Restart the server after changing settings.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: _errorMessage != null
                          ? Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  _errorMessage!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _SettingsDropdown extends StatelessWidget {
  const _SettingsDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        items: <DropdownMenuItem<String>>[
          for (final String item in values)
            DropdownMenuItem<String>(value: item, child: Text(item)),
        ],
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
        ),
      ),
    );
  }
}

class _SettingsTextField extends StatelessWidget {
  const _SettingsTextField({
    required this.label,
    required this.helper,
    required this.controller,
    required this.keyboardType,
    required this.onSave,
  });

  final String label;
  final String helper;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          suffixIcon: IconButton(
            onPressed: onSave,
            icon: const Icon(Icons.save_rounded),
            tooltip: 'Save $label',
          ),
        ),
        onSubmitted: (_) {
          onSave?.call();
        },
      ),
    );
  }
}
