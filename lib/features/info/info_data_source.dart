import 'package:meal_client/core/network/http_client.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/features/info/info_refresh_service.dart';

Future<AppInfo> fetchAppInfo({RawInfoFetcher fetch = fetchRawString}) async {
  return InfoRefreshService(
    fetchRaw: fetch,
    throwOnCacheWriteFailure: false,
  ).refreshInfo();
}
