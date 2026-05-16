```markdown
`phase_00_contract.md`
# Phase 0: Build Contract (Read Before Any Code)

**Goal**: Establish the exact environment, dependencies, backend contract, and platform targets so every subsequent phase has a fixed foundation.

## Phase 0.1: Exact Environment

| Tool | Version | Notes |
|------|---------|-------|
| Flutter SDK | 3.22.0 | Stable channel |
| Dart SDK | 3.4.0 | Bundled with Flutter |
| Android min SDK | 23 | Required for Keystore `PURPOSE_ENCRYPT`/`PURPOSE_DECRYPT` |
| iOS min deployment | 15.0 | Required for Secure Enclave APIs |
| Java | 17 | For Android build |

## Phase 0.2: Complete pubspec.yaml

**Replace `pubspec.yaml` with this exact content. Do not change versions.**

```yaml
name: classai
description: Offline-first AI teaching assistant for Nigerian schools
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.4.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

  # State
  flutter_riverpod: 2.5.1
  riverpod_annotation: 2.3.5

  # Database
  drift: 2.18.0
  sqlite3_flutter_libs: 0.5.24

  # Platform & Device
  path_provider: 2.1.4
  path: 1.9.0
  connectivity_plus: 6.0.5
  battery_plus: 6.0.2
  device_info_plus: 10.1.2

  # Cloud & HTTP
  supabase_flutter: 2.5.8
  dio: 5.7.0

  # AI
  google_generative_ai: 0.4.6
  http: 1.2.2

  # Documents
  pdf: 3.11.1
  printing: 5.13.4

  # Media
  flutter_image_compress: 2.3.0
  image_picker: 1.1.2

  # Secure Storage & Biometrics
  flutter_secure_storage: 9.2.3
  shared_preferences: 2.3.3
  local_auth: 2.3.0

  # Cryptography (pure Dart, cross-platform, Argon2id built-in)
  cryptography: 2.7.0
  crypto: 3.0.6

  # Utils
  intl: 0.19.0
  uuid: 4.5.1
  google_fonts: 6.2.1
  json_annotation: 4.9.0
  freezed_annotation: 2.4.4
  go_router: 14.6.2

  # Monitoring
  sentry_flutter: 8.9.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: 2.4.13
  riverpod_generator: 2.4.3
  freezed: 2.5.7
  drift_dev: 2.18.0
  json_serializable: 6.8.0
  mocktail: 1.0.4
  integration_test:
    sdk: flutter
```

## Phase 0.3: Platform Targets for v1

| Platform | Tier | Notes |
|----------|------|-------|
| Android (phone) | **Tier 1** | Primary target. API 23+. |
| Android (tablet ≥10") | **Tier 1** | Editor mode on large screens. |
| iOS (phone) | **Tier 2** | Tested, not launch-critical. |
| iOS (tablet ≥10") | **Tier 2** | Editor mode available. |
| Windows/macOS/Linux | **Best-effort** | Compiles but not QA-blocking for v1. |

**Rule**: Editor mode on devices with `shortestSide >= 600` (tablets + desktop). Reader mode elsewhere. User override in Settings > Advanced. Despite Appendix D's deferral, the code in Phase 1 creates all platform targets; only Tier 1 blocks launch.

## Phase 0.4: Backend Contract

The Supabase backend must exist before Phases 3+. For now, define:

**Edge Functions to implement:**
1. `POST /auth/activate` — input/output per Appendix B
2. `POST /auth/login` — input/output per Appendix B
3. `POST /auth/admin-recovery/request-otp` — sends OTP to admin recovery email
4. `POST /auth/admin-recovery/verify-otp` — verifies OTP, re-wraps school key
5. `POST /sync/push` — accepts paginated batches, resolves local_id→server_id
6. `GET /sync/pull` — returns changes since cursor, paginated
7. `GET /sync/realtime-events` — returns events since event_id
8. `POST /recovery/generate-code` — admin generates teacher recovery code
9. `POST /recovery/reset-password` — teacher uses recovery code

**Backend requirements (agent builds Flutter app only; backend is separate):**
- Supabase project with PostgreSQL
- RLS policies: teachers see own school's data; admins see all school data
- Storage buckets: `school-logos`, `vault-images` (max 50KB)
- `supabase_realtime` publication on key tables
- Environment variables in Supabase dashboard (NOT in Flutter code): `DEEPSEEK_API_KEY`, `GEMINI_API_KEY`, `PAYSTACK_SECRET_KEY`, `TERMII_API_KEY`

**Agent note**: You are building the Flutter frontend. The backend is a separate project. Use mocked HTTP responses for all Supabase calls until the backend exists. The mock HTTP client returns valid responses per the contracts in Appendix B.

## Phase 0.5: HTTP Client

All HTTP calls use **`dio`** (5.7.0). Configure in `lib/core/services/http_client.dart`:
```dart
import 'package:dio/dio.dart';

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
```

## Phase 0.6: Auth Threat Model (Summary)

- `passwordHash` sent over TLS 1.3 to server. Server stores bcrypt(pepper(hash)). Not reversible.
- Salt stored per-teacher on server; cached locally after first login. No offline login without cached salt.
- Offline login: constant-time compare of locally-stored hash (Argon2id-derived, stored in platform keystore with biometric gate).
- Password hash version forces online re-auth when incremented (admin reset, recovery).
- 3/5/10 attempt lockout with increasing delays. Device-bound via `currentDeviceId`.
- Device compromise: school key encrypted at rest with hardware-backed key. Biometric required to unwrap in foreground. Session key (15-min TTL) for background sync does not require biometric but is encrypted with device-specific key.
- Replay protection: All mutations include `clientIdempotencyKey`. Server rejects duplicates.

## Phase 0.7: CI Commands

Every phase gate runs:
```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build apk --debug          # Tier 1
flutter build windows --debug      # Best-effort (must not error)
```
```