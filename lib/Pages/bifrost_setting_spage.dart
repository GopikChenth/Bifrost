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
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
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

  late final AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
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
        _entranceController.forward();
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
    _entranceController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _customPathController.dispose();
    super.dispose();
  }

  Widget _stagger(int index, Widget child) {
    final double start = (index * 0.3).clamp(0.0, 0.6);
    final double end = (start + 0.5).clamp(0.0, 1.0);
    return AnimatedBuilder(
      animation: _entranceController,
      builder: (BuildContext context, Widget? c) {
        final double t = Interval(start, end, curve: Curves.easeOutCubic)
            .transform(_entranceController.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - t)),
            child: c,
          ),
        );
      },
      child: child,
    );
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
                _stagger(
                  0,
                  Card(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _hasAllFilesAccess
                              ? colors.outlineVariant
                              : colors.error.withValues(alpha: 0.5),
                        ),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: Icon(
                                  _hasAllFilesAccess
                                      ? Icons.check_circle_rounded
                                      : Icons.warning_amber_rounded,
                                  key: ValueKey<bool>(_hasAllFilesAccess),
                                  color: _hasAllFilesAccess
                                      ? colors.primary
                                      : colors.error,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Storage Access',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
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
                ),
                const SizedBox(height: 16),

                // ---- Server directory card ----
                _stagger(
                  1,
                  Card(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.outlineVariant),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Server Directory',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
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
                          AnimatedSize(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            child: !_useDefaultDirectory
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Expanded(
                                          child: TextField(
                                            controller: _customPathController,
                                            decoration: const InputDecoration(
                                              labelText:
                                                  'Custom directory path',
                                              hintText:
                                                  '/storage/emulated/0/MyServers',
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
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
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
                                  )
                                : const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Active server root',
                                  style:
                                      theme.textTheme.labelMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SelectableText(
                                  _resolvedDirectoryPath,
                                  style:
                                      theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            child: _statusMessage != null
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: Text(
                                      _statusMessage!,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: colors.error,
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: FilledButton(
          onPressed: _isLoading || _isSaving ? null : _saveSettings,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _isSaving
                ? const SizedBox(
                    key: ValueKey<String>('saving'),
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Save Settings',
                    key: ValueKey<String>('save'),
                  ),
          ),
        ),
      ),
    );
  }
}
