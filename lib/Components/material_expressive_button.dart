import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

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
    this.siblingDirection = 0.0,
    this.onPressStateChanged,
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
  final double siblingDirection;
  final ValueChanged<bool>? onPressStateChanged;

  @override
  State<MaterialExpressiveButton> createState() =>
      _MaterialExpressiveButtonState();
}

class _MaterialExpressiveButtonState extends State<MaterialExpressiveButton>
    with TickerProviderStateMixin {
  late final AnimationController _pressController;
  late final AnimationController _activeController;
  late final AnimationController _siblingController;

  bool _isPressed = false;
  DateTime? _pressStartTime;

  // Material 3 Expressive spring physics parameters:
  // _pressSpring: Stiff and highly damped for immediate physical response on touch down
  static final SpringDescription _pressSpring = SpringDescription.withDampingRatio(
    mass: 1.0,
    stiffness: 500.0,
    ratio: 0.9,
  );

  // _releaseSpring: Underdamped for a playful elastic bounce on touch release
  static final SpringDescription _releaseSpring = SpringDescription.withDampingRatio(
    mass: 1.0,
    stiffness: 350.0,
    ratio: 0.55,
  );

  // _activeSpring: Smooth transition when toggling active state (e.g. server status changes)
  static final SpringDescription _activeSpring = SpringDescription.withDampingRatio(
    mass: 1.0,
    stiffness: 300.0,
    ratio: 0.6,
  );

  // _siblingSpring: Smooth physics spring for adjacent button push/pull shifting
  static final SpringDescription _siblingSpring = SpringDescription.withDampingRatio(
    mass: 1.0,
    stiffness: 300.0,
    ratio: 0.6,
  );

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController.unbounded(
      vsync: this,
      value: 0.0,
    )..addListener(_update);

    _activeController = AnimationController.unbounded(
      vsync: this,
      value: widget.isActive ? 1.0 : 0.0,
    )..addListener(_update);

    _siblingController = AnimationController.unbounded(
      vsync: this,
      value: widget.siblingDirection,
    )..addListener(_update);
  }

  void _update() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(MaterialExpressiveButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _animateActiveTo(widget.isActive ? 1.0 : 0.0);
    }
    if (oldWidget.siblingDirection != widget.siblingDirection) {
      debugPrint('MaterialExpressiveButton: siblingDirection changed from ${oldWidget.siblingDirection} to ${widget.siblingDirection}');
      _animateSiblingTo(widget.siblingDirection);
    }
    if (oldWidget.onPressed != null && widget.onPressed == null) {
      if (_isPressed) {
        _releasePress();
      }
    }
  }

  @override
  void dispose() {
    _pressController.dispose();
    _activeController.dispose();
    _siblingController.dispose();
    super.dispose();
  }

  void _animatePressTo(double target) {
    final spring = target == 1.0 ? _pressSpring : _releaseSpring;
    final simulation = SpringSimulation(
      spring,
      _pressController.value,
      target,
      0.0,
    );
    _pressController.animateWith(simulation);
  }

  void _animateActiveTo(double target) {
    final simulation = SpringSimulation(
      _activeSpring,
      _activeController.value,
      target,
      0.0,
    );
    _activeController.animateWith(simulation);
  }

  void _animateSiblingTo(double target) {
    debugPrint('MaterialExpressiveButton: Animating sibling to $target');
    final simulation = SpringSimulation(
      _siblingSpring,
      _siblingController.value,
      target,
      0.0,
    );
    _siblingController.animateWith(simulation);
  }

  void _handleTapDown(TapDownDetails details) {
    _pressStartTime = DateTime.now();
    setState(() {
      _isPressed = true;
    });
    widget.onPressStateChanged?.call(true);
    _animatePressTo(1.0);
  }

  void _handleTapUp(TapUpDetails details) {
    _releasePress();
  }

  void _handleTapCancel() {
    _releasePress();
  }

  void _releasePress() {
    setState(() {
      _isPressed = false;
    });

    if (_pressStartTime == null) {
      widget.onPressStateChanged?.call(false);
      _animatePressTo(0.0);
      return;
    }

    final duration = DateTime.now().difference(_pressStartTime!);
    const minPressDuration = Duration(milliseconds: 300);

    if (duration < minPressDuration) {
      final delay = minPressDuration - duration;
      Future.delayed(delay, () {
        if (mounted) {
          widget.onPressStateChanged?.call(false);
          if (!_isPressed) {
            _animatePressTo(0.0);
          }
        }
      });
    } else {
      widget.onPressStateChanged?.call(false);
      _animatePressTo(0.0);
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

    const Duration colorAnimationDuration = Duration(milliseconds: 200);
    const Curve colorAnimationCurve = Curves.easeOutCubic;

    // Scale calculation: idle = 1.0, pressed = 0.94, sibling pressed = 0.96
    final double scale = 1.0 - (_pressController.value * 0.06) - (_siblingController.value.abs() * 0.04);

    // Border radius calculation: idle = 12.0, active/pressed = 28.0 (pill shape)
    // Sibling press adds a subtle roundness increase (up to 18.0)
    final double radiusProgress = (_activeController.value + _pressController.value).clamp(0.0, 1.0);
    final double radius = 12.0 + (radiusProgress * 16.0) + (_siblingController.value.abs() * 6.0);

    // Horizontal translation: shift away from pressed sibling (12 pixels max)
    final double translationX = _siblingController.value * 12.0;

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

    Widget result = Transform.translate(
      offset: Offset(translationX, 0.0),
      child: Transform.scale(
        scale: scale,
        child: AnimatedContainer(
          duration: colorAnimationDuration,
          curve: colorAnimationCurve,
          width: widget.expanded ? double.infinity : null,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: currentBgColor,
            borderRadius: BorderRadius.circular(radius.clamp(0.0, double.infinity)),
          ),
          child: TweenAnimationBuilder<Color?>(
            duration: colorAnimationDuration,
            curve: colorAnimationCurve,
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
        ),
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
