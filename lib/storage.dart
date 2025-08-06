import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<void> saveFileAsString(String fileName, String data) async {
  final dir = await getApplicationSupportDirectory();
  final file = File("${dir.path}/$fileName");
  await file.writeAsString(data, flush: true);
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
