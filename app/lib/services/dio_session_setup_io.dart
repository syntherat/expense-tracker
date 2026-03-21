import 'dart:io';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

void configureSessionTransport(Dio dio) {
  // Keep cookies attached across requests and app restarts on Android/iOS.
  // Initialize async to ensure directory is ready
  _initPersistentCookies(dio);
}

void _initPersistentCookies(Dio dio) {
  // Non-blocking initialization of persistent cookie storage
  getApplicationDocumentsDirectory().then((appDocDir) {
    try {
      final cookieDir = Directory('${appDocDir.path}/.cookies/');
      final cookieJar = PersistCookieJar(
          ignoreExpires: false, storage: FileStorage(cookieDir.path));
      // Clear existing in-memory cookie manager if it exists
      dio.interceptors.removeWhere((i) => i is CookieManager);
      dio.interceptors.add(CookieManager(cookieJar));
    } catch (e) {
      // Fallback to in-memory if file storage fails
      debugPrint(
          'Cookie persistence setup failed: $e, using in-memory storage');
    }
  }).catchError((e) {
    debugPrint('Could not get application directory: $e');
  });
}
