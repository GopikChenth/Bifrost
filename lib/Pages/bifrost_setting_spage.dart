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
  bool _disableAnimations = false;
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
      final bool disableAnimations = await _settingsRepository.loadDisableAnimations();

      if (!mounted) return;

      setState(() {
        _useDefaultDirectory = settings.useDefaultDirectory;
        _customPathController.text = settings.customDirectoryPath;
        _resolvedDirectoryPath = resolvedDirectoryPath;
        _hasAllFilesAccess = hasAccess;
        _disableAnimations = disableAnimations;
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
        if (AppSettings.disableAnimations) {
          _entranceController.value = 1.0;
        } else {
          _entranceController.forward();
        }
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
      await _settingsRepository.saveDisableAnimations(_disableAnimations);

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
                _stagger(
                  0,
                  Card(
                    elevation: 1,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: colors.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // ---- Storage Access ----
                          Row(
                            children: <Widget>[
                              Icon(
                                _hasAllFilesAccess
                                    ? Icons.check_circle_rounded
                                    : Icons.warning_amber_rounded,
                                color: _hasAllFilesAccess
                                    ? colors.primary
                                    : colors.error,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Storage Access',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (_hasAllFilesAccess)
                                Text(
                                  'Granted',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colors.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              else
                                TextButton(
                                  onPressed: _requestAllFilesAccess,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text('Grant'),
                                ),
                            ],
                          ),
                          const Divider(height: 24, thickness: 0.5),

                          // ---- Server Directory ----
                          Text(
                            'Server Storage',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('Use default directory'),
                            value: _useDefaultDirectory,
                            onChanged: _setDefaultDirectory,
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            child: !_useDefaultDirectory
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                                    child: Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: SizedBox(
                                            height: 40,
                                            child: TextField(
                                              controller: _customPathController,
                                              style: theme.textTheme.bodyMedium,
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 10,
                                                ),
                                                labelText: 'Custom path',
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
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton.filledTonal(
                                          onPressed: _pickDirectory,
                                          icon: const Icon(
                                            Icons.folder_open_rounded,
                                            size: 20,
                                          ),
                                          style: IconButton.styleFrom(
                                            minimumSize: const Size(40, 40),
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Path: ',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Expanded(
                                  child: SelectableText(
                                    _resolvedDirectoryPath,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            child: _statusMessage != null
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 8),
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
                          const Divider(height: 24, thickness: 0.5),

                          // ---- Preferences ----
                          Text(
                            'Preferences',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('Disable animations'),
                            value: _disableAnimations,
                            onChanged: (bool value) {
                              setState(() {
                                _disableAnimations = value;
                              });
                            },
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
