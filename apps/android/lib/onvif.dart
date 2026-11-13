import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';
import 'camera.dart';
import 'rtsp_probe.dart';

const _device = 'http://www.onvif.org/ver10/device/wsdl';
const _media = 'http://www.onvif.org/ver10/media/wsdl';
const _ptz = 'http://www.onvif.org/ver20/ptz/wsdl';
const _wsaCurrent = 'http://www.w3.org/2005/08/addressing';
const _wsaLegacy = 'http://schemas.xmlsoap.org/ws/2004/08/addressing';
String _messageId() {
  final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return 'urn:uuid:${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String _xml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
Iterable<XmlElement> _elements(XmlNode node, String name) =>
    node.descendants.whereType<XmlElement>().where((e) => e.name.local == name);
String? _text(XmlNode node, String name) =>
    _elements(node, name).firstOrNull?.innerText.trim();

class OnvifFailure implements Exception {
  final String code, message;
  final bool methodUnrecognized;
  OnvifFailure(this.code, this.message, {this.methodUnrecognized = false});
  @override
  String toString() => message;
}

class VelocitySpace {
  final String uri;
  final double xMin, xMax, yMin, yMax, fraction;
  VelocitySpace(
    this.uri,
    this.xMin,
    this.xMax,
    this.yMin,
    this.yMax, {
    this.fraction = .35,
  });
  double _speed(double min, double max, int direction) => direction < 0
      ? (min < 0 ? min * fraction : 0)
      : direction > 0
      ? (max > 0 ? max * fraction : 0)
      : 0;
  double x(int direction) => _speed(xMin, xMax, direction);
  double y(int direction) => _speed(yMin, yMax, direction);
}

class PtzProfile {
  final String token, name;
  final Uri endpoint;
  final VelocitySpace? panTilt, zoom;
  final String capabilitySource;
  PtzProfile(
    this.token,
    this.name,
    this.endpoint,
    this.panTilt,
    this.zoom, {
    this.capabilitySource = 'GetConfigurationOptions',
  });
  bool get requiresTest =>
      capabilitySource == 'espaco_generico_declarado_no_perfil' || manualYoosee;
  bool get manualYoosee => capabilitySource == 'compatibilidade_yoosee_manual';
  bool get supported => panTilt != null || zoom != null;
}

/// SOAP replies are bounded. Only the configured camera can receive credentials.
/// Diagnostics contain bounded, redacted fault fields, never SOAP/auth headers.
class OnvifClient {
  static const defaultRequestTimeout = Duration(seconds: 4);
  static const capabilityBudget = Duration(seconds: 32);
  final CameraConfig config;
  final void Function(Map<String, dynamic>) onEvent;
  final Duration timeout;
  final HttpClient _http = HttpClient();
  Duration _clockOffset = Duration.zero;
  bool _closed = false;
  final Redactor _redactor = Redactor();
  final Map<Uri, String> _ptzPrefixes = {};
  final List<PtzProfile> manualCandidates = [];
  final Map<Uri, bool> _manualMinimal = {};
  final Map<Uri, bool> _manualZeroStop = {};
  final Set<Uri> _manualHold = {};
  OnvifClient(
    this.config, {
    required this.onEvent,
    this.timeout = defaultRequestTimeout,
  }) {
    _redactor.add(config);
    _http.connectionTimeout = timeout;
    _http.findProxy = (_) =>
        'DIRECT'; // Local camera, never the system web proxy.
  }
  Uri endpoint(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host != config.host ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw OnvifFailure(
        'endpoint_recusado',
        'A câmera anunciou um serviço fora do endereço configurado.',
      );
    }
    return uri;
  }

  String _security() {
    final nonce = List.generate(20, (_) => Random.secure().nextInt(256));
    final created = DateTime.now().toUtc().add(_clockOffset).toIso8601String();
    final digest = base64Encode(
      sha1.convert([
        ...nonce,
        ...utf8.encode(created),
        ...utf8.encode(config.password),
      ]).bytes,
    );
    return '<wsse:Security s:mustUnderstand="1" '
        'xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" '
        'xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">'
        '<wsse:UsernameToken><wsse:Username>${_xml(config.username)}</wsse:Username>'
        '<wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">$digest</wsse:Password>'
        '<wsse:Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">${base64Encode(nonce)}</wsse:Nonce>'
        '<wsu:Created>$created</wsu:Created></wsse:UsernameToken></wsse:Security>';
  }

  String? _safeField(String? value) {
    if (value == null) return null;
    final text = _redactor.clean(value.trim());
    if (text.length > 256 || text.contains(RegExp(r'[<>\r\n]'))) {
      return '[valor omitido]';
    }
    final uri = Uri.tryParse(text);
    if (uri != null &&
        (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment)) {
      return '[valor omitido]';
    }
    return text;
  }

  String? _direct(XmlElement node, String name) =>
      node.getAttribute(name) ??
      node.childElements
          .where((e) => e.name.local == name)
          .firstOrNull
          ?.innerText
          .trim();

  Map<String, dynamic> _target(Uri uri) => {
    'endereco': uri.host,
    'porta': uri.port,
    'caminho': uri.path,
    'https': uri.scheme == 'https',
  };

  String _networkCode(Object error) {
    if (error is HandshakeException || error is TlsException) {
      return 'tls_verificacao';
    }
    if (error is SocketException) {
      if ([61, 111, 10061].contains(error.osError?.errorCode)) {
        return 'tcp_recusado';
      }
      if ([54, 104, 10054].contains(error.osError?.errorCode)) {
        return 'tcp_reset';
      }
      return 'socket_falhou';
    }
    if (error is HttpException) {
      final message = error.message.toLowerCase();
      if (message.contains('closed') || message.contains('connection reset')) {
        return 'http_conexao_encerrada';
      }
      return 'http_invalido';
    }
    return 'falha_de_rede';
  }

  Future<XmlDocument> call(
    Uri uri,
    String ns,
    String operation,
    String body, {
    bool authenticated = true,
  }) async {
    // Only read-only operations may be retried automatically. A failed Move
    // might already have reached the motor and must never be replayed blindly.
    final ptzRead = ns == _ptz && operation.startsWith('Get');
    final prefixes = ptzRead
        ? <String>{_ptzPrefixes[uri] ?? 'tptz', 'tptz', 'ptz', ''}.toList()
        : <String>[ns == _ptz ? (_ptzPrefixes[uri] ?? 'tptz') : 't'];
    final maxAttempts = ptzRead ? prefixes.length : 2;
    for (var attempt = 0; ; attempt++) {
      try {
        final document = await _request(
          uri,
          ns,
          operation,
          body,
          authenticated: authenticated,
          soapPrefix: prefixes[ptzRead ? attempt : 0],
        );
        if (ptzRead) _ptzPrefixes[uri] = prefixes[attempt];
        return document;
      } on OnvifFailure catch (error) {
        if (attempt + 1 >= maxAttempts ||
            _closed ||
            !operation.startsWith('Get') ||
            !(['http_conexao_encerrada', 'tcp_reset'].contains(error.code) ||
                (ptzRead && error.methodUnrecognized))) {
          rethrow;
        }
        onEvent({
          'operacao': operation,
          ..._target(uri),
          'compatibilidade': ptzRead
              ? 'leitura_com_serializacao_xml_equivalente'
              : 'repeticao_de_leitura_em_nova_conexao',
          if (ptzRead)
            'proximoPrefixoSoap': prefixes[attempt + 1].isEmpty
                ? 'namespace_padrao'
                : prefixes[attempt + 1],
        });
      }
    }
  }

  Future<XmlDocument> _request(
    Uri uri,
    String ns,
    String operation,
    String body, {
    required bool authenticated,
    required String soapPrefix,
    bool minimal = false,
  }) async {
    endpoint(uri.toString());
    if (_closed) {
      throw OnvifFailure('cancelado', 'Verificação ONVIF cancelada.');
    }
    HttpClientRequest? request;
    var expired = false;
    var stage = 'conectando';
    final watch = Stopwatch()..start();
    // Yoosee's documented wire example uses WS-Addressing 2004/08;
    // standard ONVIF PTZ uses 2005/08. Keep Device/Media's working form.
    final addressing = ns == _ptz ? (minimal ? _wsaLegacy : _wsaCurrent) : null;
    final routing = <String, dynamic>{
      if (addressing != null) ...{
        'enderecamentoSoap': addressing,
        'actionSoap': '$ns/$operation',
        'destinoSoap': _target(uri),
      },
      'prefixoSoap': soapPrefix.isEmpty ? 'namespace_padrao' : soapPrefix,
      'formatoSoap': minimal ? 'yoosee_minimo' : 'onvif_padrao',
    };
    try {
      return await (() async {
        String? authorization;
        for (var attempt = 0; attempt < 2; attempt++) {
          if (expired || _closed) {
            throw OnvifFailure('cancelado', 'Operação ONVIF cancelada.');
          }
          stage = 'conectando';
          request = await _http.postUrl(uri);
          if (expired || _closed) {
            request!.abort();
            throw OnvifFailure('cancelado', 'Operação ONVIF cancelada.');
          }
          request!.followRedirects = false;
          // Embedded ONVIF servers often mishandle pooled connections and
          // chunked POSTs. Send a complete UTF-8 body with a known length.
          request!.persistentConnection = false;
          request!.headers.set(
            'Content-Type',
            minimal
                ? 'application/soap+xml; charset=utf-8'
                : 'application/soap+xml; charset=utf-8; action="$ns/$operation"',
          );
          if (!minimal) request!.headers.set('SOAPAction', '"$ns/$operation"');
          if (authorization != null) {
            request!.headers.set('Authorization', authorization);
          }
          final prefix = soapPrefix;
          final qualified = prefix.isEmpty ? operation : '$prefix:$operation';
          final declaration = prefix.isEmpty ? 'xmlns' : 'xmlns:$prefix';
          final childPrefix = prefix.isEmpty ? '' : '$prefix:';
          final scopedBody = body
              .replaceAll('<t:', '<$childPrefix')
              .replaceAll('</t:', '</$childPrefix');
          final envelopePrefix = minimal ? 'soap' : 's';
          final routingHeader = addressing == null
              ? ''
              : '<wsa:Action>${_xml('$ns/$operation')}</wsa:Action>'
                    '<wsa:MessageID>${_messageId()}</wsa:MessageID>'
                    '<wsa:To>${_xml(uri.toString())}</wsa:To>';
          final securityHeader = !minimal && authenticated ? _security() : '';
          final soapHeader = minimal && routingHeader.isEmpty
              ? ''
              : '<$envelopePrefix:Header>$routingHeader$securityHeader</$envelopePrefix:Header>';
          final payload = utf8.encode(
            '${minimal ? '<?xml version="1.0" encoding="UTF-8"?>' : ''}'
            '<${minimal ? 'soap' : 's'}:Envelope xmlns:${minimal ? 'soap' : 's'}="http://www.w3.org/2003/05/soap-envelope" '
            '$declaration="$ns" xmlns:tt="http://www.onvif.org/ver10/schema"'
            '${addressing == null ? '' : ' xmlns:wsa="$addressing"'}>'
            '$soapHeader'
            '<${minimal ? 'soap' : 's'}:Body><$qualified>$scopedBody</$qualified></${minimal ? 'soap' : 's'}:Body></${minimal ? 'soap' : 's'}:Envelope>',
          );
          request!.contentLength = payload.length;
          stage = 'enviando_soap';
          request!.add(payload);
          stage = 'aguardando_cabecalho';
          final response = await request!.close();
          onEvent({
            'operacao': operation,
            ..._target(uri),
            ...routing,
            'http': response.statusCode,
            'etapa': 'cabecalho_recebido',
            'duracaoMs': watch.elapsedMilliseconds,
            'envio': 'Content-Length e Connection: close',
            'prefixoSoap': prefix,
            if (minimal) 'formatoSoap': 'yoosee_minimo_http_auth_se_solicitado',
            'tamanhoDeclarado': response.contentLength,
          });
          if (response.statusCode == 401 && attempt == 0 && authenticated) {
            authorization = rtspAuthorization(
              response.headers['www-authenticate']?.join(', ') ?? '',
              config,
              uri.path.isEmpty ? '/' : uri.path,
              method: 'POST',
            );
            await response.take(1).drain<void>();
            if (authorization != null) continue;
          }
          stage = 'lendo_corpo';
          final bytes = <int>[];
          await for (final part in response) {
            bytes.addAll(part);
            if (bytes.length > 512 * 1024) {
              throw OnvifFailure(
                'resposta_grande',
                'Resposta ONVIF excedeu 512 KB.',
              );
            }
          }
          if ([401, 403].contains(response.statusCode)) {
            throw OnvifFailure(
              'autenticacao_onvif',
              'ONVIF recusou o acesso. Confira a senha local ONVIF.',
            );
          }
          if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
            throw OnvifFailure(
              'redirecionamento_recusado',
              'O serviço ONVIF redirecionou o pedido. O app não encaminhou credenciais.',
            );
          }
          if (response.statusCode == 404) {
            throw OnvifFailure(
              'endpoint_404',
              'A câmera respondeu HTTP 404 para este serviço ONVIF.',
            );
          }
          if (response.statusCode == 405) {
            throw OnvifFailure(
              'metodo_http_recusado',
              'O serviço recusou o método HTTP POST.',
            );
          }
          stage = 'interpretando_xml';
          XmlDocument document;
          try {
            document = XmlDocument.parse(utf8.decode(bytes));
          } catch (_) {
            throw OnvifFailure(
              'resposta_nao_soap',
              'A porta não respondeu com XML ONVIF válido.',
            );
          }
          if (document.children.whereType<XmlDoctype>().isNotEmpty) {
            throw OnvifFailure('xml_recusado', 'Declaração XML não permitida.');
          }
          final fault = _elements(document, 'Fault').firstOrNull;
          if (fault != null) {
            final reasons = [
              ..._elements(fault, 'faultstring'),
              ..._elements(
                fault,
                'Reason',
              ).expand((reason) => _elements(reason, 'Text')),
            ].take(4).map((e) => e.innerText).toList();
            final unrecognized = reasons.any(
              (reason) => RegExp(
                r'method name or namespace not recognized|method\b.{0,160}\bnot implemented',
                caseSensitive: false,
              ).hasMatch(reason),
            );
            // Some embedded cameras return SOAP 1.1 faults inside otherwise
            // SOAP 1.2 responses. Read both formats without retaining raw XML.
            final rawCodes = [
              ..._elements(fault, 'faultcode'),
              ..._elements(
                fault,
                'Code',
              ).expand((code) => _elements(code, 'Value')),
            ].map((e) => e.innerText.trim()).toSet().take(8).toList();
            final values = rawCodes
                .map((value) => value.split(':').last)
                .toSet();
            const codes = [
              'NotAuthorized',
              'ActionNotSupported',
              'InvalidArgVal',
              'NoProfile',
              'NoConfig',
              'NoEntity',
              'InvalidVelocity',
              'SpaceNotSupported',
              'Timeout',
              'VersionMismatch',
            ];
            final safeCodes = codes.where(values.contains).toList();
            final known =
                safeCodes.firstOrNull ??
                (unrecognized ? 'metodo_onvif_nao_reconhecido' : 'SOAPFault');
            onEvent({
              'operacao': operation,
              ..._target(uri),
              'falhaSoap': known,
              'subcodigos': safeCodes,
              'formatoFalha': _elements(fault, 'faultcode').isNotEmpty
                  ? 'SOAP_1_1'
                  : 'SOAP_1_2',
              'codigosRecebidos': rawCodes.map(_safeField).toList(),
              'motivos': [
                ..._elements(fault, 'faultstring'),
                ..._elements(
                  fault,
                  'Reason',
                ).expand((reason) => _elements(reason, 'Text')),
              ].take(4).map((e) => _safeField(e.innerText)).toList(),
              'elementosFalha': fault.descendants
                  .whereType<XmlElement>()
                  .map((e) => _safeField(e.name.local))
                  .toSet()
                  .take(24)
                  .toList(),
            });
            throw OnvifFailure(
              known,
              known == 'NotAuthorized'
                  ? 'ONVIF recusou a autenticação. Confira a senha ONVIF e o horário da câmera.'
                  : 'A câmera recusou $operation ($known).',
              methodUnrecognized:
                  known == 'metodo_onvif_nao_reconhecido' ||
                  known == 'ActionNotSupported',
            );
          }
          if (response.statusCode != 200 ||
              _elements(document, '${operation}Response').isEmpty) {
            throw OnvifFailure(
              'resposta_inesperada',
              'A porta não confirmou $operation por ONVIF.',
            );
          }
          onEvent({
            'operacao': operation,
            ..._target(uri),
            'etapa': 'resposta_validada',
            ...routing,
            'bytes': bytes.length,
            'duracaoMs': watch.elapsedMilliseconds,
          });
          return document;
        }
        throw OnvifFailure(
          'autenticacao_onvif',
          'Não foi possível autenticar no serviço ONVIF.',
        );
      })().timeout(timeout);
    } on TimeoutException {
      expired = true;
      request?.abort();
      onEvent({
        'operacao': operation,
        ..._target(uri),
        ...routing,
        'codigo': 'timeout',
        'limiteMs': timeout.inMilliseconds,
        'etapa': stage,
        'duracaoMs': watch.elapsedMilliseconds,
      });
      throw OnvifFailure(
        'timeout',
        'A câmera não respondeu a $operation no prazo.',
      );
    } on OnvifFailure catch (error) {
      request?.abort();
      onEvent({
        'operacao': operation,
        ..._target(uri),
        ...routing,
        'codigo': error.code,
        'etapa': stage,
      });
      rethrow;
    } catch (error) {
      request?.abort();
      final code = _networkCode(error);
      onEvent({
        'operacao': operation,
        ..._target(uri),
        ...routing,
        'codigo': code,
        'tipoExcecao': error.runtimeType.toString(),
        if (error is SocketException) 'codigoSistema': error.osError?.errorCode,
        'etapa': stage,
        'duracaoMs': watch.elapsedMilliseconds,
      });
      throw OnvifFailure(
        code,
        code == 'tls_verificacao'
            ? 'Não foi possível validar a conexão HTTPS da câmera.'
            : 'Falha ao consultar $operation na porta ${uri.port}. Veja os detalhes no diagnóstico.',
      );
    }
  }

  Future<void> _clock(Uri uri) async {
    try {
      final doc = await call(
        uri,
        _device,
        'GetSystemDateAndTime',
        '',
        authenticated: false,
      );
      final utc = _elements(doc, 'UTCDateTime').firstOrNull;
      if (utc == null) return;
      int? number(String tag) => int.tryParse(_text(utc, tag) ?? '');
      final values = [
        'Year',
        'Month',
        'Day',
        'Hour',
        'Minute',
        'Second',
      ].map(number).toList();
      if (values.any((v) => v == null)) return;
      final time = DateTime.utc(
        values[0]!,
        values[1]!,
        values[2]!,
        values[3]!,
        values[4]!,
        values[5]!,
      );
      _clockOffset = time.difference(DateTime.now().toUtc());
      onEvent({
        'operacao': 'relogio_camera',
        'desvioSegundos': _clockOffset.inSeconds,
      });
    } on OnvifFailure {
      /* Some cameras require auth even for the clock. */
    }
  }

  int _failurePriority(OnvifFailure failure) => switch (failure.code) {
    'tls_verificacao' || 'endpoint_recusado' => 6,
    'NotAuthorized' || 'autenticacao_onvif' => 5,
    'timeout' => 4,
    'http_conexao_encerrada' || 'tcp_reset' => 3,
    'tcp_recusado' => 1,
    _ => 2,
  };

  String? _address(XmlElement node) =>
      node.getAttribute('XAddr') ??
      node.childElements
          .where((e) => e.name.local == 'XAddr')
          .firstOrNull
          ?.innerText
          .trim();

  Future<List<PtzProfile>> inspect({
    String? discoveredEndpoint,
    bool manualOnly = false,
  }) async {
    manualCandidates.clear();
    _manualMinimal.clear();
    _manualZeroStop.clear();
    _manualHold.clear();
    final candidates = <Uri>{};
    if (config.onvifUrl.isNotEmpty) {
      candidates.add(endpoint(config.onvifUrl));
    }
    if (discoveredEndpoint != null) {
      try {
        candidates.add(endpoint(discoveredEndpoint));
      } on OnvifFailure {
        /* reject foreign hosts */
      }
    }
    if (candidates.isEmpty) {
      for (final port in [80, 8899, 8999, 8080, 5000]) {
        candidates.add(
          Uri(
            scheme: 'http',
            host: config.host,
            port: port,
            path: '/onvif/device_service',
          ),
        );
      }
    }
    XmlDocument? capabilities;
    Uri? deviceUri;
    OnvifFailure? last;
    for (final candidate in candidates) {
      if (_closed) break;
      try {
        // First find an ONVIF service; clock correction is only done on a SOAP port.
        capabilities = await call(
          candidate,
          _device,
          'GetCapabilities',
          '<t:Category>All</t:Category>',
        );
        deviceUri = candidate;
        break;
      } on OnvifFailure catch (error) {
        if (last == null || _failurePriority(error) >= _failurePriority(last)) {
          last = error;
        }
        if (['NotAuthorized', 'autenticacao_onvif'].contains(error.code)) {
          await _clock(candidate);
          try {
            capabilities = await call(
              candidate,
              _device,
              'GetCapabilities',
              '<t:Category>All</t:Category>',
            );
            deviceUri = candidate;
            break;
          } on OnvifFailure catch (retry) {
            last = retry;
          }
        }
      }
    }
    if (capabilities == null || deviceUri == null) {
      throw last ??
          OnvifFailure(
            'onvif_nao_encontrado',
            'Nenhum serviço ONVIF foi confirmado nas portas testadas.',
          );
    }
    if (!manualOnly) await _clock(deviceUri);
    Uri? capabilityService(String name) {
      final node = _elements(capabilities!, name).firstOrNull;
      final address = node == null ? null : _address(node);
      if (address == null) return null;
      try {
        return endpoint(address);
      } on OnvifFailure catch (error) {
        onEvent({
          'operacao': 'endereco_anunciado_recusado',
          'servico': name,
          'codigo': error.code,
        });
        return null;
      }
    }

    final advertisedMedia = capabilityService('Media');
    final advertisedPtz = capabilityService('PTZ');
    final namespaceServices = <String, Uri>{};
    // GetCapabilities endpoints can be mislabeled by embedded firmware.
    // Match GetServices by the exact service namespace, never by path names.
    try {
      final services = await call(
        deviceUri,
        _device,
        'GetServices',
        '<t:IncludeCapability>false</t:IncludeCapability>',
      );
      final soapBody = _elements(services, 'Body').firstOrNull;
      final entries = (soapBody?.descendants ?? const <XmlNode>[])
          .whereType<XmlElement>()
          .where(
            (node) =>
                _direct(node, 'Namespace') != null && _address(node) != null,
          )
          .take(32);
      final declared = <Map<String, dynamic>>[];
      for (final service in entries) {
        final rawNs = _direct(service, 'Namespace')!;
        final ns = rawNs.replaceFirst(RegExp(r'/$'), '');
        final address = _address(service)!;
        Uri uri;
        try {
          uri = endpoint(address);
        } on OnvifFailure catch (error) {
          declared.add({
            'elemento': service.name.local,
            'namespace': _safeField(rawNs),
            'codigo': error.code,
          });
          continue;
        }
        declared.add({
          'elemento': service.name.local,
          'namespace': _safeField(rawNs),
          'reconhecido': [_media, _ptz].contains(ns),
          'endereco': _target(uri),
        });
        if ([_media, _ptz].contains(ns)) namespaceServices[ns] = uri;
      }
      onEvent({
        'operacao': 'estrutura_GetServices',
        'elementosCorpo':
            (soapBody?.descendants
                .whereType<XmlElement>()
                .map((e) => _safeField(e.name.local))
                .toSet()
                .take(48)
                .toList() ??
            const []),
        'entradas': declared,
        'reconhecidos': namespaceServices.length,
        'observacao':
            'Somente estrutura e campos de serviço; sem SOAP bruto ou cabeçalhos.',
      });
    } on OnvifFailure catch (error) {
      onEvent({
        'operacao': 'consulta_lista_servicos',
        'codigo': error.code,
        'observacao':
            'GetCapabilities e consultas alternativas continuam disponíveis.',
      });
    }
    final mediaUri = namespaceServices[_media] ?? advertisedMedia;
    final ptzUri = namespaceServices[_ptz] ?? advertisedPtz;
    if (ptzUri == null || mediaUri == null) {
      throw OnvifFailure(
        'ptz_nao_anunciado',
        'A câmera respondeu ONVIF, mas não anunciou serviços Media e PTZ válidos.',
      );
    }
    onEvent({
      'operacao': 'servicos_anunciados',
      'dispositivo': _target(deviceUri),
      if (advertisedMedia != null)
        'media_GetCapabilities': _target(advertisedMedia),
      if (advertisedPtz != null) 'ptz_GetCapabilities': _target(advertisedPtz),
      'media': _target(mediaUri),
      'ptz': _target(ptzUri),
      'servicosPorNamespace': namespaceServices.map(
        (ns, uri) => MapEntry(ns, _target(uri)),
      ),
    });
    final mediaEndpoints = <Uri>{mediaUri, ?advertisedMedia};
    XmlDocument? profiles;
    Uri? confirmedMedia;
    OnvifFailure? mediaError;
    for (final uri in mediaEndpoints) {
      try {
        profiles = await call(uri, _media, 'GetProfiles', '');
        confirmedMedia = uri;
        break;
      } on OnvifFailure catch (error) {
        mediaError = error;
        if ([
          'tls_verificacao',
          'NotAuthorized',
          'autenticacao_onvif',
          'cancelado',
        ].contains(error.code)) {
          rethrow;
        }
      }
    }
    if (profiles == null) {
      throw mediaError ??
          OnvifFailure(
            'perfis_indeterminados',
            'Não foi possível consultar os perfis de mídia.',
          );
    }
    final result = <PtzProfile>[];
    final endpoints = <Uri>{ptzUri};
    // Read-only alternatives on this same camera. A path name alone is never
    // evidence of support: require a valid response to the requested PTZ call.
    if (ptzUri.scheme == deviceUri.scheme) {
      endpoints.add(ptzUri.replace(port: deviceUri.port));
      endpoints.add(deviceUri.replace(path: '/onvif/ptz_service'));
      if (confirmedMedia != null && confirmedMedia.scheme == deviceUri.scheme) {
        endpoints.add(confirmedMedia);
      }
      if (advertisedPtz != null && advertisedPtz.scheme == deviceUri.scheme) {
        endpoints.add(advertisedPtz);
      }
      endpoints.add(deviceUri);
    }
    onEvent({
      'operacao': 'enderecos_candidatos_ptz',
      'enderecos': endpoints.map(_target).toList(),
      'apenasLeitura': true,
    });
    // Explicitly requested experimental driver, separate from discovered
    // capabilities. No movement or Stop is sent by this inspection.
    final manualEndpoints = <Uri>{
      ptzUri,
      deviceUri.replace(path: '/onvif/ptz_service'),
      ...endpoints,
    };
    var manualIndex = 0;
    for (final profile in _elements(profiles, 'Profiles').take(8)) {
      final token = profile.getAttribute('token');
      if (token == null ||
          token.isEmpty ||
          _elements(profile, 'PTZConfiguration').isEmpty) {
        continue;
      }
      manualIndex++;
      for (final uri in manualEndpoints) {
        manualCandidates.add(
          PtzProfile(
            token,
            'Perfil $manualIndex · teste ${manualEndpoints.toList().indexOf(uri) + 1}',
            uri,
            VelocitySpace('', -1, 1, -1, 1, fraction: .1),
            null,
            capabilitySource: 'compatibilidade_yoosee_manual',
          ),
        );
      }
    }
    if (manualOnly) {
      if (manualCandidates.isEmpty) {
        throw OnvifFailure(
          'sem_configuracao_ptz',
          'Os perfis recebidos não incluíram configuração PTZ para este teste.',
        );
      }
      onEvent({
        'operacao': 'perfis_manuais_recebidos',
        'candidatos': manualCandidates.length,
        'capacidadesConsultadas': false,
        'movimentoVerificado': false,
      });
      return List.of(manualCandidates);
    }
    final readResults = <String, ({XmlDocument document, Uri uri})>{};
    final readFailures = <String, OnvifFailure>{};
    final budget = Stopwatch()..start();
    Future<({XmlDocument document, Uri uri})> read(
      String operation,
      String body,
    ) async {
      OnvifFailure? failure;
      for (final uri in endpoints) {
        if (_closed || budget.elapsed > capabilityBudget) break;
        final key = '$uri|$operation|$body';
        if (readResults.containsKey(key)) return readResults[key]!;
        if (readFailures.containsKey(key)) {
          failure = readFailures[key];
          continue;
        }
        try {
          final result = (
            document: await call(uri, _ptz, operation, body),
            uri: uri,
          );
          readResults[key] = result;
          return result;
        } on OnvifFailure catch (error) {
          readFailures[key] = error;
          failure = error;
          if ([
            'tls_verificacao',
            'endpoint_recusado',
            'cancelado',
            'NotAuthorized',
            'autenticacao_onvif',
          ].contains(error.code)) {
            rethrow;
          }
        }
      }
      throw failure ??
          OnvifFailure(
            'prazo_consulta_ptz',
            'Prazo da verificação PTZ encerrado.',
          );
    }

    final nodeCache = <String, ({XmlDocument document, Uri uri})>{};
    var configuredProfiles = 0, unknownProfiles = 0;
    for (final profile in _elements(profiles, 'Profiles').take(8)) {
      final configNode = _elements(profile, 'PTZConfiguration').firstOrNull;
      final token = profile.getAttribute('token');
      final configuration = configNode?.getAttribute('token');
      if (token == null || configuration == null) continue;
      configuredProfiles++;
      final nodeToken = _text(configNode!, 'NodeToken');
      final name = _text(profile, 'Name') ?? 'Perfil ${result.length + 1}';
      final defaultPan = _text(
        configNode,
        'DefaultContinuousPanTiltVelocitySpace',
      );
      final defaultZoom = _text(
        configNode,
        'DefaultContinuousZoomVelocitySpace',
      );
      onEvent({
        'operacao': 'declaracao_ptz_no_perfil',
        'perfilIndice': configuredProfiles,
        'nodeTokenPresente': nodeToken != null,
        'espacoPanTilt': _safeField(defaultPan),
        'espacoZoom': _safeField(defaultZoom),
      });

      ({XmlDocument document, Uri uri})? capabilities;
      var source = 'GetConfigurationOptions';
      try {
        capabilities = await read(
          'GetConfigurationOptions',
          '<t:ConfigurationToken>${_xml(configuration)}</t:ConfigurationToken>',
        );
      } on OnvifFailure catch (error) {
        onEvent({'operacao': 'opcoes_do_perfil', 'codigo': error.code});
      }
      var pan = capabilities == null
          ? null
          : _space(capabilities.document, 'ContinuousPanTiltVelocitySpace');
      var zoom = capabilities == null
          ? null
          : _space(capabilities.document, 'ContinuousZoomVelocitySpace');
      if (pan == null && zoom == null) {
        // Capabilities can also be advertised by the profile's PTZ node.
        // Never borrow another node's ranges or invent a generic velocity space.
        final cacheKey = nodeToken ?? '[unico]';
        var nodes = nodeCache[cacheKey];
        if (nodes == null && nodeToken != null) {
          try {
            nodes = await read(
              'GetNode',
              '<t:NodeToken>${_xml(nodeToken)}</t:NodeToken>',
            );
          } on OnvifFailure catch (error) {
            onEvent({'operacao': 'node_do_perfil', 'codigo': error.code});
          }
        }
        if (nodes == null) {
          try {
            nodes = await read('GetNodes', '');
          } on OnvifFailure catch (error) {
            onEvent({'operacao': 'nodes_ptz', 'codigo': error.code});
          }
        }
        if (nodes != null) {
          final all = nodes.document.descendants
              .whereType<XmlElement>()
              .where(
                (e) =>
                    ['PTZNode', 'PTZNodes'].contains(e.name.local) &&
                    e.getAttribute('token') != null,
              )
              .toList();
          final matching = nodeToken == null
              ? (all.length == 1 ? all.single : null)
              : all
                    .where((e) => e.getAttribute('token') == nodeToken)
                    .firstOrNull;
          if (matching != null) {
            nodeCache[cacheKey] = nodes;
            final nodePan = _space(matching, 'ContinuousPanTiltVelocitySpace');
            final nodeZoom = _space(matching, 'ContinuousZoomVelocitySpace');
            if (nodePan != null || nodeZoom != null || capabilities == null) {
              pan = nodePan;
              zoom = nodeZoom;
              capabilities = nodes;
              source = 'PTZNode';
            }
          } else {
            onEvent({
              'operacao': 'node_do_perfil',
              'codigo': 'node_nao_correlacionado',
              'quantidadeNodes': all.length,
            });
          }
        }
      }
      if (capabilities == null) {
        const genericPan =
            'http://www.onvif.org/ver10/tptz/PanTiltSpaces/VelocityGenericSpace';
        const genericZoom =
            'http://www.onvif.org/ver10/tptz/ZoomSpaces/VelocityGenericSpace';
        // Only explicitly declared standardized generic spaces. The normalized
        // limits come from ONVIF PTZ 5.7.3, not guessed vendor capabilities.
        final declaredPan = defaultPan == genericPan
            ? VelocitySpace(genericPan, -1, 1, -1, 1, fraction: .1)
            : null;
        final declaredZoom = defaultZoom == genericZoom
            ? VelocitySpace(genericZoom, -1, 1, 0, 0, fraction: .1)
            : null;
        if (declaredPan != null || declaredZoom != null) {
          result.add(
            PtzProfile(
              token,
              name,
              ptzUri,
              declaredPan,
              declaredZoom,
              capabilitySource: 'espaco_generico_declarado_no_perfil',
            ),
          );
          onEvent({
            'operacao': 'teste_ptz_disponivel',
            'perfilIndice': configuredProfiles,
            'fonte': 'declaracao_explicita_do_perfil',
            'limitesConsultados': false,
            'ativacaoManualObrigatoria': true,
            'movimentoVerificado': false,
          });
        } else {
          unknownProfiles++;
        }
        continue;
      }
      result.add(
        PtzProfile(
          token,
          name,
          capabilities.uri,
          pan,
          zoom,
          capabilitySource: source,
        ),
      );
      onEvent({
        'operacao': 'capacidades_do_perfil',
        'perfilIndice': configuredProfiles,
        ..._target(capabilities.uri),
        'fonte': source,
        'giroInclinacao': pan != null,
        'zoom': zoom != null,
        if (pan != null)
          'limitesGiroInclinacao': [pan.xMin, pan.xMax, pan.yMin, pan.yMax],
        if (zoom != null) 'limitesZoom': [zoom.xMin, zoom.xMax],
      });
    }
    onEvent({
      'operacao': 'resumo_perfis',
      'comConfiguracaoPtz': configuredProfiles,
      'capacidadesConsultadas': result.where((p) => !p.requiresTest).length,
      'perfisComTesteDeclarado': result.where((p) => p.requiresTest).length,
      'capacidadesIndeterminadas': unknownProfiles,
    });
    if (result.isEmpty) {
      if (configuredProfiles > 0) {
        throw OnvifFailure(
          'ptz_capacidades_indeterminadas',
          'A câmera forneceu perfis PTZ, mas não confirmou as opções de movimento. Isso não significa que ela não tenha controle. Consulte o diagnóstico.',
        );
      }
      throw OnvifFailure(
        'sem_configuracao_ptz',
        'Os perfis recebidos não incluíram configuração PTZ.',
      );
    }
    return result;
  }

  VelocitySpace? _space(XmlNode document, String name) {
    for (final node in _elements(document, name)) {
      final uri = _text(node, 'URI');
      final xRange = _elements(node, 'XRange').firstOrNull;
      final yRange = _elements(node, 'YRange').firstOrNull;
      double? number(XmlElement? range, String tag) =>
          range == null ? null : double.tryParse(_text(range, tag) ?? '');
      final xMin = number(xRange, 'Min'), xMax = number(xRange, 'Max');
      final yMin = number(yRange, 'Min') ?? 0,
          yMax = number(yRange, 'Max') ?? 0;
      if (uri == null ||
          xMin == null ||
          xMax == null ||
          ![xMin, xMax, yMin, yMax].every((v) => v.isFinite) ||
          xMin > 0 ||
          xMax < 0 ||
          xMin >= xMax ||
          (name.contains('PanTilt') &&
              (yMin > 0 || yMax < 0 || yMin >= yMax))) {
        continue;
      }
      return VelocitySpace(uri, xMin, xMax, yMin, yMax);
    }
    return null;
  }

  Future<void> move(PtzProfile profile, int x, int y, int zoom) async {
    if (profile.manualYoosee) {
      if (!_manualMinimal.containsKey(profile.endpoint) ||
          !_manualZeroStop.containsKey(profile.endpoint)) {
        throw OnvifFailure(
          'teste_nao_ativado',
          'Ative o teste manual antes de mover.',
        );
      }
      if (zoom != 0 || (x == 0 && y == 0)) return;
      final hold = _manualHold.contains(profile.endpoint);
      onEvent({
        'operacao': 'movimento_manual_solicitado',
        'x': x.sign,
        'y': y.sign,
        'velocidadeSolicitada': .1,
        'timeoutCameraMs': hold ? 2000 : 300,
        'modoPressao': hold,
        'capacidadesConsultadas': false,
        'movimentoVerificado': false,
      });
      final child = _manualMinimal[profile.endpoint]! ? 'ptz' : 'tt';
      final body =
          '<t:ProfileToken>${_xml(profile.token)}</t:ProfileToken>'
          '<t:Velocity><$child:PanTilt x="${x.sign * .1}" y="${y.sign * .1}"/></t:Velocity>'
          '<t:Timeout>${hold ? 'PT2S' : 'PT0.3S'}</t:Timeout>';
      await _manualCall(profile, 'ContinuousMove', body);
      return;
    }
    String velocity = '';
    if ((x != 0 || y != 0) && profile.panTilt != null) {
      final s = profile.panTilt!;
      velocity +=
          '<tt:PanTilt x="${s.x(x)}" y="${s.y(y)}" space="${_xml(s.uri)}"/>';
    }
    if (zoom != 0 && profile.zoom != null) {
      final s = profile.zoom!;
      velocity += '<tt:Zoom x="${s.x(zoom)}" space="${_xml(s.uri)}"/>';
    }
    if (velocity.isEmpty) {
      throw OnvifFailure(
        'movimento_indisponivel',
        'Esse movimento não foi anunciado pela câmera.',
      );
    }
    onEvent({
      'operacao': 'movimento_solicitado',
      'x': x,
      'y': y,
      'zoom': zoom,
      'timeoutCameraMs': 600,
    });
    // Bounded pulses: even if the phone loses Wi-Fi, a conforming camera stops.
    await call(
      profile.endpoint,
      _ptz,
      'ContinuousMove',
      '<t:ProfileToken>${_xml(profile.token)}</t:ProfileToken><t:Velocity>$velocity</t:Velocity><t:Timeout>PT0.6S</t:Timeout>',
    );
  }

  Future<void> stop(PtzProfile profile) async {
    if (profile.manualYoosee) {
      if (_manualZeroStop[profile.endpoint] == true) {
        await _stopWithZero(profile);
        return;
      }
      await _manualCall(
        profile,
        'Stop',
        '<t:ProfileToken>${_xml(profile.token)}</t:ProfileToken><t:PanTilt>true</t:PanTilt><t:Zoom>false</t:Zoom>',
      );
      return;
    }
    await call(
      profile.endpoint,
      _ptz,
      'Stop',
      '<t:ProfileToken>${_xml(profile.token)}</t:ProfileToken><t:PanTilt>${profile.panTilt != null}</t:PanTilt><t:Zoom>${profile.zoom != null}</t:Zoom>',
    );
  }

  Future<XmlDocument> _manualCall(
    PtzProfile profile,
    String operation,
    String body,
  ) => _manualMinimal[profile.endpoint] == false
      ? call(profile.endpoint, _ptz, operation, body)
      : _request(
          profile.endpoint,
          _ptz,
          operation,
          body,
          authenticated: true,
          soapPrefix: 'ptz',
          minimal: true,
        );

  String? manualStopMethod(PtzProfile profile) =>
      !_manualZeroStop.containsKey(profile.endpoint)
      ? null
      : _manualZeroStop[profile.endpoint]!
      ? 'ContinuousMove_velocidade_zero'
      : 'Stop';

  void setManualHold(PtzProfile profile, bool enabled) {
    if (enabled) {
      if (!_manualZeroStop.containsKey(profile.endpoint)) {
        throw OnvifFailure(
          'teste_nao_ativado',
          'Confirme a parada antes de ativar o controle por pressão.',
        );
      }
      _manualHold.add(profile.endpoint);
    } else {
      _manualHold.remove(profile.endpoint);
    }
  }

  Future<void> _stopWithZero(PtzProfile profile) async {
    final child = _manualMinimal[profile.endpoint]! ? 'ptz' : 'tt';
    onEvent({
      'operacao': 'parada_alternativa_solicitada',
      'metodo': 'ContinuousMove',
      'x': 0.0,
      'y': 0.0,
      ..._target(profile.endpoint),
    });
    // ONVIF PTZ 5.3.3: zero velocity stops each specified axis. No nonzero
    // velocity and no movement timeout is needed for this stop operation.
    await _manualCall(
      profile,
      'ContinuousMove',
      '<t:ProfileToken>${_xml(profile.token)}</t:ProfileToken>'
          '<t:Velocity><$child:PanTilt x="0.0" y="0.0"/></t:Velocity>',
    );
  }

  bool? manualMinimalFormat(PtzProfile profile) =>
      _manualMinimal[profile.endpoint];

  Future<void> prepareManual(
    PtzProfile profile, {
    bool? preferredMinimal,
    bool? preferredZeroStop,
  }) async {
    if (!profile.manualYoosee) return;
    // Preflight sends stop operations only: Stop, or ContinuousMove with zero
    // velocity if Stop is refused. Never probe nonzero movement.
    _manualMinimal.remove(profile.endpoint);
    _manualZeroStop.remove(profile.endpoint);
    _manualHold.remove(profile.endpoint);
    OnvifFailure? last;
    for (final trial in <({bool minimal, bool zero})>{
      if (preferredMinimal != null && preferredZeroStop != null)
        (minimal: preferredMinimal, zero: preferredZeroStop),
      (minimal: true, zero: false),
      (minimal: false, zero: false),
      (minimal: false, zero: true),
      (minimal: true, zero: true),
    }) {
      final minimal = trial.minimal;
      _manualMinimal[profile.endpoint] = minimal;
      onEvent({
        'operacao': 'parada_previa_tentativa',
        ..._target(profile.endpoint),
        'formato': minimal ? 'yoosee_minimo' : 'onvif_padrao',
        'metodoParada': trial.zero ? 'ContinuousMove_velocidade_zero' : 'Stop',
      });
      try {
        if (trial.zero) {
          await _stopWithZero(profile);
        } else {
          await stop(profile);
        }
        _manualZeroStop[profile.endpoint] = trial.zero;
        onEvent({
          'operacao': 'parada_previa_confirmada',
          ..._target(profile.endpoint),
          'formato': minimal ? 'yoosee_minimo' : 'onvif_padrao',
          'metodoParada': manualStopMethod(profile),
          'movimentoVerificado': false,
        });
        return;
      } on OnvifFailure catch (error) {
        last = error;
        if ([
          'NotAuthorized',
          'autenticacao_onvif',
          'tls_verificacao',
          'cancelado',
        ].contains(error.code)) {
          break;
        }
      }
    }
    _manualMinimal.remove(profile.endpoint);
    throw OnvifFailure(
      'parada_previa_falhou',
      'A câmera não confirmou Parar neste teste (${last?.code}). Escolha outro teste e tente ativar novamente.',
    );
  }

  void close() {
    _closed = true;
    _http.close(force: true);
  }
}
