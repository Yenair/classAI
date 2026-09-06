import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global text scale factor applied to every screen via [MaterialApp.builder].
///
/// Stored in SharedPreferences as a `double` under the key
/// `app_text_scale`.  The default is **0.9**.  The
/// settings screen exposes a slider (0.8 – 1.2) that writes here; the lesson
/// editor's own font-size picker also writes here so there is a single
/// source of truth.
class TextScaleNotifier extends Notifier<double> {
  static const _key = 'app_text_scale';

  @override
  double build() {
    return 0.9;
  }

  /// Load the persisted value.  Safe to call multiple times (idempotent).
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_key);
    if (saved != null && saved >= 0.5 && saved <= 2.0) {
      state = saved;
    }
  }

  /// Persist and apply a new scale.
  Future<void> setScale(double value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key, value);
  }
}

final textScaleProvider =
    NotifierProvider<TextScaleNotifier, double>(TextScaleNotifier.new);
