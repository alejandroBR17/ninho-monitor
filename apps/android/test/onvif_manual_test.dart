import 'dart:convert';
import 'dart:io';
import 'package:xml/xml.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jortan_viewer/camera.dart';
import 'package:jortan_viewer/onvif.dart';
import 'onvif_compatibility_test.dart' show operation, reply, fault;

void main() {
  for (final format in ['minimal', 'standard', 'rejected']) {
    final acceptStop = format != 'rejected';
    test('Modo manual só envia movimento após Stop confirmado: $format', () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      final base = 'http://127.0.0.1:${server.port}';
      final moves = <String>[], stops = <String>[], operations = <String>[];
      final events = <Map<String, dynamic>>[];
      final zeroStops = <String>[];
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final op = operation(body);
        operations.add(op);
        switch (op) {
          case 'GetCapabilities':
            await reply(
              request,
              '<t:GetCapabilitiesResponse><t:Media><t:XAddr>$base/media</t:XAddr></t:Media><t:PTZ><t:XAddr>$base/io</t:XAddr></t:PTZ></t:GetCapabilitiesResponse>',
            );
          case 'GetProfiles':
            await reply(
              request,
              '<t:GetProfilesResponse><t:Profiles token="real-token"><t:PTZConfiguration token="cfg"><t:NodeToken>node</t:NodeToken></t:PTZConfiguration></t:Profiles></t:GetProfilesResponse>',
            );
          case 'GetServices':
            await reply(request, '<t:GetServicesResponse/>');
          case 'GetSystemDateAndTime':
            await reply(request, '<t:GetSystemDateAndTimeResponse/>');
          case 'Stop':
            stops.add(body);
            if (body.contains('<soap:Envelope')) {
              expect(body, isNot(contains('Security')));
              expect(body, isNot(contains('fixture-password')));
              expect(request.headers.value('SOAPAction'), isNull);
              expect(request.contentLength, utf8.encode(body).length);
            }
            await reply(
              request,
              (acceptStop &&
                      (format == 'minimal' || !body.contains('<soap:Envelope')))
                  ? '<t:StopResponse/>'
                  : fault,
            );
          case 'ContinuousMove':
            final tilt = XmlDocument.parse(body).descendants
                .whereType<XmlElement>()
                .firstWhere((e) => e.name.local == 'PanTilt');
            if (double.parse(tilt.getAttribute('x')!) == 0 &&
                double.parse(tilt.getAttribute('y')!) == 0) {
              zeroStops.add(body);
            } else {
              moves.add(body);
            }
            // Rejection must not replay the movement in another format.
            await reply(request, fault);
          default:
            await reply(request, fault);
        }
      });
      final client = OnvifClient(
        CameraConfig(
          host: '127.0.0.1',
          password: 'fixture-password',
          onvifUrl: '$base/device',
        ),
        onEvent: events.add,
      );
      addTearDown(() async {
        client.close();
        await server.close(force: true);
      });
      final manual = await client.inspect(manualOnly: true);
      expect(manual, isNotEmpty);
      expect(operations, contains('GetProfiles'));
      expect(operations, isNot(contains('GetConfigurationOptions')));
      expect(operations, isNot(contains('ContinuousMove')));
      expect(operations, isNot(contains('Stop')));
      await expectLater(client.inspect(), throwsA(isA<OnvifFailure>()));
      expect(moves, isEmpty);
      expect(stops, isEmpty);
      final profile = client.manualCandidates.first;
      expect(profile.token, 'real-token');
      expect(profile.endpoint.path, '/io');
      expect(profile.manualYoosee, true);
      expect(profile.zoom, isNull);
      await expectLater(
        client.move(profile, 1, 0, 0),
        throwsA(isA<OnvifFailure>()),
      );
      expect(moves, isEmpty);
      if (acceptStop) {
        await client.prepareManual(profile);
        expect(stops.length, format == 'minimal' ? 1 : 2);
        await expectLater(
          client.move(profile, 1, 0, 0),
          throwsA(isA<OnvifFailure>()),
        );
        expect(moves.length, 1);
        expect(moves.single, contains('real-token'));
        expect(
          moves.single,
          contains(
            '<${format == 'minimal' ? 'ptz' : 'tt'}:PanTilt x="0.1" y="0.0"/>',
          ),
        );
        expect(moves.single, contains('PT0.3S'));
        expect(moves.single, isNot(contains('space=')));
        await client.stop(profile);
        expect(stops.length, format == 'minimal' ? 2 : 3);
      } else {
        await expectLater(
          client.prepareManual(profile),
          throwsA(
            isA<OnvifFailure>().having(
              (e) => e.code,
              'code',
              'parada_previa_falhou',
            ),
          ),
        );
        expect(stops.length, 2);
        expect(zeroStops.length, 2);
        await expectLater(
          client.move(profile, 1, 0, 0),
          throwsA(isA<OnvifFailure>()),
        );
        expect(moves, isEmpty);
      }
      expect(jsonEncode(events), isNot(contains('fixture-password')));
    });
  }
}
