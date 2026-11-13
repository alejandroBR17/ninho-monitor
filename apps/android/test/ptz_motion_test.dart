import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:jortan_viewer/ptz_motion.dart';

void main() {
  test(
    'Resposta lenta renova usando última direção sem fila intermediária',
    () async {
      final first = Completer<void>(), second = Completer<void>();
      final sent = <(int, int)>[];
      var stops = 0;
      final motion = PtzMotion(
        interval: const Duration(milliseconds: 10),
        move: (x, y, z) async {
          sent.add((x, y));
          await (sent.length == 1 ? first.future : second.future);
        },
        halt: () async {
          stops++;
        },
        onError: (_) {},
      );
      motion.steer(1, 0);
      motion.steer(-1, 0);
      motion.steer(0, 1);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(sent, [(1, 0)]);
      first.complete();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(sent, [(1, 0), (0, 1)]);
      final stop = motion.stop();
      second.complete();
      await stop;
      expect(stops, 1);
      await motion.close();
    },
  );
  for (final cancel in [false, true]) {
    test(
      'Direção após parada pendente respeita soltura: cancelar=$cancel',
      () async {
        final halt = Completer<void>();
        final sent = <(int, int)>[];
        final motion = PtzMotion(
          move: (x, y, z) async {
            sent.add((x, y));
          },
          halt: () => halt.future,
          onError: (_) {},
        );
        motion.steer(1, 0);
        motion.steer(0, 0);
        motion.steer(-1, 0);
        motion.steer(0, 1);
        if (cancel) motion.steer(0, 0);
        halt.complete();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(sent, cancel ? [(1, 0)] : [(1, 0), (0, 1)]);
        await motion.close();
      },
    );
  }
  test('Falha de parada não reinicia direção pendente', () async {
    final halt = Completer<void>();
    final errors = <Object>[];
    var moves = 0;
    final motion = PtzMotion(
      move: (_, _, _) async {
        moves++;
      },
      halt: () => halt.future,
      onError: errors.add,
    );
    motion.steer(1, 0);
    motion.steer(0, 0);
    motion.steer(-1, 0);
    halt.completeError(StateError('fixture'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(moves, 1);
    expect(errors, hasLength(1));
    await motion.close();
  });

  test('Botão Parar força envio mesmo sem movimento pendente', () async {
    var stops = 0;
    final motion = PtzMotion(
      move: (_, _, _) async {},
      halt: () async {
        stops++;
      },
      onError: (_) {},
    );
    await motion.stop(force: true);
    expect(stops, 1);
    await motion.close();
  });

  test(
    'Soltar aguarda movimento pendente e envia Stop por último, sem novos pulsos',
    () async {
      final pending = Completer<void>();
      final sent = <String>[];
      final errors = <Object>[];
      final motion = PtzMotion(
        move: (x, y, z) async {
          sent.add('move');
          await pending.future;
        },
        halt: () async {
          sent.add('stop');
        },
        onError: errors.add,
        interval: const Duration(milliseconds: 10),
      );
      motion.start(1, 0, 0);
      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(sent, ['move']);
      final stopping = motion.stop();
      motion.start(-1, 0, 0); // no restart while Stop is pending
      pending.complete();
      await stopping;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(sent, ['move', 'stop']);
      expect(errors, isEmpty);
      await motion.close();
    },
  );
  test(
    'Limite de segurar e encerramento disparam Stop automaticamente',
    () async {
      var moves = 0, stops = 0;
      final motion = PtzMotion(
        move: (_, _, _) async {
          moves++;
        },
        halt: () async {
          stops++;
        },
        onError: (_) {},
        interval: const Duration(milliseconds: 10),
        holdLimit: const Duration(milliseconds: 35),
      );
      motion.start(0, 1, 0);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(moves, greaterThan(0));
      expect(stops, 1);
      motion.start(0, 0, 1);
      await motion.close();
      expect(stops, 2);
      motion.start(0, 1, 0);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(stops, 2);
    },
  );
  test('Falha de movimento também manda Stop e preserva o erro', () async {
    var stops = 0;
    final errors = <Object>[];
    final motion = PtzMotion(
      move: (_, _, _) async {
        throw StateError('fixture');
      },
      halt: () async {
        stops++;
      },
      onError: errors.add,
    );
    motion.start(0, 1, 0);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(stops, 1);
    expect(errors, hasLength(1));
    await motion.close();
  });
}
