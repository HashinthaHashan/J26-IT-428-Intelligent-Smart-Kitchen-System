import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config.dart';

final dioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 12),
      headers: const {'Accept': 'application/json'},
    ),
  )..interceptors.add(AuthInterceptor(token: AppConfig.apiToken));
});

class AuthInterceptor extends Interceptor {
  AuthInterceptor({required this.token});

  final String token;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }
}

class ApiException implements Exception {
  const ApiException(this.message);

  factory ApiException.fromDio(DioException error) {
    final detail = error.response?.data is Map<String, dynamic>
        ? (error.response!.data as Map<String, dynamic>)['detail']
        : null;
    return ApiException(
      detail?.toString() ?? error.message ?? 'The server could not be reached.',
    );
  }

  final String message;

  String displayMessage() => kDebugMode
      ? message
      : 'Something went wrong. Check the connection and try again.';

  @override
  String toString() => displayMessage();
}

Future<T> apiCall<T>(Future<T> Function() request) async {
  try {
    return await request();
  } on DioException catch (error) {
    throw ApiException.fromDio(error);
  }
}

String userFacingError(Object error) {
  if (error is ApiException) return error.displayMessage();
  return kDebugMode
      ? error.toString()
      : 'Something went wrong. Check the connection and try again.';
}
