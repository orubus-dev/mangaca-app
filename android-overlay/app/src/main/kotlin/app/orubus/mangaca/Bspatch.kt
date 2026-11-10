package app.orubus.mangaca

import org.apache.commons.compress.compressors.bzip2.BZip2CompressorInputStream
import java.io.ByteArrayInputStream
import java.io.DataInputStream
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.security.MessageDigest

/**
 * bspatch — applies a BSDIFF40 delta patch to produce a new APK from the
 * one already installed on the device. Ported verbatim from the production
 * Orubus updater: a code-only release travels as a small patch instead of
 * the full APK, and the result must be byte-identical to the release asset
 * (same signature, same sha256) or it never reaches the installer.
 *
 * Patch format (BSDIFF40, what python-bsdiff4 writes):
 *   0..8   magic "BSDIFF40"
 *   8..32  three int64 lengths: control stream, diff stream, new size
 *          (bsdiff ints are little-endian MAGNITUDE, sign bit in byte 7)
 *   32..   three bzip2 streams back to back: control, diff, extra
 */
object Bspatch {

    private const val CHUNK = 256 * 1024

    /** bsdiff int64: little-endian magnitude, b[7]&0x80 is the sign. */
    private fun offtin(b: ByteArray, off: Int = 0): Long {
        var y = (b[off + 7].toInt() and 0x7F).toLong()
        for (i in 6 downTo 0) y = y * 256 + (b[off + i].toInt() and 0xFF)
        return if (b[off + 7].toInt() and 0x80 != 0) -y else y
    }

    private fun readFully(input: DataInputStream, buf: ByteArray, len: Int) {
        var done = 0
        while (done < len) {
            val n = input.read(buf, done, len - done)
            if (n < 0) throw IllegalStateException("patch stream ended early")
            done += n
        }
    }

    /**
     * Apply [patchFile] onto [oldFile] (the installed APK) → [newFile].
     * Returns the SHA-256 hex of the produced file on success, null on any
     * failure (caller falls back to a full download).
     */
    fun apply(oldFile: File, patchFile: File, newFile: File): String? = try {
        val patch = patchFile.readBytes()
        require(patch.size > 32 && String(patch, 0, 8, Charsets.US_ASCII) == "BSDIFF40") { "not a bsdiff patch" }
        val ctrlLen = offtin(patch, 8)
        val diffLen = offtin(patch, 16)
        val newSize = offtin(patch, 24)
        require(ctrlLen >= 0 && diffLen >= 0 && newSize > 0) { "corrupt patch header" }
        require(32 + ctrlLen + diffLen < patch.size) { "corrupt patch layout" }

        val ctrl = DataInputStream(BZip2CompressorInputStream(ByteArrayInputStream(patch, 32, ctrlLen.toInt())))
        val diff = DataInputStream(BZip2CompressorInputStream(ByteArrayInputStream(patch, 32 + ctrlLen.toInt(), diffLen.toInt())))
        val extra = DataInputStream(BZip2CompressorInputStream(ByteArrayInputStream(patch, 32 + ctrlLen.toInt() + diffLen.toInt(), patch.size - 32 - ctrlLen.toInt() - diffLen.toInt())))

        val oldLen = oldFile.length()
        val old = RandomAccessFile(oldFile, "r")
        val md = MessageDigest.getInstance("SHA-256")

        val tri = ByteArray(24)
        val dBuf = ByteArray(CHUNK)
        val oBuf = ByteArray(CHUNK)
        val outBuf = ByteArray(CHUNK)

        try {
            FileOutputStream(newFile).use { out ->
                var op = 0L
                var np = 0L
                while (np < newSize) {
                    readFully(ctrl, tri, 24)
                    val add = offtin(tri, 0); val ins = offtin(tri, 8); val seek = offtin(tri, 16)
                    require(add >= 0 && ins >= 0 && np + add + ins <= newSize) { "patch overruns new size" }

                    // 1. add pass: new = diff + old (old zero-padded past EOF)
                    var done = 0L
                    while (done < add) {
                        val n = minOf(CHUNK.toLong(), add - done).toInt()
                        readFully(diff, dBuf, n)
                        var got = 0
                        if (op + done < oldLen) {
                            old.seek(op + done)
                            val want = minOf(n.toLong(), oldLen - op - done).toInt()
                            while (got < want) {
                                val r = old.read(oBuf, got, want - got)
                                if (r < 0) break
                                got += r
                            }
                        }
                        for (j in 0 until n) {
                            val ov = if (j < got) oBuf[j].toInt() and 0xFF else 0
                            outBuf[j] = ((dBuf[j].toInt() and 0xFF) + ov).toByte()
                        }
                        out.write(outBuf, 0, n)
                        md.update(outBuf, 0, n)
                        done += n
                    }
                    np += add; op += add

                    // 2. insert pass: verbatim extra bytes
                    var ins2 = 0L
                    while (ins2 < ins) {
                        val n = minOf(CHUNK.toLong(), ins - ins2).toInt()
                        readFully(extra, outBuf, n)
                        out.write(outBuf, 0, n)
                        md.update(outBuf, 0, n)
                        ins2 += n
                    }
                    np += ins

                    // 3. signed seek in old
                    op += seek
                }
            }
        } finally {
            old.close()
        }
        md.digest().joinToString("") { "%02x".format(it) }
    } catch (t: Throwable) {
        android.util.Log.w("mangaca-upd", "bspatch failed: ${t.message}")
        try { newFile.delete() } catch (_: Exception) {}
        null
    }
}
