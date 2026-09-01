// 플랫폼별 구현 파일을 분리해서,
// 각 타깃이 자기에게 필요한 코드만 보도록 만든다.
// 웹 판별은 Dart 공식 권장 방식에 맞춰 js_interop 조건을 사용한다.
// 기본은 네이티브 구현을 사용하고, 웹일 때만 웹 전용 구현으로 갈아낀다.
export 'platform_http_client_io.dart'
    if (dart.library.js_interop) 'platform_http_client_web.dart';
