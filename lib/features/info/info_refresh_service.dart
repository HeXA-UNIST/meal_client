import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/network/http_client.dart';
import 'package:meal_client/core/widget_shared_storage.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/features/info/info_cache.dart';

typedef RawInfoFetcher =
    Future<ConditionalResponse> Function(String url, {String? ifModifiedSince});
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
       _fetchRaw = fetchRaw ?? fetchRawConditional,
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
    final res = await _fetchRaw(
      ApiConstants.infoEndpoint,
      ifModifiedSince: await _readCachedLastModified(),
    );

    if (res.statusCode == 304) {
      // 서버가 방금 "변경 없음"을 확인해줬다. /v2/info의 last_modified는 워커
      // 배포 버전이고 공지·운영시간은 배포로만 바뀌므로, 캐시된 info.json을
      // 그대로 파싱해 돌려줘도 안전하다.
      try {
        final info = _parseValidRawInfo(await _cache.readRawInfoJson());
        debugPrint('[BapU] info 304 - 캐시 유지');
        return info;
      } catch (_) {
        // If-Modified-Since를 보냈는데 그 사이 캐시가 사라졌거나 손상된 드문
        // 경우다. 조건부 헤더 없이 한 번 더 받아 캐시를 복구한다.
        final retry = await _fetchRaw(ApiConstants.infoEndpoint);
        final rawInfo = retry.body!;
        final info = _parseValidRawInfo(rawInfo);
        await _commitRawInfoJson(rawInfo, requestStartedAt);
        return info;
      }
    }

    final rawInfo = res.body!;
    final info = _parseValidRawInfo(rawInfo);
    await _commitRawInfoJson(rawInfo, requestStartedAt);
    return info;
  }

  /// 캐시된 info.json 본문의 last_modified 값. 캐시가 없거나 값이 없으면 null을
  /// 돌려주고, 그 경우 조건부 요청 없이 전체 응답을 받는다.
  Future<String?> _readCachedLastModified() async {
    try {
      final decoded = jsonDecode(await _cache.readRawInfoJson());
      if (decoded is! Map<String, dynamic>) return null;
      final value = decoded['last_modified'];
      return value is String && value.isNotEmpty ? value : null;
    } catch (_) {
      return null;
    }
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
