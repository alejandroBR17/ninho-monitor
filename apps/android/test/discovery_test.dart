import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jortan_viewer/discovery.dart';

void main() {
  test('Faixas locais são normalizadas e limitadas a 254 hosts', () {
    final range = DiscoveryRange.parse('192.168.1.100/24');
    expect(range.toString(), '192.168.1.0/24');
    expect(range.hosts.length, 254);
    expect(range.hosts.first, '192.168.1.1');
    expect(range.hosts.last, '192.168.1.254');
    expect(DiscoveryRange.parse('10.1.2.3/32').hosts, ['10.1.2.3']);
    for (final invalid in [
      '8.8.8.0/24',
      '192.168.1.0/16',
      '192.168.1.256/24',
      '192.168.01.1/24',
    ]) {
      expect(() => DiscoveryRange.parse(invalid), throwsFormatException);
    }
  });
  test('ONVIF aceita resposta correlacionada e rejeita outra busca e rede', () {
    const xml =
        '''<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:a="http://schemas.xmlsoap.org/ws/2004/08/addressing" xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery"><s:Header><a:RelatesTo>urn:uuid:test</a:RelatesTo></s:Header><s:Body><d:ProbeMatches><d:ProbeMatch><d:Types>dn:NetworkVideoTransmitter</d:Types><d:Scopes>onvif://www.onvif.org/name/Minha%20Camera</d:Scopes><d:XAddrs>http://192.168.1.100:8999/onvif/device_service</d:XAddrs></d:ProbeMatch></d:ProbeMatches></s:Body></s:Envelope>''';
    final range = DiscoveryRange.parse('192.168.1.0/24');
    final found = parseDiscoveryReply(
      '192.168.1.100',
      xml,
      'urn:uuid:test',
      range,
    );
    expect(found.single.host, '192.168.1.100');
    expect(found.single.name, 'Minha Camera');
    expect(found.single.onvif, true);
    expect(found.single.rtspConfirmed, false);
    expect(
      parseDiscoveryReply('192.168.1.100', xml, 'urn:uuid:other', range),
      isEmpty,
    );
    expect(
      parseDiscoveryReply('10.0.0.2', xml, 'urn:uuid:test', range),
      isEmpty,
    );
    expect(
      parseDiscoveryReply('192.168.1.100', '<broken>', 'urn:uuid:test', range),
      isEmpty,
    );
  });
  test(
    'Busca limita concorrência, junta ONVIF/RTSP e não testa senhas',
    () async {
      var active = 0, maxActive = 0;
      final calls = <String>[];
      final scanner = CameraDiscovery(
        concurrency: 2,
        probeOverride: (host, port) async {
          active++;
          if (active > maxActive) maxActive = active;
          calls.add('$host:$port');
          await Future<void>.delayed(const Duration(milliseconds: 2));
          active--;
          return host == '192.168.1.1'
              ? DiscoveryDevice(host, rtspStatuses: {port: 401})
              : null;
        },
      );
      final report = await scanner.search(
        DiscoveryRange.parse('192.168.1.0/30'),
        onvif: false,
      );
      expect(maxActive, lessThanOrEqualTo(2));
      expect(calls.length, 4);
      expect(report.completed, 4);
      expect(report.found.length, 1);
      expect(report.found.single.port, 554);
      expect(report.found.single.rtspStatuses.keys.toSet(), {554, 8554});
    },
  );
  test('Cancelar impede o início de novos testes', () async {
    final gate = Completer<void>();
    var calls = 0;
    final scanner = CameraDiscovery(
      concurrency: 1,
      probeOverride: (host, port) async {
        calls++;
        await gate.future;
        return null;
      },
    );
    final running = scanner.search(
      DiscoveryRange.parse('192.168.1.0/24'),
      onvif: false,
    );
    await Future<void>.delayed(Duration.zero);
    scanner.cancel();
    gate.complete();
    final report = await running;
    expect(calls, 1);
    expect(report.cancelled, true);
  });
  test(
    'Somente resposta RTSP válida confirma o serviço; HTTP é rejeitado',
    () async {
      final sockets = <Socket>[];
      final rtsp = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final http = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final r = rtsp.listen((socket) {
        sockets.add(socket);
        socket.listen((bytes) {
          expect(utf8.decode(bytes), isNot(contains('Authorization')));
          socket.write('RTSP/1.0 401 Unauthorized\r\nCSeq: 1\r\n\r\n');
        });
      });
      final h = http.listen((socket) {
        sockets.add(socket);
        socket.listen((_) {
          socket.write('HTTP/1.1 200 OK\r\n\r\n');
        });
      });
      final scanner = CameraDiscovery();
      try {
        final found = await scanner.probeRtsp('127.0.0.1', rtsp.port);
        expect(found?.rtspStatuses[rtsp.port], 401);
        expect(await scanner.probeRtsp('127.0.0.1', http.port), isNull);
      } finally {
        scanner.cancel();
        for (final socket in sockets) {
          socket.destroy();
        }
        await r.cancel();
        await h.cancel();
        await rtsp.close();
        await http.close();
      }
    },
  );
  test('Resposta RTSP silenciosa tem prazo e encerra o socket', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    final reading = server.listen((socket) {
      sockets.add(socket);
      socket.listen((_) {});
    });
    final scanner = CameraDiscovery(
      replyTimeout: const Duration(milliseconds: 20),
    );
    try {
      expect(await scanner.probeRtsp('127.0.0.1', server.port), isNull);
    } finally {
      scanner.cancel();
      for (final socket in sockets) {
        socket.destroy();
      }
      await reading.cancel();
      await server.close();
    }
  });
}
