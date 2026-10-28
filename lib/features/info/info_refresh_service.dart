import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/network/http_client.dart';
import 'package:meal_client/core/widget_shared_storage.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/features/info/info_cache.dart';

typedef InfoCacheWriteLock = Future<void> Function(
  Future<void> Function() action,
);

class InfoCacheWriteException implements Exception {
  const InfoCacheWriteException(this.cause);

  final Object cause;

  @override
  String toString() => 'InfoCacheWriteException: $cause';
}

class InfoRefreshService {
  InfoRefreshService({
    InfoCache? cache,
    ConditionalFetcher? fetchRaw,
    InfoCacheWriteLock? lockCache,
    this._throwOnCacheWriteFailure = false,
  }) : _cache = cache ?? InfoCache(),
       _fetchRaw = fetchRaw ?? fetchRawConditional,
       _lockCache =
           lockCache ??
           (cache == null
               ? (action) =>
                     withSharedWidgetFileLock(StorageKeys.infoCacheFile, action)
               : (action) => action());

  final InfoCache _cache;
  final ConditionalFetcher _fetchRaw;
  final InfoCacheWriteLock _lockCache;
  final bool _throwOnCacheWriteFailure;

  Future<AppInfo> refreshInfo() async {
    return (await refreshInfoWithStatus()).info;
  }

  Future<({AppInfo info, bool cacheReady})> refreshInfoWithStatus() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final before = await _readCachedRaw();
      final res = await _fetchRaw(
        ApiConstants.infoEndpoint,
        ifNoneMatch: _cachedEtag(before),
      );
      String raw;
      var revalidated = false;
      if (res.statusCode == 304) {
        try {
          if (before == null || _cachedEtag(before) == null) {
            throw const FormatException('Missing info snapshot');
          }
          _parseValidRawInfo(before);
          raw = before;
          revalidated = true;
        } catch (_) {
          // 304는 보낸 ETag의 본문과만 결합한다. 본문이 없으면 한 번 복구한다.
          raw = (await _fetchRaw(ApiConstants.infoEndpoint)).body!;
        }
      } else {
        raw = res.body!;
      }
      final info = _parseValidRawInfo(raw);
      final committed = await _commitRawInfoJson(
        raw,
        before,
        revalidated: revalidated,
      );
      if (!committed.conflict) {
        return (info: info, cacheReady: committed.cacheReady);
      }
    }
    final current = await _readCachedRaw();
    if (current == null) throw StateError('Info cache changed during refresh');
    return (info: _parseValidRawInfo(current), cacheReady: false);
  }

  Future<String?> _readCachedRaw() async {
    try {
      return await _cache.readRawInfoJson();
    } catch (_) {
      return null;
    }
  }

  String? _cachedEtag(String? raw) {
    try {
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final value = decoded['etag'];
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

  /// 스냅샷이 바뀌면 호출자가 잠금 밖에서 다시 재검증한다.
  Future<({bool conflict, bool cacheReady})> _commitRawInfoJson(
    String rawInfo,
    String? expectedRaw, {
    required bool revalidated,
  }) async {
    var accepted = false;
    try {
      await _lockCache(() async {
        if (await _readCachedRaw() != expectedRaw) return;
        if (!revalidated) await _cache.writeRawInfoJson(rawInfo);
        accepted = true;
      });
      return (conflict: !accepted, cacheReady: accepted);
    } catch (e, stackTrace) {
      if (_throwOnCacheWriteFailure) {
        Error.throwWithStackTrace(InfoCacheWriteException(e), stackTrace);
      }
      debugPrint('[BapU] info cache write failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      // 실제 저장 실패 때 응답을 표시하는 기존 비엄격 모드 정책은 유지한다.
      return (conflict: false, cacheReady: false);
    }
  }
}
