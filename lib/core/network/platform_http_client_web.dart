import 'dart:js_interop';

import 'package:http/http.dart';
import 'package:web/web.dart' as web;

Exception createHttpException(int statusCode) =>
    Exception("HTTP $statusCode: Response Error");

// 웹에서는 package:http의 기본 Client()가
// 브라우저 환경에 맞는 구현을 자동으로 선택한다.
Client createPlatformHttpClient() => Client();

// 식단은 브라우저 HTTP 캐시를 읽거나 저장하지 않고 매번 요청한다.
Future<String> fetchPlatformRawString(Client client, String url) =>
    _fetchRawString(url, cache: 'no-store');

Future<({int statusCode, String? body})> fetchPlatformRawConditional(
  Client client,
  String url, {
  String? ifModifiedSince,
}) async {
  // 웹은 본문과 검증자를 브라우저가 관리한다. 조건부 헤더를 직접 넣지 않아야
  // 서버의 304 응답을 브라우저가 저장된 본문이 있는 200 응답으로 제공한다.
  final body = await _fetchRawString(url, cache: 'no-cache');
  return (statusCode: 200, body: body);
}

Future<String> _fetchRawString(String url, {required String cache}) async {
  final response = await web.window
      .fetch(url.toJS, web.RequestInit(method: 'GET', cache: cache))
      .toDart;
  if (response.status != 200) {
    throw createHttpException(response.status);
  }
  return (await response.text().toDart).toDart;
}
