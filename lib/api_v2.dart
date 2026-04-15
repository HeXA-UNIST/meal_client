// dart:io는 웹에서 사용 불가하므로 제거하고, HttpException 대신 기본 Exception 사용
import 'dart:convert';

import 'package:http/http.dart';

import 'constants.dart';
import 'platform_http_client.dart';

// 요청마다 클라이언트를 새로 만들지 않고 앱 동안 재사용한다.
final Client _httpClient = createPlatformHttpClient();

Future<String> _fetchRawString(String url) async {
  final response = await _httpClient
      .get(Uri.parse(url))
      .timeout(const Duration(seconds: 10));
  if (response.statusCode != 200) {
    // HttpException은 dart:io 전용이므로 모든 플랫폼에서 사용 가능한 Exception으로 대체
    throw Exception("HTTP ${response.statusCode}: Response Error");
  }

  return response.body;
}

Future<String> fetchRawMeal() async =>
    await _fetchRawString(ApiConstants.mealEndpoint);

Future<String> fetchRawAnnouncement() async =>
    await _fetchRawString(ApiConstants.noticeEndpoint);

String parseRawAnnouncement(String rawAnnouncement) {
  final map = jsonDecode(rawAnnouncement) as Map<String, dynamic>;
  return map["content"] as String;
}
