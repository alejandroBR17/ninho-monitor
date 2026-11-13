import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:jortan_viewer/camera.dart';
import 'package:jortan_viewer/onvif.dart';
import 'onvif_addressing_test.dart' show manual, field, legacy, current;
import 'onvif_compatibility_test.dart' show operation, reply, fault;

void main() {
  for (final minimal in [false, true]) {
    test(
      'Stop sem resposta usa velocidade zero confirmada: minimal=$minimal',
      () async {
        final server = await HttpServer.bind('127.0.0.1', 0);
        final uri = Uri.parse(
          'http://127.0.0.1:${server.port}/onvif/deviceio_service',
        );
        final requests = <XmlDocument>[];
        var stopped = 0, moving = 0;
        var rejectMove = false;
        server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          final doc = XmlDocument.parse(body);
          requests.add(doc);
          if (operation(body) == 'Stop') {
            final socket = await request.response.detachSocket(
              writeHeaders: false,
            );
            socket.destroy();
            return;
          }
          final tilt = field(doc, 'PanTilt')!;
          final x = double.parse(tilt.getAttribute('x')!);
          final y = double.parse(tilt.getAttribute('y')!);
          final zero = x == 0 && y == 0;
          final matchesFormat =
              field(doc, 'Action')!.namespaceUri ==
              (minimal ? legacy : current);
          if (zero) {
            stopped++;
            expect(field(doc, 'Timeout'), isNull);
          } else {
            moving++;
            expect(x, .1);
            expect(y, 0);
            expect(tilt.getAttribute('space'), isNull);
            expect(
              field(doc, 'Action')!.namespaceUri,
              minimal ? legacy : current,
            );
            expect(tilt.name.prefix, minimal ? 'ptz' : 'tt');
          }
          await reply(
            request,
            matchesFormat && !(rejectMove && !zero)
                ? '<t:ContinuousMoveResponse/>'
                : fault,
          );
        });
        final events = <Map<String, dynamic>>[];
        final client = OnvifClient(
          const CameraConfig(host: '127.0.0.1', password: 'fixture-private'),
          onEvent: events.add,
        );
        addTearDown(() async {
          client.close();
          await server.close(force: true);
        });
        final profile = manual(uri);
        expect(
          () => client.setManualHold(profile, true),
          throwsA(isA<OnvifFailure>()),
        );
        await client.prepareManual(
          profile,
          preferredMinimal: minimal ? null : false,
          preferredZeroStop: minimal ? null : true,
        );
        expect(moving, 0);
        expect(
          requests.where((d) => field(d, 'Stop') != null).length,
          minimal ? 2 : 0,
        );
        expect(stopped, minimal ? 2 : 1);
        expect(
          client.manualStopMethod(profile),
          'ContinuousMove_velocidade_zero',
        );
        final preflightCount = requests.length;
        await client.move(profile, 1, 0, 0);
        expect(field(requests.last, 'Timeout')!.innerText, 'PT0.3S');
        client.setManualHold(profile, true);
        await client.move(profile, 1, 0, 0);
        expect(field(requests.last, 'Timeout')!.innerText, 'PT2S');
        await client.stop(profile);
        expect(requests.length, preflightCount + 3);
        expect(field(requests.last, 'PanTilt')!.getAttribute('x'), '0.0');
        expect(field(requests.last, 'PanTilt')!.getAttribute('y'), '0.0');
        rejectMove = true;
        await expectLater(
          client.move(profile, 1, 0, 0),
          throwsA(isA<OnvifFailure>()),
        );
        expect(moving, 3); // Refused nonzero movement is never replayed.
        await client.stop(profile);
        expect(jsonEncode(events), isNot(contains('fixture-private')));
      },
    );
  }
}
