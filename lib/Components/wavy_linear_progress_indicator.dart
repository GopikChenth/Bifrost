import 'dart:math' as math;
import 'package:flutter/material.dart';

class WavyLinearProgressIndicator extends StatefulWidget {
  const WavyLinearProgressIndicator({
    super.key,
    this.value,
    this.color,
    this.backgroundColor,
    this.minHeight = 8.0,
    this.waveHeight = 6.0,
    this.waveLength = 24.0,
    this.gapSize = 10.0,
  });

  final double? value;
  final Color? color;
  final Color? backgroundColor;
  final double minHeight;
  final double waveHeight;
  final double waveLength;
  final double gapSize;

  @override
  State<WavyLinearProgressIndicator> createState() =>
      _WavyLinearProgressIndicatorState();
}

class _WavyLinearProgressIndicatorState extends State<WavyLinearProgressIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _waveController;
  late final AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    final double initialValue = (widget.value ?? 0.0).clamp(0.0, 1.0);
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      value: initialValue,
    );
  }

  @override
  void didUpdateWidget(WavyLinearProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final double targetValue = (widget.value ?? 0.0).clamp(0.0, 1.0);
      _progressController.animateTo(
        targetValue,
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color activeColor = widget.color ?? theme.colorScheme.primary;
    final Color inactiveColor =
        widget.backgroundColor ?? theme.colorScheme.surfaceContainerHighest;

    final double totalHeight = widget.minHeight + widget.waveHeight;

    return SizedBox(
      height: totalHeight,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[_waveController, _progressController]),
        builder: (BuildContext context, Widget? child) {
          final double phase = _waveController.value * 2 * math.pi;
          final double progressValue = _progressController.value;

          return CustomPaint(
            painter: _WavyProgressPainter(
              progress: progressValue,
              phase: phase,
              color: activeColor,
              backgroundColor: inactiveColor,
              strokeWidth: widget.minHeight,
              waveHeight: widget.waveHeight,
              waveLength: widget.waveLength,
              gapSize: widget.gapSize,
            ),
          );
        },
      ),
    );
  }
}

class _WavyProgressPainter extends CustomPainter {
  const _WavyProgressPainter({
    required this.progress,
    required this.phase,
    required this.color,
    required this.backgroundColor,
    required this.strokeWidth,
    required this.waveHeight,
    required this.waveLength,
    required this.gapSize,
  });

  final double? progress;
  final double phase;
  final Color color;
  final Color backgroundColor;
  final double strokeWidth;
  final double waveHeight;
  final double waveLength;
  final double gapSize;

  @override
  void paint(Canvas canvas, Size size) {
    final double yCenter = size.height / 2;
    final double width = size.width;
    final double amplitude = waveHeight / 2;

    if (progress != null) {
      // Determinate mode
      final double startX = strokeWidth / 2;
      final double endX = width - strokeWidth / 2;
      final double totalLength = endX - startX;
      final double activeLength = startX + totalLength * progress!;

      // 1. Draw Background Track (inactive/not progress section with gap)
      final double inactiveStartX = progress! == 0.0
          ? startX
          : (activeLength + gapSize).clamp(startX, endX);

      if (inactiveStartX < endX) {
        final Paint bgPaint = Paint()
          ..color = backgroundColor
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

        canvas.drawLine(
          Offset(inactiveStartX, yCenter),
          Offset(endX, yCenter),
          bgPaint,
        );
      }

      // 2. Draw Active Track (wavy line)
      if (progress! > 0.0) {
        final Paint activePaint = Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

        final Path path = Path();
        path.moveTo(startX, yCenter);

        for (double x = startX; x <= activeLength; x += 1.0) {
          double localAmplitude = amplitude;

          // Soft transition near the ends of the active segment
          final double distFromStart = x - startX;
          final double distFromEnd = activeLength - x;
          const double transitionZone = 16.0;

          if (distFromStart < transitionZone) {
            localAmplitude *= (distFromStart / transitionZone);
          } else if (distFromEnd < transitionZone) {
            localAmplitude *= (distFromEnd / transitionZone);
          }

          final double y = yCenter +
              localAmplitude *
                  math.sin((2 * math.pi * x / waveLength) - phase);
          path.lineTo(x, y);
        }

        canvas.drawPath(path, activePaint);
      }
    } else {
      // Indeterminate mode: draw a sliding wavy segment and background track segments with gaps
      final double segmentLength = (width * 0.35).clamp(40.0, 150.0);
      final double normalizedPos = (phase / (2 * math.pi));
      final double totalTravel = width + segmentLength;
      final double currentCenter =
          (totalTravel * normalizedPos) - segmentLength / 2;

      final double startX = (currentCenter - segmentLength / 2)
          .clamp(strokeWidth / 2, width - strokeWidth / 2);
      final double endX = (currentCenter + segmentLength / 2)
          .clamp(strokeWidth / 2, width - strokeWidth / 2);

      final double trackStartX = strokeWidth / 2;
      final double trackEndX = width - strokeWidth / 2;

      final Paint bgPaint = Paint()
        ..color = backgroundColor
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      // Draw left track part (before the sliding wave, with a gap)
      final double leftTrackEndX = (startX - gapSize).clamp(trackStartX, trackEndX);
      if (leftTrackEndX > trackStartX) {
        canvas.drawLine(
          Offset(trackStartX, yCenter),
          Offset(leftTrackEndX, yCenter),
          bgPaint,
        );
      }

      // Draw right track part (after the sliding wave, with a gap)
      final double rightTrackStartX = (endX + gapSize).clamp(trackStartX, trackEndX);
      if (rightTrackStartX < trackEndX) {
        canvas.drawLine(
          Offset(rightTrackStartX, yCenter),
          Offset(trackEndX, yCenter),
          bgPaint,
        );
      }

      // Draw the active sliding wavy track
      if (endX - startX > 1.0) {
        final Paint activePaint = Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

        final Path path = Path();
        path.moveTo(startX, yCenter);

        for (double x = startX; x <= endX; x += 1.0) {
          double localAmplitude = amplitude;

          // Soft amplitude transition at segment boundaries
          final double distFromStart = x - startX;
          final double distFromEnd = endX - x;
          const double transitionZone = 12.0;

          if (distFromStart < transitionZone) {
            localAmplitude *= (distFromStart / transitionZone);
          } else if (distFromEnd < transitionZone) {
            localAmplitude *= (distFromEnd / transitionZone);
          }

          final double y = yCenter +
              localAmplitude *
                  math.sin((2 * math.pi * x / waveLength) - (phase * 1.5));
          path.lineTo(x, y);
        }

        canvas.drawPath(path, activePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WavyProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.phase != phase ||
        oldDelegate.color != color ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.waveHeight != waveHeight ||
        oldDelegate.waveLength != waveLength ||
        oldDelegate.gapSize != gapSize;
  }
}
