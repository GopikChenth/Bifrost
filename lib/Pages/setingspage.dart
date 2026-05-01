import 'package:bifrost/Utils/directory_picker_service.dart';
import 'package:bifrost/Utils/settings_repository.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsRepository _settingsRepository = const SettingsRepository();
  final DirectoryPickerService _directoryPickerService =
      const DirectoryPickerService();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isPickingDirectory = false;
  bool _useDefaultDirectory = true;
  String _customDirectoryPath = '';
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final ServerDirectorySettings settings = await _settingsRepository
          .loadServerDirectorySettings();

      if (!mounted) {
        return;
      }

      setState(() {
        _useDefaultDirectory = settings.useDefaultDirectory;
        _customDirectoryPath = settings.customDirectoryPath;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _useDefaultDirectory = true;
        _customDirectoryPath = '';
        _statusMessage =
            'Settings could not be loaded. Using the default directory.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectPath() async {
    setState(() {
      _isPickingDirectory = true;
    });

    try {
      final String? selectedPath = await _directoryPickerService
          .pickDirectory();

      if (!mounted) {
        return;
      }

      if (selectedPath != null && selectedPath.trim().isNotEmpty) {
        setState(() {
          _useDefaultDirectory = false;
          _customDirectoryPath = selectedPath.trim();
          _statusMessage = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Unable to open the file manager on this device.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPickingDirectory = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isSaving = true;
    });

    final ServerDirectorySettings settings = ServerDirectorySettings(
      useDefaultDirectory: _useDefaultDirectory,
      customDirectoryPath: _customDirectoryPath,
    );

    try {
      await _settingsRepository.saveServerDirectorySettings(settings);

      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Minecraft server directory set to ${settings.effectiveDirectoryPath}',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage = 'Settings could not be saved.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _setDefaultDirectory(bool value) {
    setState(() {
      _useDefaultDirectory = value;
    });
  }

  String get _effectiveDirectoryPath {
    return ServerDirectorySettings(
      useDefaultDirectory: _useDefaultDirectory,
      customDirectoryPath: _customDirectoryPath,
    ).effectiveDirectoryPath;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.outlineVariant),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Minecraft Server Directory',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Choose where Bifrost stores server jars, worlds, mods, and backups.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Server creation currently uses app storage for reliability on Android. Custom external folders are saved for future SAF-based support.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        if (_statusMessage != null) ...<Widget>[
                          const SizedBox(height: 16),
                          Text(
                            _statusMessage!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Use default internal storage'),
                          subtitle: const Text(
                            ServerDirectorySettings.defaultDirectoryPath,
                          ),
                          value: _useDefaultDirectory,
                          onChanged: _setDefaultDirectory,
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Current directory',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                _effectiveDirectoryPath,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!_useDefaultDirectory) ...<Widget>[
                          const SizedBox(height: 16),
                          FilledButton.tonalIcon(
                            onPressed: _isPickingDirectory ? null : _selectPath,
                            icon: const Icon(Icons.folder_open_rounded),
                            label: Text(
                              _isPickingDirectory
                                  ? 'Opening file manager...'
                                  : 'Select Path',
                            ),
                          ),
                          if (_customDirectoryPath
                              .trim()
                              .isNotEmpty) ...<Widget>[
                            const SizedBox(height: 10),
                            Text(
                              'Selected folder: $_customDirectoryPath',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ] else ...<Widget>[
                          const SizedBox(height: 16),
                          FilledButton.tonalIcon(
                            onPressed: _isPickingDirectory
                                ? null
                                : () async {
                                    await _selectPath();
                                  },
                            icon: const Icon(Icons.folder_open_rounded),
                            label: const Text('Choose Custom Path'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: FilledButton(
          onPressed: _isLoading || _isSaving ? null : _saveSettings,
          child: Text(_isSaving ? 'Saving...' : 'Save Settings'),
        ),
      ),
    );
  }
}
