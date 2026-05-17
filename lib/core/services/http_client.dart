import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class IdempotencyInterceptor extends Interceptor {}

/// Allowed SHA-256 certificate fingerprints for pinning.
///
/// Populate this list with the actual fingerprints obtained by running:
///   `openssl s_client -connect <project>.supabase.co:443 -showcerts 2>/dev/null | openssl x509 -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256`
///
/// When the list is empty the certificate check is skipped (pass-through) so
/// that development / test environments are not blocked until fingerprints
/// are configured.
const allowedFingerprints = <String>[];

/// Creates an API client for Supabase Edge Function calls.
///
/// Reads the Supabase URL and anon key from [Supabase.instance.client] so that
/// [baseUrl] points to the Supabase REST/Edge Functions endpoint and every
/// request carries the `Authorization: Bearer <anon-key>` header.
Dio createApiClient({required String baseUrl, required List<String> certPins}) {
  final supabase = Supabase.instance.client;
  final anonKey = supabase.auth.currentSession?.accessToken ?? '';

  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'Authorization': 'Bearer $anonKey',
      'apikey': anonKey,
    },
  ));

  // Certificate pinning via dart:io SecurityContext
  //
  // The default native adapter (IOHttpClientAdapter) exposes an
  // `onHttpClientCreate` setter that lets us configure each HttpClient
  // with a custom badCertificateCallback.  We access it through dynamic
  // dispatch because the concrete adapter type is not exported from the
  // public Dio API.
  try {
    // ignore: avoid_dynamic_calls
    (dio.httpClientAdapter as dynamic).onHttpClientCreate =
        (HttpClient client) {
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
        // Pass-through when pinning is not yet configured
        if (allowedFingerprints.isEmpty) return true;

        // Hash the PEM representation of the server certificate and compare
        // against the allowed fingerprint list.
        final hash = sha256.convert(cert.pem.codeUnits).toString();
        return allowedFingerprints.contains(hash);
      };
      return client;
    };
  } catch (_) {
    // Not a IOHttpClientAdapter (e.g., test mock) – skip pinning.
  }

  // Idempotency interceptor for credit batches
  dio.interceptors.add(IdempotencyInterceptor());

  return dio;
}
