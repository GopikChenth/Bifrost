import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A reusable component that implements a premium Material 3 container transform
/// morph transition between a closed widget and an open widget.
class BifrostContainerTransform<T> extends StatefulWidget {
  const BifrostContainerTransform({
    super.key,
    required this.closedBuilder,
    required this.openBuilder,
    this.closedColor,
    this.openColor,
    this.closedRadius = 16.0,
    this.openRadius = 28.0,
    this.closedElevation = 3.0,
    this.openElevation = 6.0,
    this.transitionDuration = const Duration(milliseconds: 300),
    this.reverseTransitionDuration = const Duration(milliseconds: 250),
    this.openMockBuilder,
    this.onClosed,
    this.openLayoutWrapper,
  });

  /// Builds the closed widget (e.g. Floating Action Button or Card).
  ///
  /// The callback [openContainer] must be called when the widget is tapped
  /// to trigger the morph transition.
  final Widget Function(BuildContext context, VoidCallback openContainer) closedBuilder;

  /// Builds the destination widget (e.g. Dialog or Screen details).
  ///
  /// The callback [closeContainer] must be called to morph back to the closed state.
  final Widget Function(BuildContext context, VoidCallback closeContainer) openBuilder;

  /// The background color of the closed container. Defaults to the theme's [primaryContainer] color.
  final Color? closedColor;

  /// The background color of the open container. Defaults to the theme's [surfaceContainerHigh] color.
  final Color? openColor;

  /// The corner radius of the closed container. Defaults to `16.0`.
  final double closedRadius;

  /// The corner radius of the open container. Defaults to `28.0`.
  final double openRadius;

  /// The elevation of the closed container. Defaults to `3.0`.
  final double closedElevation;

  /// The elevation of the open container. Defaults to `6.0`.
  final double openElevation;

  /// The transition duration when pushing the open widget. Defaults to `300ms`.
  final Duration transitionDuration;

  /// The transition duration when popping the open widget. Defaults to `250ms`.
  final Duration reverseTransitionDuration;

  /// Optional mock builder rendered inside the flight shuttle during the final morph stage.
  final WidgetBuilder? openMockBuilder;

  /// Callback called when the open container transitions back to closed state, returning any result from the pop operation.
  final void Function(T? result)? onClosed;

  /// Optional wrapper for custom positioning/layout of the open container inside the transparent route.
  final Widget Function(BuildContext context, Widget child)? openLayoutWrapper;

  @override
  State<BifrostContainerTransform<T>> createState() => _BifrostContainerTransformState<T>();
}

class _BifrostContainerTransformState<T> extends State<BifrostContainerTransform<T>> {
  final Object _heroTag = Object();

  void _openContainer() {
    Navigator.of(context).push<T>(
      BifrostContainerTransformRoute<T>(
        builder: (BuildContext context) {
          return widget.openBuilder(context, () => Navigator.of(context).pop());
        },
        heroTag: _heroTag,
        closedColor: widget.closedColor ?? Theme.of(context).colorScheme.primaryContainer,
        openColor: widget.openColor ?? Theme.of(context).colorScheme.surfaceContainerHigh,
        closedRadius: widget.closedRadius,
        openRadius: widget.openRadius,
        closedElevation: widget.closedElevation,
        openElevation: widget.openElevation,
        transitionDuration: widget.transitionDuration,
        reverseTransitionDuration: widget.reverseTransitionDuration,
        closedWidget: widget.closedBuilder(context, () {}),
        openMockBuilder: widget.openMockBuilder,
        openLayoutWrapper: widget.openLayoutWrapper,
      ),
    ).then((T? result) {
      if (widget.onClosed != null) {
        widget.onClosed!(result);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: _heroTag,
      createRectTween: (Rect? begin, Rect? end) {
        return CurvedRectTween(
          begin: begin,
          end: end,
          curve: const Cubic(0.34, 1.15, 0.64, 1.00),
        );
      },
      flightShuttleBuilder: (
        BuildContext flightContext,
        Animation<double> animation,
        HeroFlightDirection flightDirection,
        BuildContext fromHeroContext,
        BuildContext toHeroContext,
      ) {
        return BifrostFlightShuttle(
          animation: animation,
          flightDirection: flightDirection,
          closedColor: widget.closedColor ?? Theme.of(flightContext).colorScheme.primaryContainer,
          openColor: widget.openColor ?? Theme.of(flightContext).colorScheme.surfaceContainerHigh,
          closedRadius: widget.closedRadius,
          openRadius: widget.openRadius,
          closedElevation: widget.closedElevation,
          openElevation: widget.openElevation,
          closedWidget: widget.closedBuilder(flightContext, () {}),
          openMockBuilder: widget.openMockBuilder,
        );
      },
      child: widget.closedBuilder(context, _openContainer),
    );
  }
}

/// The page route that manages the transparent background and fade transitions of the container.
class BifrostContainerTransformRoute<T> extends PageRouteBuilder<T> {
  BifrostContainerTransformRoute({
    required WidgetBuilder builder,
    required Object heroTag,
    required Color closedColor,
    required Color openColor,
    required double closedRadius,
    required double openRadius,
    required double closedElevation,
    required double openElevation,
    super.transitionDuration,
    super.reverseTransitionDuration,
    required Widget closedWidget,
    required WidgetBuilder? openMockBuilder,
    Widget Function(BuildContext context, Widget child)? openLayoutWrapper,
  }) : super(
          opaque: false,
          barrierDismissible: true,
          barrierColor: Colors.black.withValues(alpha: 0.5),
          barrierLabel: 'Dismiss Transform',
          pageBuilder: (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) {
            final Widget heroWidget = Hero(
              tag: heroTag,
              createRectTween: (Rect? begin, Rect? end) {
                return CurvedRectTween(
                  begin: begin,
                  end: end,
                  curve: const Cubic(0.34, 1.15, 0.64, 1.00),
                );
              },
              flightShuttleBuilder: (
                BuildContext flightContext,
                Animation<double> animation,
                HeroFlightDirection flightDirection,
                BuildContext fromHeroContext,
                BuildContext toHeroContext,
              ) {
                return BifrostFlightShuttle(
                  animation: animation,
                  flightDirection: flightDirection,
                  closedColor: closedColor,
                  openColor: openColor,
                  closedRadius: closedRadius,
                  openRadius: openRadius,
                  closedElevation: closedElevation,
                  openElevation: openElevation,
                  closedWidget: closedWidget,
                  openMockBuilder: openMockBuilder,
                );
              },
              child: builder(context),
            );
            if (openLayoutWrapper != null) {
              return openLayoutWrapper(context, heroWidget);
            }
            return heroWidget;
          },
          transitionsBuilder: (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
            Widget child,
          ) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
        );
}

/// The widget displayed during the Hero transition flight.
class BifrostFlightShuttle extends StatelessWidget {
  const BifrostFlightShuttle({
    super.key,
    required this.animation,
    required this.flightDirection,
    required this.closedColor,
    required this.openColor,
    required this.closedRadius,
    required this.openRadius,
    required this.closedElevation,
    required this.openElevation,
    required this.closedWidget,
    required this.openMockBuilder,
  });

  final Animation<double> animation;
  final HeroFlightDirection flightDirection;
  final Color closedColor;
  final Color openColor;
  final double closedRadius;
  final double openRadius;
  final double closedElevation;
  final double openElevation;
  final Widget closedWidget;
  final WidgetBuilder? openMockBuilder;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        final bool isPush = flightDirection == HeroFlightDirection.push;
        final double t = isPush ? animation.value : 1.0 - animation.value;

        // Custom curve representing toned-down Material Expressive physics
        const Curve expressiveCurve = Cubic(0.34, 1.15, 0.64, 1.00);
        final double shapeT = expressiveCurve.transform(t);
        final double colorT = expressiveCurve.transform(t);

        // Interpolate background color
        final Color backgroundColor = Color.lerp(closedColor, openColor, colorT) ?? openColor;

        // Interpolate border radius
        final double borderRadius = closedRadius + (openRadius - closedRadius) * shapeT;

        // Interpolate elevation
        final double elevation = closedElevation + (openElevation - closedElevation) * shapeT;

        // Cross-fade the children based on size progress (animation.value)
        final double sizeVal = animation.value;
        Widget content;
        if (sizeVal < 0.45) {
          final double opacity = (1.0 - sizeVal / 0.45).clamp(0.0, 1.0);
          content = Opacity(
            opacity: opacity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: closedWidget,
            ),
          );
        } else if (sizeVal > 0.55 && openMockBuilder != null) {
          final double opacity = ((sizeVal - 0.55) / 0.45).clamp(0.0, 1.0);
          content = Opacity(
            opacity: opacity,
            child: openMockBuilder!(context),
          );
        } else {
          content = const SizedBox.shrink();
        }

        return Material(
          color: backgroundColor,
          elevation: elevation,
          borderRadius: BorderRadius.circular(borderRadius),
          clipBehavior: Clip.antiAlias,
          child: Center(
            child: content,
          ),
        );
      },
    );
  }
}

/// A custom rect tween that applies a Curve and prevents negative height/width overshoot bounds.
class CurvedRectTween extends RectTween {
  CurvedRectTween({super.begin, super.end, required this.curve});

  final Curve curve;

  @override
  Rect? lerp(double t) {
    final Rect? original = Rect.lerp(begin, end, curve.transform(t));
    if (original == null) {
      return null;
    }

    const double minSize = 16.0;
    if (original.width >= minSize && original.height >= minSize) {
      return original;
    }

    final double width = math.max(original.width, minSize);
    final double height = math.max(original.height, minSize);
    return Rect.fromCenter(
      center: original.center,
      width: width,
      height: height,
    );
  }
}
