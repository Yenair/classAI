
```markdown
`phase_07_admin.md`
# Phase 7: Admin Portal + Vault + Payments + Export (Self-Contained)

**Goal**: Complete admin portal with teacher/device management, recovery code generation, vault approval. Paystack payment flow. PDF export with watermark. Bulk operations.

## Architecture Decisions (This Phase Only)

- **Paystack**: WebView-based payment. Webhook updates server credit state. Client polls every 30s for 5 min, then normal sync. `payment_events` table with UNIQUE `transaction_reference`, `INSERT ... ON CONFLICT DO NOTHING`.
- **PDF watermark**: Checked at generation AND view time (cached check for 1 hour). Composite cache key: `contentHash + watermarkStatus + schoolNameHash + logoHash`.
- **Vault approval**: Server-side approval only (admin must be online). Items with `min_tier > 'free'` hidden on downgrade (not deleted).
- **Credit spending on vault**: Decrement credits, append `credit_spent_ids_local`, generate `credit_spent_batch_id`. Server validates counter continuity.

## Agent Playbook — Phase 7 File Creation Order

### Step 7.1: Payment Service (`lib/core/services/payment_service.dart`)

```dart
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../database/database.dart';

class PaymentService {
  final AppDatabase _db;
  final Dio _dio;
  final _uuid = const Uuid();

  PaymentService(this._db, this._dio);

  /// Initialize a Paystack payment.
  /// Returns a Paystack checkout URL to open in WebView.
  Future<String> initializePayment({
    required String email,
    required int amountNaira, // in NGN
    required String plan,     // 'basic', 'standard', 'elite'
    required String schoolId,
  }) async {
    final reference = _uuid.v4();
    final response = await _dio.post(
      '/payment/initialize',
      data: {
        'email': email,
        'amount': amountNaira * 100, // Paystack uses kobo
        'reference': reference,
        'plan': plan,
        'school_id': schoolId,
        'currency': 'NGN',
      },
    );

    // Save pending payment event locally
    await _db.paymentEventsDao.insert(
      transactionReference: reference,
      confirmedByWebhook: false,
      amount: amountNaira,
      plan: plan,
      createdAt: DateTime.now(),
    );

    return response.data['authorization_url'];
  }

  /// Verify a payment with Paystack.
  Future<bool> verifyPayment(String reference) async {
    final response = await _dio.get('/payment/verify/$reference');
    final status = response.data['status'];
    if (status == 'success') {
      await _db.paymentEventsDao.markConfirmed(reference);
      return true;
    }
    return false;
  }

  /// Poll for payment confirmation (called after WebView closes).
  /// Polls every 30 seconds for up to 5 minutes.
  Stream<bool> pollForConfirmation(String reference) async* {
    for (int i = 0; i < 10; i++) {
      yield await verifyPayment(reference);
      await Future.delayed(const Duration(seconds: 30));
    }
  }
}
```

### Step 7.2: Admin Dashboard Screen (`lib/features/admin/screens/admin_dashboard_screen.dart`)

Requirements:
- **Teacher Management Table**: List all teachers with: name, email, role, last sync timestamp, device count, status indicator (green <1hr, yellow 1-24hr, red >24hr, gray >7 days). Tap teacher → detail screen.
- **Teacher Detail Screen**: Device list with `last_active`, manual deactivate button, "Generate Recovery Code" button, subject assignment dropdown.
- **Recovery Code Generation**: Admin must be online. Queues offline requests in `pending_recovery_requests`. Shows code + expiry. Code is 16-char alphanumeric.
- **Vault Approval Queue**: Items pending approval. Approve/Reject buttons. Only visible to admin with Standard+ tier.
- **Subject Assignment**: Dropdown of all subjects. Search/filter. Duplicate detection via manifest aliases. Bulk assign to multiple teachers.
- **Sync Health Dashboard**: Per-teacher: last sync, pending count, status color-coded, conflicts count, device list.

### Step 7.3: Vault Screens (`lib/features/vault/screens/`)

**Vault Browser Screen**:
- Grid/list of approved vault items. Filter by subject, class level, curriculum.
- Each card: title, author, tier badge, credit cost, preview thumbnail.
- Tap → detail view with full content, "Acquire for X credits" button.
- Credit check before acquiring. Spend → decrement locally → queue for sync.

**Vault Publisher Screen** (Standard+ tier):
- Form: title, description, subject, class level, content, attachments (max 50KB images via `flutter_image_compress`).
- Preview before submit.
- Submit → encrypt content with school key → queue for sync with `needs_approval = true`.
- Track approval status: pending, approved, rejected (with reason).
- On approval: `min_tier` set to publisher's tier. `credits_spent = 0` for publisher's own items. `acquisition_date = NOW()`.
```
```