// 요청마다 클라이언트를 새로 만들지 않고 앱 동안 재사용한다.
import 'package:http/http.dart';

import 'package:meal_client/core/network/platform_http_client.dart';

final Client appHttpClient = createPlatformHttpClient();

Future<String> fetchRawString(String url) => fetchPlatformRawString(
  appHttpClient,
  url,
).timeout(const Duration(seconds: 10));

/// 조건부 GET 결과. [statusCode]가 304면 [body]는 null이고 호출자는 캐시를 쓴다.
typedef ConditionalResponse = ({int statusCode, String? body});

/// 네이티브에서는 [ifModifiedSince]를 조건부 헤더로 보내고 304를 처리한다.
/// 웹에서는 no-cache로 브라우저에 재검증과 응답 본문 재사용을 맡긴다.
///
/// 현재 이 조건부 요청 최적화는 `/v2/info` 엔드포인트에만 적용한다. `/v2/info`는
/// Last-Modified만 주고 응답 본문에 같은 값(`last_modified`)을 담아 되돌려 보낼
/// 값을 별도 저장 없이 캐시에서 그대로 읽을 수 있다. `/v2/menu` 계열은 ETag /
/// If-None-Match를 쓰며 아직 이 경로로 옮기지 않았다.
Future<ConditionalResponse> fetchRawConditional(
  String url, {
  String? ifModifiedSince,
}) => fetchPlatformRawConditional(
  appHttpClient,
  url,
  ifModifiedSince: ifModifiedSince,
).timeout(const Duration(seconds: 10));
