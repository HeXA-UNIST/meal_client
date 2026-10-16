// 요청마다 클라이언트를 새로 만들지 않고 앱 동안 재사용한다.
import 'package:http/http.dart';

import 'package:meal_client/core/network/platform_http_client.dart';

final Client appHttpClient = createPlatformHttpClient();

Future<String> fetchRawString(String url) async {
  final response = await appHttpClient
      .get(Uri.parse(url))
      .timeout(const Duration(seconds: 10));
  if (response.statusCode != 200) {
    throw createHttpException(response.statusCode);
  }

  return response.body;
}

/// 조건부 GET 결과. [statusCode]가 304면 [body]는 null이고 호출자는 캐시를 쓴다.
typedef ConditionalResponse = ({int statusCode, String? body});

typedef ConditionalFetcher = Future<ConditionalResponse> Function(
  String url, {
  String? ifNoneMatch,
});

/// 네이티브에서는 응답 JSON의 etag를 [ifNoneMatch]로 보내고 304를 처리한다.
/// 웹의 `/v2/info`는 no-cache로 브라우저에 재검증과 응답 본문 재사용을 맡긴다.
Future<ConditionalResponse> fetchRawConditional(
  String url, {
  String? ifNoneMatch,
}) => fetchPlatformRawConditional(
  appHttpClient,
  url,
  ifNoneMatch: ifNoneMatch,
).timeout(const Duration(seconds: 10));
