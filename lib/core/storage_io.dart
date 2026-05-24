// 네이티브(Android/iOS) 플랫폼용 파일 기반 캐시 구현체
import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<void> saveFileAsString(String fileName, String data) async {
  final dir = await getApplicationSupportDirectory();
  final file = File("${dir.path}/$fileName");
  final tmpFile = File(
    "${dir.path}/$fileName.tmp.${DateTime.now().microsecondsSinceEpoch}",
  );

  await tmpFile.writeAsString(data, flush: true);
  try {
    await tmpFile.rename(file.path);
  } on FileSystemException {
    if (await file.exists()) {
      await file.delete();
    }
    await tmpFile.rename(file.path);
  }
}

Future<String> readFileAsString(String fileName) async {
  final dir = await getApplicationSupportDirectory();
  final file = File("${dir.path}/$fileName");
  return await file.readAsString();
}

Future<DateTime> getLastModifiedOfFile(String fileName) async {
  final dir = await getApplicationSupportDirectory();
  final file = File("${dir.path}/$fileName");
  return await file.lastModified();
}
