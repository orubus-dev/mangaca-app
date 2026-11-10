package app.orubus.mangaca

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller

/** Receives the PackageInstaller session result and surfaces the system
 *  confirm dialog (STATUS_PENDING_USER_ACTION) to the user. */
class UpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -999)
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                if (confirm != null) {
                    confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    try {
                        context.startActivity(confirm)
                    } catch (_: Exception) {}
                }
            }
            PackageInstaller.STATUS_SUCCESS -> {}
            else -> {}
        }
    }
}
