import 'dart:convert';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/network/http_client.dart';

Future<String> fetchRawAnnouncement() =>
    fetchRawString(ApiConstants.noticeEndpoint);

String parseRawAnnouncement(String raw) {
  final map = jsonDecode(raw) as Map<String, dynamic>;
  return map["content"] as String;
}
