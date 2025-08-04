import 'dart:io';

import 'package:http/http.dart';
import 'package:http/io_client.dart';
import 'package:cronet_http/cronet_http.dart';
import 'package:cupertino_http/cupertino_http.dart';

const _cacheSize = 4 * 1024;

Client httpClient() {
  if (Platform.isAndroid) {
    final engine = CronetEngine.build(
      cacheMode: CacheMode.memory,
      cacheMaxSize: _cacheSize,
    );
    return CronetClient.fromCronetEngine(engine);
  }
  if (Platform.isIOS) {
    final config = URLSessionConfiguration.ephemeralSessionConfiguration()
      ..cache = URLCache.withCapacity(memoryCapacity: _cacheSize);
    return CupertinoClient.fromSessionConfiguration(config);
  }
  return IOClient();
}
