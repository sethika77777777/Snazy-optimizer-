import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Registers this install with Firebase so:
///   1. `functions/index.js`'s daily re-engagement job has real devices to
///      look at instead of an empty `devices` collection, and
///   2. the Firestore console dashboard actually shows users.
///
/// Before this file existed, `main.dart` initialized Firebase Messaging but
/// nothing ever wrote a `devices/{id}` doc — so nothing could ever show up
/// anywhere, and the notification permission prompt never fired either.
///
/// Every method is wrapped in try/catch and never rethrows: a Firestore/FCM
/// hiccup (offline on first launch, Firestore not yet enabled in the
/// console, permission denied) must never crash app startup or block the
/// rest of the app — same reasoning as the try/catch already around
/// `Firebase.initializeApp()` in main.dart.
class NotificationService {
  static const _kDeviceIdKey = 'snazy_device_id';
  static const _uuid = Uuid();

  static String? _deviceId;

  /// Call once on app launch (see main.dart). Requests the POST_NOTIFICATIONS
  /// permission (Android 13+) — this is the actual system dialog the app
  /// needs "grant notification access" for — then registers the device.
  static Future<void> initAndRegister() async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {
      // Permission API unavailable, or the user denied it — push just won't
      // arrive for this device. Still try to register it below so it shows
      // up in the dashboard even without notifications enabled.
    }
    await markActive();
  }

  /// Call on every app resume too (main.dart's lifecycle observer) so
  /// `lastActiveAt` reflects real usage — that field is exactly what
  /// `sendReengagementPush` uses to decide who has gone quiet.
  static Future<void> markActive() async {
    try {
      final deviceId = await _getOrCreateDeviceId();
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return; // no token yet — nothing useful to write

      // Field names must match firestore.rules' hasOnly(...) list exactly,
      // or the write is rejected. lastNudgeAt is intentionally never
      // written from the client — only the Cloud Function's Admin SDK sets it.
      await FirebaseFirestore.instance.collection('devices').doc(deviceId).set(
        {
          'fcmToken': token,
          'platform': 'android',
          'lastActiveAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // Firestore/Messaging unreachable (offline, project not fully set up
      // yet, etc.) — fail silently, same as every other privileged-feature
      // fallback in Snazy. There's nothing the user can fix from inside the
      // app for a project-level Firebase config issue.
    }
  }

  /// A stable per-install id, generated once and persisted locally — this
  /// is the Firestore document id under `devices/`.
  static Future<String> _getOrCreateDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kDeviceIdKey);
    if (id == null) {
      id = _uuid.v4();
      await prefs.setString(_kDeviceIdKey, id);
    }
    _deviceId = id;
    return id;
  }
}
