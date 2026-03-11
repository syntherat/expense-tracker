import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

void configureSessionTransport(Dio dio) {
  // Keep cookies attached across requests on Android/iOS.
  dio.interceptors.add(CookieManager(CookieJar()));
}
