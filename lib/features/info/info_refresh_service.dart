import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/network/http_client.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/features/info/info_cache.dart';

typedef RawInfoFetcher = Future<String> Function(String url);

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
    bool throwOnCacheWriteFailure = false,
  }) : _cache = cache ?? InfoCache(),
       _fetchRaw = fetchRaw ?? fetchRawString,
       _throwOnCacheWriteFailure = throwOnCacheWriteFailure;

  final InfoCache _cache;
  final RawInfoFetcher _fetchRaw;
  final bool _throwOnCacheWriteFailure;

  Future<AppInfo> refreshInfo() async {
    final rawInfo = await _fetchRaw(ApiConstants.infoEndpoint);
    final info = _parseValidRawInfo(rawInfo);
    await _writeRawInfoJson(rawInfo);
    return info;
  }

  AppInfo _parseValidRawInfo(String rawInfo) {
    final decoded = jsonDecode(rawInfo);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Invalid info API response');
    }

    return AppInfo.fromJson(decoded);
  }

  Future<void> _writeRawInfoJson(String rawInfo) async {
    try {
      await _cache.writeRawInfoJson(rawInfo);
    } catch (e, stackTrace) {
      if (_throwOnCacheWriteFailure) {
        Error.throwWithStackTrace(InfoCacheWriteException(e), stackTrace);
      }
      debugPrint('[BapU] info cache write failed: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
