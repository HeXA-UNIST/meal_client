import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/network/http_client.dart';
import 'package:meal_client/core/widget_shared_storage.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/features/info/info_cache.dart';

typedef RawInfoFetcher = Future<String> Function(String url);
typedef InfoCacheWriteLock =
    Future<void> Function(Future<void> Function() action);

class InfoCacheWriteException implements Exception {
  const InfoCacheWriteException(this.cause);

  final Object cause;

  @override
  String toString() => 'InfoCacheWriteException: $cause';
}

class InfoRefreshService {
  InfoRefreshService({
    InfoCache? cache,
    RawInfoFetcher? fetchRaw,
    DateTime Function()? clock,
    InfoCacheWriteLock? lockCache,
    bool throwOnCacheWriteFailure = false,
  }) : _cache = cache ?? InfoCache(),
       _fetchRaw = fetchRaw ?? fetchRawString,
       _clock = clock ?? DateTime.now,
       _lockCache =
           lockCache ??
           (cache == null
               ? (action) =>
                     withSharedWidgetFileLock(StorageKeys.infoCacheFile, action)
               : (action) => action()),
       _throwOnCacheWriteFailure = throwOnCacheWriteFailure;

  final InfoCache _cache;
  final RawInfoFetcher _fetchRaw;
  final DateTime Function() _clock;
  final InfoCacheWriteLock _lockCache;
  final bool _throwOnCacheWriteFailure;

  Future<AppInfo> refreshInfo() async {
    final requestStartedAt = _clock();
    final rawInfo = await _fetchRaw(ApiConstants.infoEndpoint);
    final info = _parseValidRawInfo(rawInfo);
    await _commitRawInfoJson(rawInfo, requestStartedAt);
    return info;
  }

  AppInfo _parseValidRawInfo(String rawInfo) {
    final decoded = jsonDecode(rawInfo);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Invalid info API response');
    }

    return AppInfo.fromJson(decoded);
  }

  /// 먼저 시작한 요청이 늦게 끝나 최신 info cache를 되돌리는 것을 막는다.
  Future<void> _commitRawInfoJson(
    String rawInfo,
    DateTime requestStartedAt,
  ) async {
    try {
      await _lockCache(() async {
        try {
          final currentUpdatedAt = await _cache.getRawInfoUpdatedAt();
          if (currentUpdatedAt.isAfter(requestStartedAt)) {
            debugPrint('[BapU] discarded stale info response');
            return;
          }
        } catch (_) {
          // cache가 아직 없거나 timestamp를 읽지 못하면 검증된 응답으로 복구한다.
        }
        await _cache.writeRawInfoJson(rawInfo);
      });
    } catch (e, stackTrace) {
      if (_throwOnCacheWriteFailure) {
        Error.throwWithStackTrace(InfoCacheWriteException(e), stackTrace);
      }
      debugPrint('[BapU] info cache write failed: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
