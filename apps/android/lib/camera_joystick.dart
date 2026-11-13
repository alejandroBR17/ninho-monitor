import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'design.dart';

class CameraJoystick extends StatefulWidget {
  final bool enabled;
  final void Function(int x, int y) onDirection;
  final Duration holdLimit;
  final int stopRevision;
  const CameraJoystick({
    super.key,
    required this.enabled,
    required this.onDirection,
    this.holdLimit = const Duration(seconds: 5),
    this.stopRevision = 0,
  });
  @override
  State<CameraJoystick> createState() => _CameraJoystickState();
}

class _CameraJoystickState extends State<CameraJoystick> {
  static const double diameter = 192, travel = 64;
  Offset _offset = Offset.zero;
  (int, int) _last = (0, 0);
  bool _active = false, _expired = false;
  Timer? _limit;
  void _emit(int x, int y) {
    if (_last == (x, y)) return;
    _last = (x, y);
    widget.onDirection(x, y);
  }

  void _down(Offset point) {
    if (!widget.enabled || _active) return;
    _active = true;
    _expired = false;
    _limit = Timer(widget.holdLimit, () {
      if (!mounted) return;
      _expired = true;
      _emit(0, 0);
      setState(() => _offset = Offset.zero);
    });
    _update(point);
  }

  void _update(Offset point) {
    if (!widget.enabled || !_active || _expired) return;
    var delta = point - const Offset(diameter / 2, diameter / 2);
    final distance = delta.distance;
    if (distance > travel) delta = delta / distance * travel;
    setState(() => _offset = delta);
    // Dead zone avoids accidental movement and jitter around the center.
    if (distance < 16) {
      _emit(0, 0);
      return;
    }
    final sector =
        (math.atan2(-delta.dy, delta.dx) / (math.pi / 4)).round() % 8;
    const directions = [
      (1, 0),
      (1, 1),
      (0, 1),
      (-1, 1),
      (-1, 0),
      (-1, -1),
      (0, -1),
      (1, -1),
    ];
    final (x, y) = directions[sector];
    _emit(x, y);
  }

  void _reset({bool rebuild = true}) {
    _limit?.cancel();
    _limit = null;
    _active = false;
    _expired = false;
    _emit(0, 0);
    _offset = Offset.zero;
    if (rebuild && mounted) setState(() {});
  }

  @override
  void didUpdateWidget(CameraJoystick old) {
    super.didUpdateWidget(old);
    if (!widget.enabled || old.stopRevision != widget.stopRevision) {
      _reset(rebuild: false);
    }
  }

  @override
  void dispose() {
    _limit?.cancel();
    _emit(0, 0);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Joystick da câmera',
    enabled: widget.enabled,
    hint:
        'Arraste para mover. Solte ou volte ao centro para parar. A opção Setas oferece botões individuais.',
    child: Align(
      widthFactor: 1,
      heightFactor: 1,
      child: RepaintBoundary(
        child: GestureDetector(
          key: const ValueKey('camera-joystick'),
          behavior: HitTestBehavior.opaque,
          onPanDown: widget.enabled ? (d) => _down(d.localPosition) : null,
          onPanStart: widget.enabled ? (d) => _update(d.localPosition) : null,
          onPanUpdate: widget.enabled ? (d) => _update(d.localPosition) : null,
          onPanEnd: (_) => _reset(),
          onPanCancel: _reset,
          child: SizedBox.square(
            dimension: diameter,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.enabled ? inputSurface : panel,
                  ),
                ),
                const Positioned(
                  top: 8,
                  child: Icon(Icons.keyboard_arrow_up, color: textSecondary),
                ),
                const Positioned(
                  bottom: 8,
                  child: Icon(Icons.keyboard_arrow_down, color: textSecondary),
                ),
                const Positioned(
                  left: 8,
                  child: Icon(Icons.chevron_left, color: textSecondary),
                ),
                const Positioned(
                  right: 8,
                  child: Icon(Icons.chevron_right, color: textSecondary),
                ),
                Transform.translate(
                  offset: _offset,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _last != (0, 0) ? accent : textSecondary,
                    ),
                    child: const Icon(Icons.open_with, color: onAccent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
