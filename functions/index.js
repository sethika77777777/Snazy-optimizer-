/**
 * Re-engagement push notifications for Snazy Optimizer.
 *
 * This is the piece that actually decides "this user hasn't opened the
 * app in a while, send them a nudge" — it has to live on a server,
 * because by definition it needs to run while nobody's phone has the
 * app open. Deploy it to Firebase Cloud Functions and it runs on its
 * own schedule for free (within the free tier).
 *
 * How it works:
 *   1. The app (see lib/services/notification_service.dart) writes a
 *      `devices/{deviceId}` doc with { fcmToken, lastActiveAt } every
 *      time it's opened.
 *   2. This function runs once a day, finds devices whose lastActiveAt
 *      is older than INACTIVE_AFTER_DAYS and that haven't already been
 *      nudged in the last COOLDOWN_DAYS, and sends each one a push.
 *   3. It stamps lastNudgeAt so the same device isn't re-nudged every
 *      single day, and deletes tokens Firebase reports as dead.
 */

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const INACTIVE_AFTER_DAYS = 3; // "hasn't opened the app" threshold
const COOLDOWN_DAYS = 3; // don't nudge the same device more than this often
const BATCH_SIZE = 400; // FCM sendEachForMulticast caps at 500/call

const NUDGE_MESSAGES = [
  {
    title: "Your game profiles are waiting",
    body: "Jump back into Snazy and boost your next session.",
  },
  {
    title: "Haven't seen you in a while",
    body: "Your device could use a quick optimization pass.",
  },
];

exports.sendReengagementPush = onSchedule(
  {
    schedule: "every day 10:00",
    timeZone: "Asia/Colombo",
  },
  async () => {
    const db = getFirestore();
    const now = Timestamp.now();
    const inactiveCutoff = Timestamp.fromMillis(
      now.toMillis() - INACTIVE_AFTER_DAYS * 24 * 60 * 60 * 1000
    );
    const cooldownCutoff = Timestamp.fromMillis(
      now.toMillis() - COOLDOWN_DAYS * 24 * 60 * 60 * 1000
    );

    const snapshot = await db
      .collection("devices")
      .where("lastActiveAt", "<", inactiveCutoff)
      .get();

    const candidates = snapshot.docs.filter((doc) => {
      const lastNudgeAt = doc.data().lastNudgeAt;
      return !lastNudgeAt || lastNudgeAt.toMillis() < cooldownCutoff.toMillis();
    });

    if (candidates.length === 0) {
      console.log("No inactive devices to nudge today.");
      return;
    }

    const message = NUDGE_MESSAGES[Math.floor(Math.random() * NUDGE_MESSAGES.length)];

    for (let i = 0; i < candidates.length; i += BATCH_SIZE) {
      const batch = candidates.slice(i, i + BATCH_SIZE);
      const tokens = batch.map((doc) => doc.data().fcmToken).filter(Boolean);
      if (tokens.length === 0) continue;

      const response = await getMessaging().sendEachForMulticast({
        tokens,
        notification: message,
        android: { priority: "high" },
      });

      const writeBatch = db.batch();
      response.responses.forEach((result, idx) => {
        const doc = batch[idx];
        if (result.success) {
          writeBatch.update(doc.ref, { lastNudgeAt: FieldValue.serverTimestamp() });
        } else if (
          result.error &&
          (result.error.code === "messaging/registration-token-not-registered" ||
            result.error.code === "messaging/invalid-registration-token")
        ) {
          // Token is dead (app uninstalled, etc) — stop trying it.
          writeBatch.delete(doc.ref);
        }
      });
      await writeBatch.commit();

      console.log(
        `Nudged ${response.successCount}/${tokens.length} devices (batch ${i / BATCH_SIZE + 1}).`
      );
    }
  }
);
