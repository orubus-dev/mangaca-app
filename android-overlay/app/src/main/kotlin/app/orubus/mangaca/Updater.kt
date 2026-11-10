package app.orubus.mangaca

import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/**
 * The MANGACA self-updater — the Orubus delta-update system, production
 * proven. release/updates.json (committed to the repo on every release)
 * lists the latest APK {version, code, url, sha256, size} plus optional
 * bsdiff deltas keyed by the version code they upgrade. A device behind
 * latest downloads just its delta, rebuilds the installed APK on device,
 * byte-verifies sha256, and hands the result to the system PackageInstaller.
 * Anything wrong at any step falls back to the plain full-APK path.
 */
object Updater {

    const val MANIFEST_URL =
        "https://raw.githubusercontent.com/orubus-dev/mangaca-app/main/release/updates.json"

    private const val MAX_DOWNLOAD = 400L * 1024 * 1024

    private val main = Handler(Looper.getMainLooper())

    /** progress events pushed into Flutter ('progress' method on the channel) */
    private var flutterChannel: MethodChannel? = null

    fun attach(channel: MethodChannel) {
        flutterChannel = channel
    }

    // ---------- manifest ----------

    private fun fetchManifest(): Pair<JSONObject, JSONObject?>? {
        return try {
            val c = URL(MANIFEST_URL).openConnection() as HttpURLConnection
            c.connectTimeout = 15_000
            c.readTimeout = 20_000
            c.setRequestProperty("User-Agent", "mangaca-app")
            val body = c.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
            c.disconnect()
            val j = JSONObject(body)
            val latest = j.optJSONObject("latest") ?: return null
            if (latest.optLong("code", 0) <= 0 || latest.optString("url").isBlank()) return null
            val installed = installedCode()
            var delta: JSONObject? = null
            val deltas = j.optJSONObject("deltas")
            val d = deltas?.optJSONObject(installed.toString())
            if (d != null && d.optLong("to", 0) == latest.optLong("code", 0) && d.optString("url").isNotBlank()) {
                delta = d
            }
            latest to delta
        } catch (e: Exception) {
            null
        }
    }

    fun installedCode(): Long = try {
        val ctx = AppContextHolder.get()
        ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionCode.toLong()
    } catch (_: Exception) {
        0L
    }

    fun installedName(): String = try {
        val ctx = AppContextHolder.get()
        ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName ?: "?"
    } catch (_: Exception) {
        "?"
    }

    fun installedInfo(): Map<String, Any> =
        mapOf("code" to installedCode(), "name" to (installedName() ?: "?"))

    // ---------- the check (called from Flutter Settings) ----------

    fun check(result: MethodChannel.Result) {
        Thread {
            val m = fetchManifest()
            main.post {
                try {
                    if (m == null) {
                        result.success(mapOf("ok" to false, "reason" to "update server unreachable"))
                        return@post
                    }
                    val (latest, delta) = m
                    val out = mutableMapOf<String, Any>(
                        "ok" to true,
                        "installedCode" to installedCode(),
                        "installedName" to (installedName() ?: "?"),
                        "latest" to jsonToMap(latest),
                    )
                    if (delta != null) out["delta"] = jsonToMap(delta)
                    result.success(out)
                } catch (e: Exception) {
                    result.success(mapOf("ok" to false, "reason" to (e.message ?: "check failed")))
                }
            }
        }.start()
    }

    private fun jsonToMap(j: JSONObject): Map<String, Any?> {
        val out = mutableMapOf<String, Any?>()
        for (key in j.keys()) out[key] = j.opt(key)
        return out
    }

    // ---------- the update pipeline ----------

    /**
     * payload: {latest: {code,name,url,sha256,size,notes}, delta: {from,to,url,size}|null}
     * Runs fully in the background; every stage reports progress into Flutter.
     */
    fun start(payload: Map<*, *>) {
        val latestRaw = payload["latest"] as? Map<*, *> ?: run {
            progress("error", 0.0, 0L, 0L, "no update payload")
            return
        }
        val latestUrl = (latestRaw["url"] ?: "").toString()
        val latestSha = (latestRaw["sha256"] ?: "").toString()
        val latestSize = ((latestRaw["size"] as? Number)?.toLong() ?: 0L)
        val deltaRaw = payload["delta"] as? Map<*, *>

        val ctx = AppContextHolder.get()
        Thread {
            val dir = File(ctx.cacheDir, "update").apply { mkdirs() }
            dir.listFiles()?.forEach { it.delete() } // idempotent: previous attempts never leak

            // --- the cheap path: rebuild the installed APK from a delta patch ---
            if (deltaRaw != null && latestSha.isNotBlank()) {
                val deltaUrl = (deltaRaw["url"] ?: "").toString()
                if (deltaUrl.isNotBlank()) {
                    progress("downloading", 0.0, 0L, ((deltaRaw["size"] as? Number)?.toLong() ?: 0L), "downloading delta patch…")
                    val patchFile = File(dir, "delta.bsdiff")
                    val sha = download(deltaUrl, patchFile) { rec, tot -> progress("downloading", pct(rec, tot), rec, tot, "downloading delta patch…") }
                    if (sha != null) {
                        progress("patching", 0.15, 0L, 0L, "rebuilding the app on device…")
                        val srcApk = File(ctx.applicationInfo.sourceDir ?: "")
                        val out = File(dir, "mangaca-new.apk")
                        val newSha = if (srcApk.exists()) Bspatch.apply(srcApk, patchFile, out) else null
                        if (newSha != null && latestSha.isNotBlank() && newSha.equals(latestSha, ignoreCase = true)) {
                            progress("verifying", 0.85, 0L, 0L, "verified against the release manifest")
                            install(out)
                            return@Thread
                        }
                        out.delete()
                        progress("downloading", 0.0, 0L, latestSize, "delta mismatch — falling back to the full APK…")
                    }
                    patchFile.delete()
                }
            }

            // --- the plain path: full APK from the release ---
            val apk = File(dir, "mangaca.apk")
            progress("downloading", 0.0, 0L, latestSize, "downloading the update…")
            val sha = download(latestUrl, apk) { rec, tot -> progress("downloading", pct(rec, tot), rec, tot, "downloading the update…") }
            if (sha == null) {
                progress("error", 0.0, 0L, 0L, "download failed — check the connection and try again")
                apk.delete()
                return@Thread
            }
            if (latestSha.isNotBlank() && !sha.equals(latestSha, ignoreCase = true)) {
                progress("error", 0.0, 0L, 0L, "the download didn't match — try again in a bit")
                apk.delete()
                return@Thread
            }
            progress("verifying", 0.9, 0L, 0L, "verified against the release manifest")
            install(apk)
        }.start()
    }

    private fun pct(rec: Long, tot: Long): Double =
        if (tot > 0) (rec.toDouble() / tot).coerceIn(0.0, 1.0) else 0.0

    private fun progress(stage: String, p: Double, received: Long, total: Long, message: String) {
        main.post {
            try {
                flutterChannel?.invokeMethod(
                    "progress",
                    mapOf(
                        "stage" to stage,
                        "progress" to p,
                        "received" to received,
                        "total" to total,
                        "message" to message,
                    ),
                )
            } catch (_: Exception) {}
        }
    }

    /** Streams [url] to [dest]; returns the file's SHA-256 hex, null on trouble. */
    private fun download(url: String, dest: File, onBytes: (Long, Long) -> Unit): String? = try {
        val c = URL(url).openConnection() as HttpURLConnection
        c.connectTimeout = 20_000
        c.readTimeout = 60_000
        c.instanceFollowRedirects = true
        c.setRequestProperty("User-Agent", "mangaca-app")
        val md = MessageDigest.getInstance("SHA-256")
        var total = 0L
        c.inputStream.use { input ->
            FileOutputStream(dest).use { out ->
                val buf = ByteArray(64 * 1024)
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    total += n
                    if (total > MAX_DOWNLOAD) throw IllegalStateException("absurd size")
                    out.write(buf, 0, n)
                    md.update(buf, 0, n)
                    onBytes(total, dest.length())
                }
            }
        }
        c.disconnect()
        md.digest().joinToString("") { "%02x".format(it) }
    } catch (e: Exception) {
        try { dest.delete() } catch (_: Exception) {}
        null
    }

    // ---------- the system handoff ----------

    private fun install(apk: File) {
        val ctx = AppContextHolder.get()
        // Android 8+: the user flips "allow MANGACA to install unknown apps"
        // once — then every future update is one tap, no browser, no store.
        if (Build.VERSION.SDK_INT >= 26 && !ctx.packageManager.canRequestPackageInstalls()) {
            if (ctx is Activity) {
                try {
                    ctx.startActivity(
                        Intent(
                            android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            android.net.Uri.parse("package:${ctx.packageName}"),
                        )
                    )
                    progress("installing", 1.0, 0L, 0L, "allow MANGACA to install updates — then tap UPDATE again")
                } catch (_: Exception) {
                    progress("error", 0.0, 0L, 0L, "couldn't open the install-permission screen")
                }
            } else {
                progress("error", 0.0, 0L, 0L, "install permission missing")
            }
            return
        }
        try {
            val pi = ctx.packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            val sessionId = pi.createSession(params)
            val session = pi.openSession(sessionId)
            apk.inputStream().use { input ->
                session.openWrite("mangaca.apk", 0, apk.length()).use { out ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        out.write(buf, 0, n)
                    }
                    session.fsync(out)
                }
            }
            val rec = Intent(ctx, UpdateReceiver::class.java).setPackage(ctx.packageName)
            val pending = PendingIntent.getBroadcast(
                ctx, sessionId, rec,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            )
            session.commit(pending.intentSender)
            session.close()
            progress("installing", 1.0, 0L, 0L, "ready — confirm the install in the system dialog")
        } catch (e: Exception) {
            progress("error", 0.0, 0L, 0L, "couldn't start the install — ${e.message ?: "try again"}")
        }
    }
}

/** Application context holder — set once in MainActivity.attachBaseContext. */
object AppContextHolder {
    private lateinit var appCtx: android.content.Context
    fun init(ctx: android.content.Context) {
        appCtx = ctx.applicationContext
    }
    fun get(): android.content.Context = appCtx
}
