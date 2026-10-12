import 'package:flutter/material.dart';

/// Animated "AI is looking" overlay — a luminous scanline sweeps
/// up and down over the child (a photo) while the vision model
/// judges it. Drive with [active].
class ScanOverlay extends StatefulWidget {
  const ScanOverlay({
    super.key,
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  State<ScanOverlay> createState() => _ScanOverlayState();
}

class _ScanOverlayState extends State<ScanOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _sweep.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(ScanOverlay old) {
    super.didUpdateWidget(old);
    if (widget.active && !_sweep.isAnimating) {
      _sweep.repeat(reverse: true);
    } else if (!widget.active && _sweep.isAnimating) {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: _sweep,
        child: widget.child,
        builder: (context, child) {
          final h = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 300.0;
          return Stack(
            fit: StackFit.expand,
            children: [
              child!,
              // Soft analyzing tint.
              Container(
                color: Colors.tealAccent.withValues(alpha: 0.08),
              ),
              // The sweeping scanline with a glow trail.
              Positioned(
                left: 0,
                right: 0,
                top: _sweep.value * h,
                child: IgnorePointer(
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.tealAccent
                              .withValues(alpha: 0.9),
                          Colors.transparent,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.tealAccent
                              .withValues(alpha: 0.5),
                          blurRadius: 18,
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
