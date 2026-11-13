import 'dart:async';

/// One move in flight; renewed after its response with no periodic busy polling.
/// Stop follows the last pending move. Steer retains only the latest direction.
class PtzMotion {
  final Future<void> Function(int, int, int) move;
  final Future<void> Function() halt;
  final void Function(Object) onError;
  final Duration interval, holdLimit;
  Timer? _timer, _limit;
  Future<void>? _inFlight, _stopping;
  int _generation = 0, _steerGeneration = 0;
  int _x = 0, _y = 0, _zoom = 0;
  bool _closed = false, _holding = false;
  PtzMotion({
    required this.move,
    required this.halt,
    required this.onError,
    this.interval = const Duration(milliseconds: 400),
    this.holdLimit = const Duration(seconds: 5),
  });

  void start(int x, int y, int zoom) {
    if (_closed || _stopping != null) return;
    _x = x;
    _y = y;
    _zoom = zoom;
    if (_holding) return;
    _holding = true;
    final generation = ++_generation;
    _limit = Timer(holdLimit, () => unawaited(stop()));
    _pulse(generation);
  }

  void _pulse(int generation) {
    if (_closed ||
        !_holding ||
        generation != _generation ||
        _inFlight != null) {
      return;
    }
    final watch = Stopwatch()..start();
    var failed = false;
    final work = Future<void>.sync(() => move(_x, _y, _zoom)).catchError((
      Object error,
    ) {
      failed = true;
      onError(error);
      scheduleMicrotask(() => unawaited(stop()));
    });
    _inFlight = work;
    unawaited(
      work.whenComplete(() {
        if (identical(_inFlight, work)) _inFlight = null;
        if (!failed && !_closed && _holding && generation == _generation) {
          final remaining = interval - watch.elapsed;
          _timer = Timer(
            remaining.isNegative ? Duration.zero : remaining,
            () => _pulse(generation),
          );
        }
      }),
    );
  }

  /// Joystick updates replace direction, never enqueue intermediate positions.
  void steer(int x, int y) {
    if (_closed) return;
    final ticket = ++_steerGeneration;
    if (x == 0 && y == 0) {
      unawaited(stop());
      return;
    }
    final stopping = _stopping;
    if (stopping != null) {
      unawaited(
        stopping.then((_) {
          if (!_closed && ticket == _steerGeneration) start(x, y, 0);
        }),
      );
    } else {
      start(x, y, 0);
    }
  }

  Future<void> stop({bool force = false}) {
    ++_steerGeneration;
    if (_stopping != null) return _stopping!;
    final moving = _holding || _inFlight != null;
    _holding = false;
    ++_generation;
    _timer?.cancel();
    _timer = null;
    _limit?.cancel();
    _limit = null;
    if (!moving && !force) return Future.value();
    final pending = _inFlight;
    final stopping = (() async {
      await pending;
      try {
        await halt();
      } catch (error) {
        ++_steerGeneration;
        onError(error);
      }
    })();
    // Publish the completion that clears _stopping before a queued steer runs.
    _stopping = stopping.whenComplete(() => _stopping = null);
    return _stopping!;
  }

  Future<void> close() async {
    _closed = true;
    await stop();
  }
}
