// 플랫폼에 따라 구현체를 선택하는 조건부 export
// - 웹(dart.library.js_interop): storage_web.dart (캐싱 없이 매번 새로 fetch)
// - 네이티브(그 외): storage_io.dart (파일 기반 캐시)
export 'storage_io.dart' if (dart.library.js_interop) 'storage_web.dart';
