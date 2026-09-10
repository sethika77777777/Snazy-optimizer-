package com.sethikadv.snazy

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.net.Uri
import android.os.IBinder
import rikka.shizuku.Shizuku

/**
 * Bridges Snazy to Shizuku (https://shizuku.rikka.app), which lets a
 * non-rooted user grant Snazy the same shell-level access adb already has —
 * without rooting the device. Root users never need this: [MainActivity]
 * only reaches for it when `su` isn't available. Everything here calls the
 * real, published Shizuku-API (dev.rikka.shizuku:api) — there is no
 * simulated "pretend Shizuku" fallback.
 */
object ShizukuManager {

    /** Shizuku's real package id on the Play Store / GitHub releases. */
    const val SHIZUKU_PACKAGE = "moe.shizuku.privileged.api"
    private const val PERMISSION_REQUEST_CODE = 24_828

    // Bump whenever UserService.kt's behaviour changes — Shizuku restarts
    // the privileged process when this stops matching.
    private const val SERVICE_VERSION = 1

    private var userService: IUserService? = null
    private var binding = false
    private val pendingCalls = mutableListOf<(IUserService?) -> Unit>()
    private var permissionCallback: ((Boolean) -> Unit)? = null
    private var initialized = false

    private val userServiceArgs by lazy {
        Shizuku.UserServiceArgs(ComponentName("com.sethikadv.snazy", UserService::class.java.name))
            .daemon(false)
            .processNameSuffix("privileged")
            .debuggable(false)
            .version(SERVICE_VERSION)
    }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            userService = if (binder != null && binder.pingBinder()) {
                IUserService.Stub.asInterface(binder)
            } else {
                null
            }
            binding = false
            drainPending()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            userService = null
        }
    }

    private val permissionResultListener =
        Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
            if (requestCode == PERMISSION_REQUEST_CODE) {
                val granted = grantResult == PackageManager.PERMISSION_GRANTED
                permissionCallback?.invoke(granted)
                permissionCallback = null
            }
        }

    /** Call once from MainActivity#onCreate. Safe to call more than once. */
    fun init() {
        if (initialized) return
        initialized = true
        try {
            Shizuku.addRequestPermissionResultListener(permissionResultListener)
        } catch (_: Throwable) {
            // Shizuku classes failing to load at all means the dependency
            // didn't ship — nothing else in this object will work either,
            // but every public method here already fails safe (false/null).
        }
    }

    /** Call from MainActivity#onDestroy. */
    fun dispose() {
        try {
            Shizuku.removeRequestPermissionResultListener(permissionResultListener)
        } catch (_: Throwable) {
        }
        unbind()
        initialized = false
    }

    fun isShizukuAppInstalled(context: Context): Boolean {
        return try {
            context.packageManager.getPackageInfo(SHIZUKU_PACKAGE, 0)
            true
        } catch (_: Exception) {
            false
        }
    }

    fun openShizukuApp(context: Context): Boolean {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(SHIZUKU_PACKAGE)
        return if (launchIntent != null) {
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(launchIntent)
            true
        } else {
            false
        }
    }

    fun openShizukuOnPlayStore(context: Context) {
        try {
            val intent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("market://details?id=$SHIZUKU_PACKAGE")
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        } catch (_: Exception) {
            val intent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("https://play.google.com/store/apps/details?id=$SHIZUKU_PACKAGE")
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }
    }

    /** True once Shizuku/Sui is installed AND actually running (service started). */
    fun isBinderAlive(): Boolean = try {
        Shizuku.pingBinder()
    } catch (_: Throwable) {
        false
    }

    fun hasPermission(): Boolean {
        if (!isBinderAlive()) return false
        return try {
            if (Shizuku.isPreV11()) {
                false
            } else {
                Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
            }
        } catch (_: Throwable) {
            false
        }
    }

    /** 0 when backed by root (Sui/root-started Shizuku), 2000 when backed by adb/shell, -1 unknown. */
    fun getUid(): Int = try {
        if (isBinderAlive()) Shizuku.getUid() else -1
    } catch (_: Throwable) {
        -1
    }

    fun requestPermission(callback: (Boolean) -> Unit) {
        if (!isBinderAlive()) {
            callback(false)
            return
        }
        if (hasPermission()) {
            callback(true)
            return
        }
        permissionCallback = callback
        try {
            Shizuku.requestPermission(PERMISSION_REQUEST_CODE)
        } catch (_: Throwable) {
            permissionCallback = null
            callback(false)
        }
    }

    private fun drainPending() {
        val callbacks = pendingCalls.toList()
        pendingCalls.clear()
        callbacks.forEach { it(userService) }
    }

    private fun bind(then: (IUserService?) -> Unit) {
        if (userService != null) {
            then(userService)
            return
        }
        if (!hasPermission()) {
            then(null)
            return
        }
        pendingCalls.add(then)
        if (!binding) {
            binding = true
            try {
                Shizuku.bindUserService(userServiceArgs, connection)
            } catch (_: Throwable) {
                binding = false
                drainPending()
            }
        }
    }

    fun unbind() {
        try {
            if (userService != null) {
                Shizuku.unbindUserService(userServiceArgs, connection, true)
            }
        } catch (_: Throwable) {
        }
        userService = null
    }

    /** Runs [command] with whatever privilege the user's Shizuku/Sui session has. */
    fun exec(command: String, callback: (String?) -> Unit) {
        bind { svc ->
            if (svc == null) {
                callback(null)
            } else {
                try {
                    callback(svc.exec(command))
                } catch (_: Throwable) {
                    userService = null // stale binder — force a clean rebind next call
                    callback(null)
                }
            }
        }
    }

    fun execSilent(command: String, callback: (Boolean) -> Unit) {
        exec(command) { output -> callback(output != null && !output.startsWith("ERROR:")) }
    }
}
