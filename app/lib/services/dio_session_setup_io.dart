import 'dart:io';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

Future<void> configureSessionTransport(Dio dio) async {
  // Always install an in-memory cookie manager immediately so requests never race startup.
  dio.interceptors.removeWhere((i) => i is CookieManager);
  dio.interceptors.add(CookieManager(CookieJar()));

  try {
    final appDocDir = await getApplicationDocumentsDirectory();
    final cookieDir = Directory('${appDocDir.path}/.cookies/');
    if (!cookieDir.existsSync()) {
      cookieDir.createSync(recursive: true);
    }

    final cookieJar = PersistCookieJar(
      ignoreExpires: false,
      storage: FileStorage(cookieDir.path),
    );

    // Swap to persistent cookie storage for app restarts.
    dio.interceptors.removeWhere((i) => i is CookieManager);
    dio.interceptors.add(CookieManager(cookieJar));
  } catch (e) {
    debugPrint(
        'Cookie persistence setup failed: $e, keeping in-memory storage');
  }
}
