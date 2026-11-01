package app.mull

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * The native half of push on Android: permission, the FCM token, and which
 * notification was tapped. The same `mull/push` channel as iOS's
 * PushChannel.swift, so lib/data/remote/push_service.dart does not know which
 * phone it is on.
 *
 * Deliberately thin. What a notification says is decided on the server (the
 * `push` edge function); what happens when one is tapped is decided in Dart.
 */
object PushChannel {
    /** Firebase's name for the token's kind, sent where iOS sends its APNs host. */
    private const val ENVIRONMENT = "fcm"
    private const val REQUEST_CODE = 4021
    private const val ASKED = "push_asked"

    private var channel: MethodChannel? = null
    private var token: String? = null
    private var pending: MethodChannel.Result? = null

    /**
     * The notification that opened the app, held until Dart asks for it. A tap
     * that cold-launches Mull arrives before Dart is listening, so telling it
     * once is not enough; Dart takes it when ready and it is cleared then.
     */
    private var opened: Map<String, String>? = null

    fun attach(messenger: BinaryMessenger, activity: Activity) {
        makeNoticesChannel(activity)
        val channel = MethodChannel(messenger, "mull/push")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(status(activity))
                "request" -> request(activity, result)
                "register" -> {
                    // As on iOS, every launch: the token can change (a restore,
                    // cleared app data) and nothing else says so.
                    register(activity)
                    result.success(null)
                }
                "token" -> result.success(token?.let { mapOf("token" to it, "environment" to ENVIRONMENT) })
                // Launchers badge from the notifications themselves.
                "setBadge" -> result.success(null)
                "takeOpened" -> {
                    result.success(opened)
                    opened = null
                }
                else -> result.notImplemented()
            }
        }
        this.channel = channel
    }

    /**
     * A tapped notification. Firebase posts it while Mull is closed and hands
     * its data to the launch intent, marked with a `google.message_id`.
     */
    fun didOpen(intent: Intent?) {
        val extras = intent?.extras ?: return
        if (extras.getString("google.message_id") == null) return
        opened = listOf("notice_id", "group_id", "kind")
            .mapNotNull { key -> extras.getString(key)?.let { key to it } }
            .toMap()
        // Handled once: a rotation recreates the activity with the same intent.
        extras.keySet().filter { it.startsWith("google.") }.forEach { intent.removeExtra(it) }
        channel?.invokeMethod("opened", null)
    }

    /** Forwarded from MainActivity, which is where Android answers. */
    fun onPermissionResult(activity: Activity, requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQUEST_CODE) return
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        if (granted) register(activity)
        pending?.success(granted)
        pending = null
    }

    /** The names iOS uses, so Dart reads both the same way. */
    private fun status(context: Context): String {
        if (!configured(context)) return "unavailable"
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.areNotificationsEnabled()) return "authorized"
        // Before Android 13 notifications are on unless turned off in Settings.
        if (Build.VERSION.SDK_INT < 33) return "denied"
        return if (prefs(context).getBoolean(ASKED, false)) "denied" else "notDetermined"
    }

    private fun request(activity: Activity, result: MethodChannel.Result) {
        if (!configured(activity)) return result.success(false)
        if (Build.VERSION.SDK_INT < 33) {
            register(activity)
            return result.success(status(activity) == "authorized")
        }
        prefs(activity).edit().putBoolean(ASKED, true).apply()
        pending?.success(false)
        pending = result
        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_CODE)
    }

    private fun register(context: Context) {
        if (!configured(context)) return
        FirebaseMessaging.getInstance().token.addOnSuccessListener { fresh ->
            token = fresh
            channel?.invokeMethod("token", mapOf("token" to fresh, "environment" to ENVIRONMENT))
        }
    }

    /**
     * Where a push lands in Settings → Notifications. Firebase falls back to a
     * channel called "Miscellaneous" when the one it is told about is missing.
     */
    private fun makeNoticesChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel("notices", "Notices", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "New bills, settle-ups and friend requests"
            },
        )
    }

    /** False in a build made without google-services.json. */
    private fun configured(context: Context) = FirebaseApp.getApps(context).isNotEmpty()

    private fun prefs(context: Context) = context.getSharedPreferences("mull_push", Context.MODE_PRIVATE)
}
