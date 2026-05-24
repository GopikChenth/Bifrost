import 'package:bifrost/Utils/settings_repository.dart';
import 'package:flutter/material.dart';

class BifrostBounce extends StatefulWidget {
  const BifrostBounce({
    super.key,
    required this.child,
    this.scaleFactor = 0.96,
    this.duration = const Duration(milliseconds: 200),
    this.curve = Curves.easeOutBack,
    this.enabled = true,
  });

  final Widget child;
  final double scaleFactor;
  final Duration duration;
  final Curve curve;
  final bool enabled;

  @override
  State<BifrostBounce> createState() => _BifrostBounceState();
}

class _BifrostBounceState extends State<BifrostBounce> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return Listener(
      onPointerDown: (_) {
        setState(() => _scale = widget.scaleFactor);
      },
      onPointerUp: (_) {
        setState(() => _scale = 1.0);
      },
      onPointerCancel: (_) {
        setState(() => _scale = 1.0);
      },
      child: AnimatedScale(
        scale: _scale,
        duration: AppSettings.disableAnimations ? Duration.zero : widget.duration,
        curve: widget.curve,
        child: widget.child,
      ),
    );
  }
}
