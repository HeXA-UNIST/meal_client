import 'dart:convert';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/network/http_client.dart';
import 'package:meal_client/features/info/app_info.dart';

typedef RawInfoFetcher = Future<String> Function(String url);

Future<AppInfo> fetchAppInfo({
  RawInfoFetcher fetch = fetchRawString,
}) async {
  final raw = await fetch(ApiConstants.infoEndpoint);
  return AppInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
