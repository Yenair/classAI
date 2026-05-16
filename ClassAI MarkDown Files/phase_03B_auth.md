```markdown
### Step 3.6: Deep Link Configuration

**Android** (`android/app/src/main/AndroidManifest.xml`):
```xml
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="classai" />
</intent-filter>
```

**iOS** (`ios/Runner/Info.plist`):
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>classai</string>
    </array>
  </dict>
</array>
```

**Windows** — protocol registration in `windows/runner/main.cpp` (or defer to Phase 9).

## Phase 3 Acceptance Criteria (GATE)

```bash
flutter test test/auth/auth_state_machine_test.dart    # All state transitions correct
flutter test test/auth/emergency_flush_test.dart        # Flush saves all registered callbacks
flutter test test/auth/login_screen_widget_test.dart    # Login screen renders, handles errors
flutter test test/auth/deep_link_test.dart              # Deep links parsed correctly
flutter build windows --debug                           # Compiles
```
```
