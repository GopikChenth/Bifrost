import 'package:flutter/material.dart';

class MaterialExpressiveButton extends StatefulWidget {
  const MaterialExpressiveButton({
    super.key,
    required this.icon,
    this.label,
    this.onPressed,
    this.tooltip,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.pressedBackgroundColor,
    required this.pressedForegroundColor,
    this.expanded = false,
    this.isActive = false,
  });

  final Widget icon;
  final Widget? label;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color pressedBackgroundColor;
  final Color pressedForegroundColor;
  final bool expanded;
  final bool isActive;

  @override
  State<MaterialExpressiveButton> createState() =>
      _MaterialExpressiveButtonState();
}

class _MaterialExpressiveButtonState extends State<MaterialExpressiveButton> {
  bool _isPressed = false;
  DateTime? _pressStartTime;

  @override
  void didUpdateWidget(MaterialExpressiveButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onPressed != null && widget.onPressed == null) {
      if (_isPressed) {
        _releasePress();
      }
    }
  }

  void _handleTapDown(TapDownDetails details) {
    _pressStartTime = DateTime.now();
    setState(() {
      _isPressed = true;
    });
  }

  void _handleTapUp(TapUpDetails details) {
    _releasePress();
  }

  void _handleTapCancel() {
    _releasePress();
  }

  void _releasePress() {
    if (_pressStartTime == null) {
      setState(() {
        _isPressed = false;
      });
      return;
    }

    final duration = DateTime.now().difference(_pressStartTime!);
    const minPressDuration = Duration(milliseconds: 400);

    if (duration < minPressDuration) {
      final delay = minPressDuration - duration;
      Future.delayed(delay, () {
        if (mounted) {
          setState(() {
            _isPressed = false;
          });
        }
      });
    } else {
      setState(() {
        _isPressed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isEnabled = widget.onPressed != null;

    final Color currentBgColor = !isEnabled
        ? colors.onSurface.withValues(alpha: 0.12)
        : (_isPressed ? widget.pressedBackgroundColor : widget.backgroundColor);

    final Color currentFgColor = !isEnabled
        ? colors.onSurface.withValues(alpha: 0.38)
        : (_isPressed ? widget.pressedForegroundColor : widget.foregroundColor);

    const Duration animationDuration = Duration(milliseconds: 300);
    const Curve animationCurve = Curves.easeInOutCubic;

    final Widget buttonContent = Row(
      mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        widget.icon,
        if (widget.label != null) ...<Widget>[
          const SizedBox(width: 8),
          widget.label!,
        ],
      ],
    );

    Widget result = AnimatedContainer(
      duration: animationDuration,
      curve: animationCurve,
      width: widget.expanded ? double.infinity : null,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: currentBgColor,
        borderRadius: BorderRadius.circular((widget.isActive || _isPressed) ? 999 : 12),
      ),
      child: TweenAnimationBuilder<Color?>(
        duration: animationDuration,
        curve: animationCurve,
        tween: ColorTween(end: currentFgColor),
        builder: (BuildContext context, Color? animatedFgColor, Widget? child) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              onTapDown: isEnabled ? _handleTapDown : null,
              onTapCancel: isEnabled ? _handleTapCancel : null,
              onTapUp: isEnabled ? _handleTapUp : null,
              child: Padding(
                padding: widget.label != null
                    ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
                    : const EdgeInsets.all(10),
                child: IconTheme(
                  data: IconThemeData(
                     color: animatedFgColor,
                     size: widget.label != null ? 18 : 20,
                  ),
                  child: DefaultTextStyle(
                    style: theme.textTheme.labelLarge!.copyWith(
                          color: animatedFgColor,
                          fontWeight: FontWeight.w600,
                        ),
                    child: buttonContent,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    if (widget.tooltip != null) {
      result = Tooltip(
        message: widget.tooltip!,
        child: result,
      );
    }

    return result;
  }
}
