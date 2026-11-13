import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jortan_viewer/camera.dart';
import 'package:jortan_viewer/rtsp_probe.dart';

void main() {
  test('Digest MD5 qop=auth corresponde a vetor independente', () {
    final auth = rtspAuthorization(
      'Digest realm="testrealm@host.com", nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093", qop="auth,auth-int"',
      const CameraConfig(username: 'Mufasa', password: 'Circle Of Life'),
      '/dir/index.html',
      cnonce: '0a4f113b',
    );
    expect(auth, contains('response="eb8af4678a7d127d0b4f513f90100c6e"'));
    expect(auth, contains('qop=auth'));
    expect(
      rtspAuthorization(
        'Digest realm="x",nonce="y",algorithm=unknown',
        const CameraConfig(),
        '/',
      ),
      isNull,
    );
  });
  test('Basic monta cabeçalho e parser não mistura corpo com status', () {
    expect(
      rtspAuthorization(
        'Basic realm="camera"',
        const CameraConfig(password: 'senha'),
        '/',
      ),
      'Basic ${base64Encode(utf8.encode('admin:senha'))}',
    );
    final reply = RtspReply.parse(
      utf8.encode(
        'RTSP/1.0 200 OK\r\nCSeq: 0\r\nContent-Length: 4\r\n\r\nv=0\n',
      ),
    );
    expect(reply.status, 200);
    expect(reply.body, 'v=0\n');
    expect(
      () => RtspReply.parse(utf8.encode('HTTP/1.1 200 OK\r\n\r\n')),
      throwsFormatException,
    );
  });
  test(
    'Servidor real local: CSeq zero, autenticação Digest e SDP são registrados',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final subscription = server.listen((socket) {
        sockets.add(socket);
        var buffer = '';
        socket.listen((bytes) {
          buffer += utf8.decode(bytes);
          while (buffer.contains('\r\n\r\n')) {
            final end = buffer.indexOf('\r\n\r\n');
            final request = buffer.substring(0, end);
            buffer = buffer.substring(end + 4);
            final describe = request.startsWith('DESCRIBE');
            final authenticated = request.contains('Authorization: Digest');
            final status = describe && !authenticated
                ? '401 Unauthorized'
                : '200 OK';
            const sdp =
                'v=0\r\nm=video 0 RTP/AVP 96\r\na=rtpmap:96 H264/90000\r\n';
            final body = describe && authenticated ? sdp : '';
            final header =
                'RTSP/1.0 $status\r\nCSeq: 0\r\nServer: TestCamera\r\n'
                '${status.startsWith('401') ? 'WWW-Authenticate: Digest realm="camera", nonce="server-secret", qop="auth"\r\n' : ''}'
                'Content-Type: application/sdp\r\nContent-Length: ${utf8.encode(body).length}\r\n\r\n';
            socket.add(utf8.encode(header.substring(0, 10)));
            socket.add(utf8.encode(header.substring(10) + body));
          }
        });
      });
      final probe = RtspProbe();
      try {
        final report = await probe.run(
          CameraConfig(
            host: '127.0.0.1',
            port: server.port,
            password: 'local-secret',
          ),
        );
        expect(report['statusDescribe'], 200);
        expect(report['tcpConectado'], true);
        expect(report['autenticacaoConfirmada'], true);
        expect((report['sdp'] as Map)['codecs'], contains('96 H264/90000'));
        expect((report['sdp'] as Map)['audioAnunciado'], false);
        final replies = report['respostas'] as List;
        expect(replies.map((r) => r['status']), [200, 401, 200]);
        expect(replies.every((r) => r['cseqConfere'] == false), true);
        expect(jsonEncode(report), isNot(contains('server-secret')));
        expect(jsonEncode(report), isNot(contains('local-secret')));
      } finally {
        probe.cancel();
        for (final socket in sockets) {
          socket.destroy();
        }
        await subscription.cancel();
        await server.close();
      }
    },
  );
  test(
    'Servidor silencioso produz timeout limitado e pode ser cancelado',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final subscription = server.listen((socket) {
        sockets.add(socket);
        socket.listen((_) {});
      });
      final probe = RtspProbe();
      try {
        final report = await probe.run(
          CameraConfig(host: '127.0.0.1', port: server.port),
          budget: const Duration(milliseconds: 50),
        );
        expect((report['erro'] as Map)['tipo'], 'TimeoutException');
        expect((report['erro'] as Map)['etapa'], 'OPTIONS');
        expect(report['tcpConectado'], true);
      } finally {
        probe.cancel();
        for (final socket in sockets) {
          socket.destroy();
        }
        await subscription.cancel();
        await server.close();
      }
    },
  );
  test('Resposta grande é rejeitada sem guardar conteúdo bruto', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    final subscription = server.listen((socket) {
      sockets.add(socket);
      socket.listen((_) {
        socket.write('RTSP/1.0 200 OK\r\nContent-Length: 999999\r\n\r\n');
      });
    });
    final probe = RtspProbe();
    try {
      final report = await probe.run(
        CameraConfig(host: '127.0.0.1', port: server.port),
      );
      expect((report['erro'] as Map)['tipo'], 'FormatException');
    } finally {
      probe.cancel();
      for (final socket in sockets) {
        socket.destroy();
      }
      await subscription.cancel();
      await server.close();
    }
  });
  test('Cancelamento interrompe a leitura RTSP em andamento', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    final received = Completer<void>();
    final subscription = server.listen((socket) {
      sockets.add(socket);
      socket.listen((_) {
        if (!received.isCompleted) received.complete();
      });
    });
    final probe = RtspProbe();
    try {
      final pending = probe.run(
        CameraConfig(host: '127.0.0.1', port: server.port),
      );
      await received.future.timeout(const Duration(seconds: 2));
      probe.cancel();
      final report = await pending.timeout(const Duration(seconds: 1));
      expect((report['erro'] as Map)['mensagem'], contains('cancelado'));
    } finally {
      probe.cancel();
      for (final socket in sockets) {
        socket.destroy();
      }
      await subscription.cancel();
      await server.close();
    }
  });
}
