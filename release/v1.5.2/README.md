# BG Gremlin APK Recovery v1.5.2

v1.5.2 is the Android user-visible export hotfix.

The production defect in v1.5.1 was that **Export Full Recovery Project** could complete successfully into Godot app-private `user://` storage, which is not a normal user-visible Files/Downloads destination on Android.

In v1.5.2 the primary action is **Export Full Recovery Project ZIP**. It opens Android's native save flow and writes the complete SHA-qualified recovery workspace as a portable ZIP to the destination selected by the user. Report export and project-ZIP export no longer silently redirect a failed user-facing save into app-private storage.

App-private storage remains available only as internal working/staging space while constructing the recovery workspace and while streaming a ZIP to a selected `content://` document.

See `BGGremlinAPKRecovery-v1.5.2-VALIDATION.txt` for the exact validation boundary. Static build/package checks passed. No physical Android target was attached during this validation run, so physical-device export acceptance is explicitly not claimed.
