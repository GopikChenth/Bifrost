import 'package:bifrost/Services/server_storage_service.dart';
import 'package:bifrost/Utils/settings_repository.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  final SettingsRepository _settingsRepository = const SettingsRepository();
  final ServerStorageService _serverStorageService =
      const ServerStorageService();
  final TextEditingController _customPathController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _useDefaultDirectory = true;
  bool _hasAllFilesAccess = false;
  String _resolvedDirectoryPath = ServerDirectorySettings.defaultDirectoryPath;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check permission when the user returns from system settings.
    if (state == AppLifecycleState.resumed) {
      _refreshPermissionStatus();
    }
  }

  Future<void> _refreshPermissionStatus() async {
    final bool hasAccess = await _serverStorageService.hasAllFilesAccess();
    if (mounted && hasAccess != _hasAllFilesAccess) {
      setState(() {
        _hasAllFilesAccess = hasAccess;
      });
    }
  }

  Future<void> _loadSettings() async {
    try {
      final ServerDirectorySettings settings = await _settingsRepository
          .loadServerDirectorySettings();
      final String resolvedDirectoryPath = await _serverStorageService
          .resolveBaseDirectoryPath();
      final bool hasAccess = await _serverStorageService.hasAllFilesAccess();

      if (!mounted) return;

      setState(() {
        _useDefaultDirectory = settings.useDefaultDirectory;
        _customPathController.text = settings.customDirectoryPath;
        _resolvedDirectoryPath = resolvedDirectoryPath;
        _hasAllFilesAccess = hasAccess;
        _statusMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusMessage =
            'Settings could not be loaded. Default storage will be used.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _requestAllFilesAccess() async {
    try {
      await _serverStorageService.requestAllFilesAccess();
    } catch (_) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Unable to open storage permission settings.';
        });
      }
    }
  }

  Future<void> _pickDirectory() async {
    final String? selectedPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select server storage directory',
    );
    if (selectedPath == null || selectedPath.trim().isEmpty) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _customPathController.text = selectedPath;
      _resolvedDirectoryPath = selectedPath;
      _statusMessage = null;
    });
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isSaving = true;
      _statusMessage = null;
    });

    final String customPath = _customPathController.text.trim();
    try {
      final ServerDirectorySettings settings = ServerDirectorySettings(
        useDefaultDirectory: _useDefaultDirectory,
        customDirectoryPath: _useDefaultDirectory ? '' : customPath,
      );
      await _settingsRepository.saveServerDirectorySettings(settings);

      final String resolvedDirectoryPath = await _serverStorageService
          .resolveBaseDirectoryPath();

      if (!mounted) return;

      setState(() {
        _resolvedDirectoryPath = resolvedDirectoryPath;
        _statusMessage = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Server directory set to $resolvedDirectoryPath'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
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

  void _setDefaultDirectory(bool value) {
    setState(() {
      _useDefaultDirectory = value;
      if (value) {
        _resolvedDirectoryPath = ServerDirectorySettings.defaultDirectoryPath;
        _statusMessage = null;
      } else if (_customPathController.text.trim().isNotEmpty) {
        _resolvedDirectoryPath = _customPathController.text.trim();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
                // ---- Storage permission card ----
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _hasAllFilesAccess
                            ? colors.outlineVariant
                            : colors.error.withOpacity(0.5),
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              _hasAllFilesAccess
                                  ? Icons.check_circle_rounded
                                  : Icons.warning_amber_rounded,
                              color: _hasAllFilesAccess
                                  ? colors.primary
                                  : colors.error,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Storage Access',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _hasAllFilesAccess
                              ? 'All files access is granted. Bifrost can read and write server files directly.'
                              : 'Bifrost needs "All files access" to manage server files. '
                                  'Tap the button below to grant it in system settings.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        if (!_hasAllFilesAccess) ...<Widget>[
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _requestAllFilesAccess,
                            icon: const Icon(Icons.settings_rounded),
                            label: const Text('Grant All Files Access'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Server directory card ----
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
                          'Server Directory',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'All server files are stored in this folder. '
                          'Each server gets its own subdirectory.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Use default storage'),
                          subtitle: const Text(
                            ServerDirectorySettings.defaultDirectoryPath,
                          ),
                          value: _useDefaultDirectory,
                          onChanged: _setDefaultDirectory,
                        ),
                        if (!_useDefaultDirectory) ...<Widget>[
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: TextField(
                                  controller: _customPathController,
                                  decoration: const InputDecoration(
                                    labelText: 'Custom directory path',
                                    hintText: '/storage/emulated/0/MyServers',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (String value) {
                                    setState(() {
                                      _resolvedDirectoryPath =
                                          value.trim().isEmpty
                                              ? ServerDirectorySettings
                                                    .defaultDirectoryPath
                                              : value.trim();
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 56,
                                child: FilledButton.tonal(
                                  onPressed: _pickDirectory,
                                  style: FilledButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.folder_open_rounded,
                                  ),
                                ),
                              ),
                            ],
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
