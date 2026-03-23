// 웹 플랫폼용 스텁 구현체
// 웹에서는 dart:io와 path_provider를 사용할 수 없으므로,
// 저장은 무시하고 읽기는 항상 예외를 던져 매번 새로 API에서 데이터를 받아오도록 함

// 웹에서는 파일 저장 없이 그냥 무시
Future<void> saveFileAsString(String fileName, String data) async {}

// 웹에서는 캐시 파일이 없으므로 항상 예외를 던져 새로 fetch하도록 유도
Future<String> readFileAsString(String fileName) async {
  throw Exception("웹 플랫폼은 파일 캐시를 지원하지 않습니다");
}

// 웹에서는 파일 수정 시간을 알 수 없으므로 항상 예외를 던짐
Future<DateTime> getLastModifiedOfFile(String fileName) async {
  throw Exception("웹 플랫폼은 파일 수정 시간 조회를 지원하지 않습니다");
}
