import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';
import 'theme.dart';

// This is what was missing: firebase_core/messaging/cloud_firestore don't
// send anything to the Firebase Analytics dashboard on their own — that's
// a separate SDK (firebase_analytics) with its own instance + explicit
// logging calls. Without this, Firestore's "devices" collection keeps
// filling up (that part was always working) but Analytics stays empty.
final FirebaseAnalytics analytics = FirebaseAnalytics.instance;

// Background එකේ නොටිෆිකේෂන් එනකොට වැඩ කරන handler එක
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("Handling a background message: ${message.messageId}");
}

void main() async {
  // Flutter බයින්ඩින්ස් ඉනිවලයිස් කිරීම අනිවාර්යයි
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase ස්ටාර්ට් කිරීම — wrapped so a Firebase problem (missing/
  // misconfigured google-services.json, plugin not applied, no network
  // on first launch, etc.) can never block the app from opening at all.
  // Without this try/catch, an exception here stops main() before
  // runApp() is reached — which shows as a black screen with no crash
  // dialog in release builds, and is almost certainly what's happening.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    // Requests notification permission and writes this device's
    // `devices/{id}` doc to Firestore — this is the piece that was
    // documented as added but never actually shipped, which is why no
    // users were ever showing up in the Firebase dashboard.
    unawaited(NotificationService.initAndRegister());
    // Explicit app_open event — Analytics logs some events (like this
    // one) automatically once the SDK is initialized, but logging it
    // ourselves means it fires the moment main() runs, not whenever the
    // SDK's own internal timer gets to it.
    unawaited(analytics.logAppOpen());
  } catch (e, st) {
    debugPrint('Firebase init failed — app will still start without push notifications: $e\n$st');
  }

  runApp(const SnazyApp());
}

class SnazyApp extends StatefulWidget {
  const SnazyApp({super.key});

  @override
  State<SnazyApp> createState() => _SnazyAppState();
}

class _SnazyAppState extends State<SnazyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Keeps lastActiveAt current so the daily re-engagement Cloud
      // Function only nudges devices that have genuinely gone quiet.
      NotificationService.markActive();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Snazy',
      debugShowCheckedModeBanner: false,
      theme: SnazyTheme.theme,
      // Auto-logs a screen_view event every time the user navigates to
      // a new named route or screen — this alone is what populates most
      // of the Firebase Analytics dashboard (active users, engagement,
      // screen popularity) without hand-writing a log call per screen.
      navigatorObservers: [
        FirebaseAnalyticsObserver(analytics: analytics),
      ],
      home: const SplashScreen(),
    );
  }
}
