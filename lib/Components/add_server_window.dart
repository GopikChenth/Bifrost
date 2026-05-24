import 'dart:math' as math;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:bifrost/Services/paper_jar_service.dart';
import 'package:bifrost/Services/vanilla_jar_service.dart';
import 'package:bifrost/Components/bifrost_bounce.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AddServerResult {
  const AddServerResult({
    required this.name,
    required this.version,
    required this.serverType,
    required this.memoryLabel,
  });

  final String name;
  final String version;
  final String serverType;
  final String memoryLabel;
}

class AddServerWindow extends StatefulWidget {
  const AddServerWindow({super.key});

  static double? cachedTotalRamMb;
  static bool? cachedIsRamFallbackUsed;

  static String formatMbAsGb(double mb) {
    final double gb = mb / 1024;
    if (gb == gb.roundToDouble()) {
      return '${gb.toInt()} GB';
    }
    return '${gb.toStringAsFixed(1)} GB';
  }

  static Future<void> preloadDeviceInfo() async {
    if (cachedTotalRamMb != null) {
      return;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      cachedTotalRamMb = 4096;
      cachedIsRamFallbackUsed = true;
      return;
    }
    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      final double safeTotal = math.max(
        (androidInfo.physicalRamSize > 0 ? androidInfo.physicalRamSize : 4096).toDouble(),
        1024,
      );
      cachedTotalRamMb = safeTotal;
      cachedIsRamFallbackUsed = androidInfo.physicalRamSize <= 0;
    } catch (_) {
      cachedTotalRamMb = 4096;
      cachedIsRamFallbackUsed = true;
    }
  }

  @override
  State<AddServerWindow> createState() => _AddServerWindowState();
}

class _AddServerWindowState extends State<AddServerWindow> {
  static const List<String> _serverTypes = <String>[
    'Vanilla',
    'Paper',
  ];

  final OfficialServerDownloadService _downloadService =
      const OfficialServerDownloadService();
  final PaperJarService _paperJarService = const PaperJarService();
  final TextEditingController _nameController = TextEditingController();
  List<String> _availableVersions = <String>[];
  String? _selectedVersion;
  String? _selectedType;
  double _totalRamMb = 4096;
  double _allocatedRamMb = 2048;
  bool _loadingRam = true;
  bool _loadingVersions = false;
  bool _isRamFallbackUsed = false;
  String? _nameErrorText;
  String? _typeErrorText;
  String? _versionErrorText;
  String? _versionStatusText;

  @override
  void initState() {
    super.initState();
    if (AddServerWindow.cachedTotalRamMb != null) {
      _totalRamMb = AddServerWindow.cachedTotalRamMb!;
      _allocatedRamMb = _snapToStep(math.min(2048, _totalRamMb));
      _loadingRam = false;
      _isRamFallbackUsed = AddServerWindow.cachedIsRamFallbackUsed!;
    } else if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      _totalRamMb = 4096;
      _allocatedRamMb = 2048;
      _loadingRam = false;
      _isRamFallbackUsed = true;
      AddServerWindow.cachedTotalRamMb = 4096;
      AddServerWindow.cachedIsRamFallbackUsed = true;
    } else {
      _loadDeviceRam();
    }
  }



  Future<int?> _readRamMbFromDeviceInfo() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }

    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
    if (androidInfo.physicalRamSize > 0) {
      return androidInfo.physicalRamSize;
    }

    return null;
  }

  Future<void> _loadDeviceRam() async {
    try {
      int? physicalMemoryMb;
      try {
        physicalMemoryMb = await _readRamMbFromDeviceInfo();
      } catch (_) {
        physicalMemoryMb = null;
      }

      final bool invalidRam = physicalMemoryMb == null || physicalMemoryMb <= 0;
      final double safeTotal = math.max(
        (physicalMemoryMb ?? 4096).toDouble(),
        1024,
      );
      AddServerWindow.cachedTotalRamMb = safeTotal;
      AddServerWindow.cachedIsRamFallbackUsed = invalidRam;
      if (mounted) {
        setState(() {
          _totalRamMb = safeTotal;
          _allocatedRamMb = _snapToStep(math.min(2048, _totalRamMb));
          _loadingRam = false;
          _isRamFallbackUsed = invalidRam;
        });
      }
    } catch (_) {
      AddServerWindow.cachedTotalRamMb = 4096;
      AddServerWindow.cachedIsRamFallbackUsed = true;
      if (mounted) {
        setState(() {
          _totalRamMb = 4096;
          _allocatedRamMb = 2048;
          _loadingRam = false;
          _isRamFallbackUsed = true;
        });
      }
    }
  }

  /// Snaps a value to the nearest 512 MB (0.5 GB) step.
  double _snapToStep(double mb) {
    return (mb / _stepMb).round() * _stepMb;
  }

  static const double _stepMb = 512;

  String _formatMbAsGb(double mb) {
    return AddServerWindow.formatMbAsGb(mb);
  }

  void _closeDialog() {
    Navigator.of(context).pop();
  }

  Future<void> _loadVersionsForType(
    String serverType, {
    bool forceRefresh = false,
  }) async {
    setState(() {
      _selectedType = serverType;
      _selectedVersion = null;
      _availableVersions = <String>[];
      _loadingVersions = true;
      _typeErrorText = null;
      _versionErrorText = null;
      _versionStatusText = null;
    });

    try {
      final List<String> versions = serverType.toLowerCase() == 'paper'
          ? await _paperJarService.getAvailableVersions()
          : await _downloadService.getAvailableVersions(
              serverType,
              forceRefresh: forceRefresh,
            );

      if (!mounted) {
        return;
      }

      setState(() {
        _availableVersions = versions;
        _selectedVersion = versions.isNotEmpty ? versions.first : null;
        _versionStatusText = versions.isEmpty
            ? 'No downloadable versions are available for $serverType yet.'
            : null;
      });
    } on OfficialServerDownloadException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _versionStatusText = error.message;
      });
    } on PaperJarDownloadException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _versionStatusText = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _versionStatusText = 'Unable to load versions for $serverType.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingVersions = false;
        });
      }
    }
  }

  void _submitServer() {
    FocusScope.of(context).unfocus();
    final String trimmedName = _nameController.text.trim();
    final String? selectedType = _selectedType;
    final String? selectedVersion = _selectedVersion;

    var hasError = false;
    if (trimmedName.isEmpty) {
      _nameErrorText = 'Server name is required';
      hasError = true;
    }

    if (selectedType == null) {
      _typeErrorText = 'Select a server type first';
      hasError = true;
    }

    if (selectedVersion == null) {
      _versionErrorText = 'Select an available version';
      hasError = true;
    }

    if (hasError) {
      setState(() {});
      return;
    }

    setState(() {
      _nameErrorText = null;
      _typeErrorText = null;
      _versionErrorText = null;
    });

    Navigator.of(context).pop(
      AddServerResult(
        name: trimmedName,
        version: selectedVersion!,
        serverType: selectedType!,
        memoryLabel: _formatMbAsGb(_allocatedRamMb),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double sliderMin = _stepMb;
    final double sliderMax =
        ((_totalRamMb / _stepMb).ceil() * _stepMb).clamp(_stepMb, double.infinity);
    final int divisions =
        ((sliderMax - sliderMin) / _stepMb).round().clamp(1, 256);

    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Material(
      color: colors.surfaceContainerHigh,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      type: MaterialType.card,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Add Server',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextField(
                      controller: _nameController,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Server Name',
                        hintText: 'Friends SMP',
                      ).copyWith(errorText: _nameErrorText),
                      onSubmitted: (_) => _submitServer(),
                      onChanged: (_) {
                        if (_nameErrorText != null) {
                          setState(() {
                            _nameErrorText = null;
                          });
                        }
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedType,
                      decoration: InputDecoration(
                        labelText: 'Server Type',
                        errorText: _typeErrorText,
                      ),
                      items: _serverTypes
                          .map(
                            (String type) => DropdownMenuItem<String>(
                              value: type,
                              child: Text(type),
                            ),
                          )
                          .toList(),
                      onChanged: (String? value) {
                        if (value != null) {
                          _loadVersionsForType(value);
                        }
                      },
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      DropdownButtonFormField<String>(
                        initialValue: _selectedVersion,
                        decoration: const InputDecoration(
                          labelText: 'Version',
                        ).copyWith(errorText: _versionErrorText),
                        items: _availableVersions
                            .map(
                              (String version) => DropdownMenuItem<String>(
                                value: version,
                                child: Text(version),
                              ),
                            )
                            .toList(),
                        onChanged: _loadingVersions || _availableVersions.isEmpty
                            ? null
                            : (String? value) {
                                if (value != null) {
                                  setState(() {
                                    _selectedVersion = value;
                                    _versionErrorText = null;
                                  });
                                }
                              },
                      ),
                      if (_loadingVersions) ...<Widget>[
                        const SizedBox(height: 8),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ],
                      if (_versionStatusText != null) ...<Widget>[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _versionStatusText!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                      if (_selectedType != null) ...<Widget>[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _loadingVersions
                                ? null
                                : () {
                                    _loadVersionsForType(
                                      _selectedType!,
                                      forceRefresh: true,
                                    );
                                  },
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Refresh versions'),
                          ),
                        ),
                      ],
                      if (_selectedType == null) ...<Widget>[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Select a server type to load available versions.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _loadingRam
                              ? 'Detecting device RAM...'
                              : 'Device RAM: ${_formatMbAsGb(_totalRamMb)}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      if (_isRamFallbackUsed && !_loadingRam) ...<Widget>[
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Using fallback RAM value',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Allocated: ${_formatMbAsGb(_allocatedRamMb)}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Slider(
                        min: sliderMin,
                        max: sliderMax,
                        divisions: divisions,
                        value: _allocatedRamMb.clamp(sliderMin, sliderMax),
                        label: _formatMbAsGb(_allocatedRamMb),
                        onChanged: _loadingRam
                            ? null
                            : (double value) {
                                setState(() {
                                  _allocatedRamMb = value;
                                });
                              },
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${_formatMbAsGb(sliderMin)} \u2013 ${_formatMbAsGb(sliderMax)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      BifrostBounce(
                        child: TextButton(onPressed: _closeDialog, child: const Text('Close')),
                      ),
                      const SizedBox(width: 8),
                      BifrostBounce(
                        child: FilledButton(onPressed: _submitServer, child: const Text('Add')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
  }
}

class AddServerFlightShuttleMock extends StatelessWidget {
  const AddServerFlightShuttleMock({super.key});

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double targetWidth = math.min(420.0, screenWidth - 40.0);

    return OverflowBox(
      alignment: Alignment.topCenter,
      minWidth: targetWidth,
      maxWidth: targetWidth,
      minHeight: 0,
      maxHeight: 600,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Add Server',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            // Server Name mock
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: TextField(
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Server Name',
                  hintText: 'Friends SMP',
                ),
              ),
            ),
            // Server Type mock
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: DropdownButtonFormField<String>(
                initialValue: null,
                decoration: const InputDecoration(
                  labelText: 'Server Type',
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(value: 'Vanilla', child: Text('Vanilla')),
                  DropdownMenuItem<String>(value: 'Paper', child: Text('Paper')),
                ],
                onChanged: (_) {},
              ),
            ),
            // Version mock
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                DropdownButtonFormField<String>(
                  initialValue: null,
                  decoration: const InputDecoration(
                    labelText: 'Version',
                  ),
                  items: const <DropdownMenuItem<String>>[],
                  onChanged: null,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Select a server type to load available versions.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
            // RAM Mock
            Builder(
              builder: (BuildContext context) {
                final double totalRamMb = AddServerWindow.cachedTotalRamMb ?? 4096.0;
                final bool isRamFallbackUsed = AddServerWindow.cachedIsRamFallbackUsed ??
                    (kIsWeb || defaultTargetPlatform != TargetPlatform.android);
                final double sliderMin = 512.0;
                final double sliderMax =
                    ((totalRamMb / 512.0).ceil() * 512.0).clamp(512.0, double.infinity);
                final double allocatedRamMb = math.min(2048.0, totalRamMb);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Device RAM: ${AddServerWindow.formatMbAsGb(totalRamMb)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    if (isRamFallbackUsed) ...<Widget>[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Using fallback RAM value',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Allocated: ${AddServerWindow.formatMbAsGb(allocatedRamMb)}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Slider(
                      min: sliderMin,
                      max: sliderMax,
                      value: allocatedRamMb,
                      onChanged: (_) {},
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${AddServerWindow.formatMbAsGb(sliderMin)} \u2013 ${AddServerWindow.formatMbAsGb(sliderMax)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
            // Buttons Mock
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                BifrostBounce(
                  child: TextButton(
                    onPressed: () {},
                    child: const Text('Close'),
                  ),
                ),
                const SizedBox(width: 8),
                BifrostBounce(
                  child: FilledButton(
                    onPressed: () {},
                    child: const Text('Add'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
