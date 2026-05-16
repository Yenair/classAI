import 'package:dio/dio.dart';

class IdempotencyInterceptor extends Interceptor {}

Dio createApiClient({required String baseUrl, required List<String> certPins}) {
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  // Certificate pinning for production
  // (dio_interceptor_certificate_pinning package added in Phase 5)

  // Idempotency interceptor for credit batches
  dio.interceptors.add(IdempotencyInterceptor());

  return dio;
}
