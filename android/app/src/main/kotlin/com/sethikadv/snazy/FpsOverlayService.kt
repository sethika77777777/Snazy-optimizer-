package com.sethikadv.snazy

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import java.io.BufferedReader
import java.io.DataOutputStream
import java.io.InputStreamReader

/**
 * Floating in-game FPS counter. Everything it shows is a real, measured
 * number — never a fake/animated placeholder. FPS is read from the same
 * per-app frame-timing data Android itself records (`dumpsys gfxinfo
 * <pkg> framestats`), which — like every privileged action in this app —
 * requires root or a granted Shizuku session; there is no public,
 * unprivileged Android API that exposes another app's real frame times.
 * Without root/Shizuku this service simply isn't started (see
 * MainActivity#startFpsOverlay).
 */
class FpsOverlayService : Service() {

    companion object {
        const val EXTRA_PKG = "pkg"
        private const val NOTIF_CHANNEL = "snazy_fps_overlay"
        private const val NOTIF_ID = 4201
        private const val POLL_MS = 800L
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var fpsText: TextView? = null
    private var dot: View? = null
    private var targetPkg: String = ""
    private val handler = Handler(Looper.getMainLooper())
    private var polling = false

    private val pollRunnable = object : Runnable {
        override fun run() {
            if (!polling) return
            val pkg = targetPkg
            Thread {
                val fps = FpsReader.readFps(pkg) { cmd -> runPrivilegedBlocking(cmd) }
                handler.post { updateFpsDisplay(fps) }
            }.start()
            handler.postDelayed(this, POLL_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        targetPkg = intent?.getStringExtra(EXTRA_PKG) ?: targetPkg
        startForeground(NOTIF_ID, buildNotification())
        if (overlayView == null) showOverlay()
        if (!polling) {
            polling = true
            handler.post(pollRunnable)
        }
        return START_STICKY
    }

    override fun onDestroy() {
        polling = false
        handler.removeCallbacks(pollRunnable)
        removeOverlay()
        super.onDestroy()
    }

    // ---------------- Notification (required by Android for any FGS) ----------------

    private fun buildNotification(): android.app.Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(NOTIF_CHANNEL) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(
                        NOTIF_CHANNEL, "FPS Overlay",
                        NotificationManager.IMPORTANCE_MIN
                    ).apply { setShowBadge(false) }
                )
            }
        }
        return NotificationCompat.Builder(this, NOTIF_CHANNEL)
            .setContentTitle("Snazy FPS counter active")
            .setContentText("Tap the floating counter's toggle in-app to turn it off")
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()
    }

    // ---------------- Overlay view (premium glass pill + SNAZY watermark) ----------------

    private fun dp(v: Int): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()

    private fun sp(v: Float): Float =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, v, resources.displayMetrics)

    private fun showOverlay() {
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val accentCyan = Color.parseColor("#00E5FF")
        val accentPurple = Color.parseColor("#7C4DFF")
        val glassBorder = Color.parseColor("#59FFFFFF")

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(8), dp(14), dp(8))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(18).toFloat()
                setColor(Color.parseColor("#E6101319")) // dark glass, near-opaque
                setStroke(dp(1), glassBorder)
            }
            elevation = dp(6).toFloat()
        }

        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val dotView = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(8), dp(8)).apply {
                marginEnd = dp(7)
            }
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#00E676"))
            }
        }
        dot = dotView

        val fpsNum = TextView(this).apply {
            text = "--"
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 19f)
        }
        fpsText = fpsNum

        val fpsLabel = TextView(this).apply {
            text = " FPS"
            setTextColor(Color.parseColor("#B3FFFFFF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        }

        row.addView(dotView)
        row.addView(fpsNum)
        row.addView(fpsLabel)

        val watermark = TextView(this).apply {
            text = "SNAZY OPTIMIZER"
            setTextColor(Color.argb(178, 0, 229, 255)) // accentCyan @ ~70%
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 8f)
            letterSpacing = 0.12f
            gravity = Gravity.CENTER
            setPadding(0, dp(2), 0, 0)
        }

        root.addView(row)
        root.addView(watermark)

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            android.graphics.PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dp(16)
            y = dp(90)
        }

        // Draggable — the overlay is meant to sit wherever doesn't block
        // the user's own game HUD, so it can be repositioned by touch.
        var startX = 0
        var startY = 0
        var touchStartX = 0f
        var touchStartY = 0f
        root.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = params.x
                    startY = params.y
                    touchStartX = event.rawX
                    touchStartY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    params.x = startX + (event.rawX - touchStartX).toInt()
                    params.y = startY + (event.rawY - touchStartY).toInt()
                    windowManager?.updateViewLayout(root, params)
                    true
                }
                else -> false
            }
        }

        windowManager?.addView(root, params)
        overlayView = root
    }

    private fun removeOverlay() {
        overlayView?.let {
            try {
                windowManager?.removeView(it)
            } catch (_: Exception) {
            }
        }
        overlayView = null
    }

    private fun updateFpsDisplay(fps: Int?) {
        if (fps == null) {
            fpsText?.text = "--"
            dot?.background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#9AA5B1"))
            }
            return
        }
        fpsText?.text = fps.toString()
        // Real thresholds, not decorative: green = smooth, amber = dips,
        // red = the session is actually stuttering.
        val color = when {
            fps >= 50 -> "#00E676"
            fps >= 30 -> "#FFB300"
            else -> "#FF5252"
        }
        dot?.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.parseColor(color))
        }
    }

    // ---------------- Privileged exec (self-contained — service may outlive MainActivity) ----------------

    private fun checkRoot(): Boolean {
        val paths = arrayOf(
            "/system/bin/su", "/system/xbin/su", "/sbin/su",
            "/su/bin/su", "/data/local/xbin/su", "/data/local/bin/su"
        )
        if (paths.any { java.io.File(it).exists() }) return true
        return try {
            val p = Runtime.getRuntime().exec(arrayOf("which", "su"))
            val out = BufferedReader(InputStreamReader(p.inputStream)).readLine()
            p.waitFor()
            !out.isNullOrEmpty()
        } catch (e: Exception) {
            false
        }
    }

    private fun runAsRootRawWithOutput(command: String): String? {
        var process: Process? = null
        return try {
            process = Runtime.getRuntime().exec("su")
            val os = DataOutputStream(process.outputStream)
            os.writeBytes("$command\n")
            os.writeBytes("exit\n")
            os.flush()
            val output = BufferedReader(InputStreamReader(process.inputStream)).readText()
            process.waitFor()
            output
        } catch (e: Exception) {
            null
        } finally {
            process?.destroy()
        }
    }

    /** Root if present, otherwise the same live Shizuku session MainActivity uses (app-process-wide singleton). */
    private fun runPrivilegedBlocking(cmd: String): String? {
        return if (checkRoot()) {
            runAsRootRawWithOutput(cmd)
        } else if (ShizukuManager.hasPermission()) {
            val latch = java.util.concurrent.CountDownLatch(1)
            var out: String? = null
            ShizukuManager.exec(cmd) { output ->
                out = output
                latch.countDown()
            }
            latch.await(3, java.util.concurrent.TimeUnit.SECONDS)
            out
        } else {
            null
        }
    }
}
