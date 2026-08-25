import 'dart:convert';

import 'package:meal_client/core/network/http_client.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/features/info/info_cache.dart';
import 'package:meal_client/features/info/info_refresh_service.dart';

Future<AppInfo> fetchAppInfo({RawInfoFetcher fetch = fetchRawString}) async {
  return InfoRefreshService(
    fetchRaw: fetch,
    throwOnCacheWriteFailure: false,
  ).refreshInfo();
}

/// 마지막으로 저장된 info.json을 읽어 파싱한다.
///
/// 식단 카드의 운영시간이 매 실행마다 네트워크 왕복을 기다리지 않도록,
/// 화면을 먼저 채우는 용도로만 쓴다. 캐시가 없거나 손상됐으면 null을 돌려주고
/// 호출 측이 네트워크 응답을 기다리게 한다.
Future<AppInfo?> readCachedAppInfo({InfoCache? cache}) async {
  try {
    final raw = await (cache ?? InfoCache()).readRawInfoJson();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    return AppInfo.fromJson(decoded);
  } catch (_) {
    return null;
  }
}
