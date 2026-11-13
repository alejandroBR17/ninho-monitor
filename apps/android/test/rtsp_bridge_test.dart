import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:jortan_viewer/camera.dart';
import 'package:jortan_viewer/rtsp_bridge.dart';
import 'package:jortan_viewer/rtsp_probe.dart';
import 'package:crypto/crypto.dart';

void main() {
  test(
    'Resposta real Jortan: completa /TCP apenas para canais correspondentes',
    () {
      const requested = 'RTP/AVP/TCP;unicast;interleaved=0-1';
      const received =
          'RTP/AVP;unicast;destination=192.168.1.11;source=192.168.1.100;interleaved=0-1';
      expect(
        normalizeTcpTransport(requested, received),
        'RTP/AVP/TCP;unicast;destination=192.168.1.11;source=192.168.1.100;interleaved=0-1',
      );
      for (final value in [
        'RTP/AVP;unicast;client_port=4000-4001;server_port=5000-5001',
        'RTP/AVP/UDP;unicast;interleaved=0-1',
        'RTP/AVP;unicast;interleaved=2-3',
        'RTP/AVP/TCP;unicast;interleaved=0-1',
      ]) {
        expect(normalizeTcpTransport(requested, value), value);
      }
    },
  );
  test(
    'RTSP fragmentado e RTP misturado preservam todos os bytes binários',
    () {
      final framer = RtspFramer();
      final message = utf8.encode(
        'RTSP/1.0 200 OK\r\nCSeq: 4\r\nContent-Length: 4\r\n\r\nv=0\n',
      );
      final video = [36, 0, 0, 8, 0, 13, 10, 13, 10, 255, 36, 0];
      final joined = [...message, ...video, ...message];
      final packets = <List<int>>[];
      for (var index = 0; index < joined.length; index += 3) {
        packets.addAll(
          framer.add(
            joined.sublist(index, (index + 3).clamp(0, joined.length)),
          ),
        );
      }
      expect(packets, [message, video, message]);
      final roundTrip = RtspReply.parse(RtspMessage.parse(message).encode());
      expect(roundTrip.status, 200);
      expect(roundTrip.body, 'v=0\n');
    },
  );
  test('Digest é recalculado com URI original e método SETUP', () {
    const config = CameraConfig(username: 'admin', password: 'local-secret');
    const header =
        'Digest username="admin", realm="camera", nonce="abc", uri="rtsp://127.0.0.1:1000/token/onvif1/track1", response="old"';
    const target = 'rtsp://192.168.1.100:554/onvif1/track1';
    final result = rewriteDigestAuthorization(header, 'SETUP', target, config);
    final values = parseChallenge(result);
    String hash(String s) => md5.convert(utf8.encode(s)).toString();
    final expected = hash(
      '${hash('admin:camera:local-secret')}:abc:${hash('SETUP:$target')}',
    );
    expect(values['uri'], target);
    expect(values['response'], expected);
    expect(result, isNot(contains('local-secret')));
  });
  test(
    'Diagnóstico prioriza transporte incompatível sobre erro genérico de formato',
    () {
      expect(
        diagnoseFailure(
          'Nonmatching transport in server reply\navformat_open_input() failed\nFailed to recognize file format.',
        ).code,
        'rtsp_transport_mismatch',
      );
    },
  );
  test(
    'Dump caractere a caractere não ocupa o relatório nem preserva fragmentos de autenticação',
    () {
      final attempt = Attempt('tcp', 0);
      attempt.addLog('trace [ffmpeg/demuxer]: rtsp: ret=1 c=61 [a]');
      attempt.addLog('error [ffmpeg]: Nonmatching transport in server reply');
      expect(attempt.logs.length, 1);
      expect(attempt.droppedLogs, 1);
    },
  );
}
