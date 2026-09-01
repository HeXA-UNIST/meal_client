// 위젯 raw JSON 캐시 전용 공유 저장소.
//
// 범용 앱 파일 저장소(storage_io.dart)는 Application Support를 계속 사용하고,
// meal.json/info.json처럼 native 위젯이 직접 읽는 파일만 이 seam을 통한다.
export 'widget_shared_storage_io.dart'
    if (dart.library.js_interop) 'widget_shared_storage_web.dart';
