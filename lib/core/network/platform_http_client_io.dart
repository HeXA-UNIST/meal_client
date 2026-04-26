import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:cupertino_http/cupertino_http.dart';
import 'package:http/http.dart';

// HttpException은 dart:io에서만 사용 가능하므로, 플랫폼별로 예외 생성 함수를 구현한다.
Exception createHttpException(int statusCode) =>
    HttpException("HTTP $statusCode: Response Error");

Client _createDefaultClient() => Client();


Client createPlatformHttpClient() {
  if (Platform.isIOS || Platform.isMacOS) {
    try {
      // CupertinoClient는 iOS/macOS에서 네이티브 URLSession을 활용해
      // HTTP/2와 QUIC 지원을 제공한다.
      return CupertinoClient.defaultSessionConfiguration();
    } catch (_) {
      // CupertinoClient 초기화에 실패하면
      // package:http의 기본 네이티브 클라이언트로 안전하게 폴백한다.
      return _createDefaultClient();
    }
  }

  if (Platform.isAndroid) {
    try {
      // Android에서는 Cronet을 우선 사용해 네트워크 스택을 최적화한다.
      // data.dart에 구현된 디스크 캐시를 사용하기 때문에, 캐시는 비활성화한다.
      final engine = CronetEngine.build(cacheMode: CacheMode.disabled);
      return CronetClient.fromCronetEngine(engine);
    } catch (_) {
      // Google Play 서비스가 없거나 Cronet 엔진 초기화에 실패하면
      // package:http의 기본 네이티브 클라이언트로 안전하게 폴백한다.
      return _createDefaultClient();
    }
  }
  return _createDefaultClient();
}
