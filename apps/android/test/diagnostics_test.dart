import 'package:flutter_test/flutter_test.dart';
import 'package:jortan_viewer/camera.dart';

void main() {
  test('Regressão 1.4: 200 removido do buffer não vira senha recusada', () {
    final attempt = Attempt('tcp', 0);
    for (var i = 0; i < 70; i++) {
      attempt.addLog('inicial $i');
    }
    attempt.addLog('RTSP/1.0 401 Unauthorized');
    for (var i = 0; i < 30; i++) {
      attempt.addLog('negociacao $i');
    }
    attempt.addLog('RTSP/1.0 200 OK');
    for (var i = 0; i < 500; i++) {
      attempt.addLog('error hevc: PPS id out of range: 0');
    }
    attempt.addLog('hevc_mediacodec: width=0, height=0');
    attempt.addLog('Could not open codec.');
    expect(attempt.logs.join(), isNot(contains('RTSP/1.0 200')));
    expect(attempt.lastRtspStatus, 200);
    final finding = diagnoseFailure(
      attempt.logs.join('\n'),
      finalRtspStatus: attempt.lastRtspStatus,
    );
    expect(finding.code, 'video_parameters_missing');
    expect(
      attempt.importantLogs.where((l) => l.contains('PPS id')),
      hasLength(1),
    );
    expect(attempt.importantLogs.last, contains('Could not open codec'));
  });

  test(
    'Regressão do relatório real: propriedade ausente e CSeq não viram caminho inválido',
    () {
      final finding = diagnoseFailure(
        '''media_kit: error: property not found _setProperty(osc, 1)
playlist: Reading plaintext playlist.
ffmpeg/demuxer: rtsp: CSeq 3 expected, 0 received.
lavf: avformat_open_input() failed
cplayer: Failed to recognize file format.''',
      );
      expect(finding.code, 'rtsp_sequence_mismatch');
      expect(finding.confidence, 'indicio');
      expect(finding.evidence.join(), contains('CSeq 3 expected, 0 received'));
    },
  );
  test(
    'Avisos de propriedade e frames recuperáveis não são erros terminais',
    () {
      expect(
        isTerminalPlayerError('property not found _setProperty(osc, 1)'),
        false,
      );
      expect(isTerminalPlayerError('Could not find ref with POC 42'), false);
      expect(isTerminalPlayerError('Failed to recognize file format.'), true);
    },
  );
  test('Regressão UDP real: falha genérica não comprova caminho nem codec', () {
    final finding = diagnoseFailure(
      'property not found _setProperty(osc, 1)\navformat_open_input() failed\nFailed to recognize file format.',
    );
    expect(finding.code, 'rtsp_open_failed');
    expect(finding.confidence, 'causa_indeterminada');
  });
  test('Desafio 401 seguido de sucesso não é senha recusada', () {
    final finding = diagnoseFailure(
      'RTSP/1.0 401 Unauthorized\nRTSP/1.0 200 OK\nFailed to recognize file format.',
    );
    expect(finding.code, 'rtsp_open_failed');
  });
  test('404 de OPTIONS seguido de DESCRIBE 200 não rejeita caminho', () {
    expect(
      diagnoseFailure(
        'OPTIONS: RTSP/1.0 404 Not Found\nDESCRIBE: RTSP/1.0 200 OK\nFailed to recognize file format.',
      ).code,
      'rtsp_open_failed',
    );
    expect(
      diagnoseFailure('method DESCRIBE failed: 404 Not Found').code,
      'rtsp_path_not_found',
    );
  });
  test('Tokens Digest e Authorization são removidos antes de armazenar', () {
    final clean = Redactor().clean(
      'username="admin", nonce="secretNonce", cnonce="secretClient", response="secretDigest"\nAuthorization: Basic private-token',
    );
    for (final secret in [
      'admin',
      'secretNonce',
      'secretClient',
      'secretDigest',
      'private-token',
    ]) {
      expect(clean, isNot(contains(secret)));
    }
  });
  test('Limite de logs preserva começo, fim, erros e informa descarte', () {
    final attempt = Attempt('tcp', 0);
    for (var index = 0; index < 500; index++) {
      attempt.addLog('linha $index');
    }
    attempt.addLog('CSeq 3 expected, 0 received');
    expect(attempt.logs.length, 320);
    expect(attempt.logs.first, 'linha 0');
    expect(attempt.logs.last, contains('CSeq'));
    expect(attempt.importantLogs.single, contains('CSeq'));
    expect(attempt.droppedLogs, 181);
  });
}
