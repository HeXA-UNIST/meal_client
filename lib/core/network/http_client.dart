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

/// [ifModifiedSince]가 있으면 If-Modified-Since 헤더를 실어 조건부 GET을 보낸다.
/// 304를 정상 결과로 돌려주고, 그 밖의 비정상 상태 코드는 예외로 던진다.
///
/// 현재 이 조건부 요청 최적화는 `/v2/info` 엔드포인트에만 적용한다. `/v2/info`는
/// Last-Modified만 주고 응답 본문에 같은 값(`last_modified`)을 담아 되돌려 보낼
/// 값을 별도 저장 없이 캐시에서 그대로 읽을 수 있다. `/v2/menu` 계열은 ETag /
/// If-None-Match를 쓰며 아직 이 경로로 옮기지 않았다.
Future<ConditionalResponse> fetchRawConditional(
  String url, {
  String? ifModifiedSince,
}) async {
  final response = await appHttpClient
      .get(
        Uri.parse(url),
        headers: ifModifiedSince == null
            ? null
            : {'If-Modified-Since': ifModifiedSince},
      )
      .timeout(const Duration(seconds: 10));

  if (response.statusCode == 304) {
    return (statusCode: 304, body: null);
  }
  if (response.statusCode != 200) {
    throw createHttpException(response.statusCode);
  }

  return (statusCode: 200, body: response.body);
}
