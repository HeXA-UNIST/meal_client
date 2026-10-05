import 'dart:js_interop';

import 'package:http/http.dart';
import 'package:web/web.dart' as web;

Exception createHttpException(int statusCode) =>
    Exception("HTTP $statusCode: Response Error");

// 웹에서는 package:http의 기본 Client()가
// 브라우저 환경에 맞는 구현을 자동으로 선택한다.
Client createPlatformHttpClient() => Client();

Future<String> fetchPlatformRawString(Client client, String url) async {
  // 식단은 브라우저 HTTP 캐시를 읽거나 저장하지 않고 매번 요청한다.
  // 조건부 GET을 사용하는 공지 요청은 기존 Client를 그대로 사용한다.
  final response = await web.window
      .fetch(url.toJS, web.RequestInit(method: 'GET', cache: 'no-store'))
      .toDart;
  if (response.status != 200) {
    throw createHttpException(response.status);
  }
  return (await response.text().toDart).toDart;
}
