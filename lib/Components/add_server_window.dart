import 'dart:math' as math;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:bifrost/Service/official_server_download_service.dart';
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

  @override
  State<AddServerWindow> createState() => _AddServerWindowState();
}

class _AddServerWindowState extends State<AddServerWindow> {
  static const List<String> _serverTypes = <String>[
    'Paper',
    'Vanilla',
    'Forge',
  ];

  final OfficialServerDownloadService _downloadService =
      const OfficialServerDownloadService();
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
    _loadDeviceRam();
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
      setState(() {
        _totalRamMb = safeTotal;
        _allocatedRamMb = math.min(2048, _totalRamMb).toDouble();
        _loadingRam = false;
        _isRamFallbackUsed = invalidRam;
      });
    } catch (_) {
      setState(() {
        _totalRamMb = 4096;
        _allocatedRamMb = 2048;
        _loadingRam = false;
        _isRamFallbackUsed = true;
      });
    }
  }

  String _formatMbAsGb(double mb) {
    final double gb = mb / 1024;
    return '${gb.toStringAsFixed(1)} GB';
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
      final List<String> versions = await _downloadService.getAvailableVersions(
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
    final double sliderMin = math.min(512, _totalRamMb);
    final double sliderMax = _totalRamMb;
    final int divisions = sliderMax > sliderMin
        ? ((sliderMax - sliderMin) / 256).floor().clamp(1, 256)
        : 1;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      title: const Text('Add Server'),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
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
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedType,
                decoration: InputDecoration(
                  labelText: 'Server Type',
                  border: const OutlineInputBorder(),
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
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedVersion,
                decoration: const InputDecoration(
                  labelText: 'Version',
                  border: OutlineInputBorder(),
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
                const SizedBox(height: 10),
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
                const SizedBox(height: 10),
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
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Select a server type to load available versions.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _loadingRam
                          ? 'Detecting device RAM...'
                          : 'Device RAM: ${_formatMbAsGb(_totalRamMb)}',
                    ),
                  ),
                  if (_isRamFallbackUsed && !_loadingRam)
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(left: 8),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              if (_isRamFallbackUsed && !_loadingRam)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Using fallback RAM value',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Allocated RAM: ${_formatMbAsGb(_allocatedRamMb)}'),
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
                  '${_allocatedRamMb.round()} MB / ${_totalRamMb.round()} MB',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: _closeDialog, child: const Text('Close')),
        FilledButton(onPressed: _submitServer, child: const Text('Add')),
      ],
    );
  }
}
