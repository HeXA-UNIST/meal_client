import 'package:http/http.dart';

Exception createHttpException(int statusCode) =>
    Exception("HTTP $statusCode: Response Error");

// 웹에서는 package:http의 기본 Client()가
// 브라우저 환경에 맞는 구현을 자동으로 선택한다.
Client createPlatformHttpClient() => Client();

Future<({int statusCode, String? body})> fetchPlatformRawConditional(
  Client client,
  String url, {
  String? ifNoneMatch,
}) async {
  // 웹은 본문과 검증자를 브라우저가 관리한다. 조건부 헤더를 직접 넣지 않아야
  // 서버의 304 응답을 브라우저가 저장된 본문이 있는 200 응답으로 제공한다.
  final response = await client.get(Uri.parse(url));
  if (response.statusCode != 200) {
    throw createHttpException(response.statusCode);
  }
  return (statusCode: 200, body: response.body);
}
