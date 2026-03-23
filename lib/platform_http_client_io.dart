import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:cupertino_http/cupertino_http.dart';
import 'package:http/http.dart';

// 네이티브 플랫폼에서는 package:http의 기본 Client()가
// dart:io 기반 구현을 자동으로 선택한다.
Client _createDefaultClient() => Client();


Client createPlatformHttpClient() {
  if (Platform.isIOS || Platform.isMacOS) {
    // iOS에서는 NSURLSession 기반 구현을 사용한다.
    return CupertinoClient.defaultSessionConfiguration();
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

  // 당장 지원하지 않지만 Windows/Linux 등 그 밖의 네이티브 플랫폼은 기본 구현을 사용한다.
  return _createDefaultClient();
}
