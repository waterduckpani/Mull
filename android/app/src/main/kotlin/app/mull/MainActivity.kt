package app.mull

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hands payments to UPI apps the Android way.
 *
 * iOS can only reach an app through its private URL scheme, which is why
 * lib/core/upi.dart keeps a list of them. Android has the real thing: every
 * UPI app answers `upi://pay`, and an intent can be addressed to one app by
 * its package. So the Dart side asks here which apps answer, and pays by
 * package rather than by scheme.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mull/upi").setMethodCallHandler { call, result ->
            when (call.method) {
                "installed" -> result.success(upiPackages())
                "pay" -> result.success(pay(call.argument<String>("uri")!!, call.argument<String>("package")))
                "open" -> result.success(open(call.argument<String>("package")!!))
                else -> result.notImplemented()
            }
        }
    }

    /** Packages of every app that will take a `upi://pay` link. */
    private fun upiPackages(): List<String> {
        val probe = Intent(Intent.ACTION_VIEW, Uri.parse("upi://pay"))
        val found = if (Build.VERSION.SDK_INT >= 33) {
            packageManager.queryIntentActivities(probe, PackageManager.ResolveInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(probe, 0)
        }
        return found.map { it.activityInfo.packageName }.distinct()
    }

    /**
     * Opens [uri] in [pkg], or offers every UPI app when [pkg] is null.
     *
     * A chooser rather than a plain VIEW: a default someone once ticked for
     * `upi:` (WhatsApp, often) would otherwise win without asking, which is
     * the iOS problem the picker exists to avoid.
     */
    private fun pay(uri: String, pkg: String?): Boolean {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri))
        return try {
            if (pkg != null) {
                intent.setPackage(pkg)
                startActivity(intent)
            } else {
                if (intent.resolveActivity(packageManager) == null) return false
                startActivity(Intent.createChooser(intent, "Pay with"))
            }
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    /** The app's own home screen, nothing filled in. */
    private fun open(pkg: String): Boolean {
        val launch = packageManager.getLaunchIntentForPackage(pkg) ?: return false
        return try {
            startActivity(launch)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }
}
