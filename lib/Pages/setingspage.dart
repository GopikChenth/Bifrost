import 'dart:io';

import 'package:bifrost/Service/server_storage_service.dart';
import 'package:bifrost/Utils/directory_picker_service.dart';
import 'package:bifrost/Utils/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsRepository _settingsRepository = const SettingsRepository();
  final DirectoryPickerService _directoryPickerService =
      const DirectoryPickerService();
  final ServerStorageService _serverStorageService =
      const ServerStorageService();
  final TextEditingController _customPathController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isPickingDirectory = false;
  bool _useDefaultDirectory = true;
  String _customDirectoryUri = '';
  String _resolvedDirectoryPath = ServerDirectorySettings.defaultDirectoryPath;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final ServerDirectorySettings settings =
          await _settingsRepository.loadServerDirectorySettings();
      final String resolvedDirectoryPath =
          await _serverStorageService.resolveBaseDirectoryPath();

      if (!mounted) {
        return;
      }

      setState(() {
        _useDefaultDirectory = settings.useDefaultDirectory;
        _customPathController.text = settings.customDirectoryPath;
        _customDirectoryUri = settings.customDirectoryUri;
        _resolvedDirectoryPath = resolvedDirectoryPath;
        _statusMessage = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage =
            'Settings could not be loaded. App-specific storage will be used.';
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
      final PickedDirectory? selectedDirectory =
          await _directoryPickerService.pickDirectory();

      if (!mounted || selectedDirectory == null) {
        return;
      }

      _customPathController.text = selectedDirectory.path.trim();
      _customDirectoryUri = selectedDirectory.uri.trim();
      _useDefaultDirectory = false;
      await _saveSettings();
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
      _statusMessage = null;
    });

    final String customPath = _customPathController.text.trim();
    try {
      if (!_useDefaultDirectory) {
        await _validateDirectWritableCustomPath(customPath);
      }

      final ServerDirectorySettings settings = ServerDirectorySettings(
        useDefaultDirectory: _useDefaultDirectory,
        customDirectoryPath: _useDefaultDirectory ? '' : customPath,
        customDirectoryUri: _useDefaultDirectory ? '' : _customDirectoryUri,
      );
      await _settingsRepository.saveServerDirectorySettings(settings);

      final String resolvedDirectoryPath =
          await _serverStorageService.resolveBaseDirectoryPath();

      if (!mounted) {
        return;
      }

      setState(() {
        _resolvedDirectoryPath = resolvedDirectoryPath;
        _statusMessage = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Minecraft server directory set to $resolvedDirectoryPath',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _validateDirectWritableCustomPath(String customPath) async {
    if (customPath.isEmpty) {
      throw Exception('Enter or select a custom folder path first.');
    }

    if (_customDirectoryUri.trim().isNotEmpty) {
      return;
    }

    if (!path.isAbsolute(customPath)) {
      throw Exception('Custom server path must be an absolute filesystem path.');
    }

    final Directory baseDirectory = Directory(path.join(customPath, 'minecraft'));
    await baseDirectory.create(recursive: true);
    final File probeFile = File(path.join(baseDirectory.path, '.bifrost_probe'));
    try {
      await probeFile.writeAsString('ok', flush: true);
      if (await probeFile.exists()) {
        await probeFile.delete();
      }
    } on FileSystemException catch (error) {
      throw Exception(
        'Bifrost cannot write to ${baseDirectory.path}: ${error.message}',
      );
    }
  }

  void _setDefaultDirectory(bool value) {
    setState(() {
      _useDefaultDirectory = value;
      if (value) {
        _resolvedDirectoryPath = ServerDirectorySettings.defaultDirectoryPath;
        _statusMessage = null;
      } else if (_customPathController.text.trim().isNotEmpty) {
        _resolvedDirectoryPath =
            path.join(_customPathController.text.trim(), 'minecraft');
      }
    });
  }

  @override
  void dispose() {
    _customPathController.dispose();
    super.dispose();
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
                          'Live servers can use default app storage or a folder selected with Android folder access. If Android does not expose a direct filesystem path for Java, launch will ask you to choose another folder.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Use default app storage'),
                          subtitle: const Text(
                            ServerDirectorySettings.defaultDirectoryPath,
                          ),
                          value: _useDefaultDirectory,
                          onChanged: _setDefaultDirectory,
                        ),
                        if (!_useDefaultDirectory) ...<Widget>[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _customPathController,
                            decoration: const InputDecoration(
                              labelText: 'Custom direct path',
                              hintText: '/storage/emulated/0/Bifrost',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (String value) {
                              setState(() {
                                _resolvedDirectoryPath =
                                    value.trim().isEmpty
                                        ? ServerDirectorySettings
                                              .defaultDirectoryPath
                                        : path.join(value.trim(), 'minecraft');
                              });
                            },
                          ),
                          const SizedBox(height: 10),
                          FilledButton.tonalIcon(
                            onPressed: _isPickingDirectory ? null : _selectPath,
                            icon: const Icon(Icons.folder_open_rounded),
                            label: Text(
                              _isPickingDirectory
                                  ? 'Opening file manager...'
                                  : 'Select Path',
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
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
                                'Active server root',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                _resolvedDirectoryPath,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
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
