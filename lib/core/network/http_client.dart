// 요청마다 클라이언트를 새로 만들지 않고 앱 동안 재사용한다.
import 'package:http/http.dart';

import 'package:meal_client/core/network/platform_http_client.dart';

final Client appHttpClient = createPlatformHttpClient();

Future<String> fetchRawString(String url) async {
  final response = await appHttpClient
      .get(Uri.parse(url))
      .timeout(const Duration(seconds: 10));
  if (response.statusCode != 200) {
    // HttpException은 dart:io 전용이므로 모든 플랫폼에서 사용 가능한 Exception으로 대체
    throw Exception("HTTP ${response.statusCode}: Response Error");
  }

  return response.body;
}
