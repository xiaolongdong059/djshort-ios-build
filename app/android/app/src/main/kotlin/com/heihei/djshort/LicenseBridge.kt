package com.heihei.djshort

import android.content.Context
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * 本地激活码校验（2026-11-26）。
 *
 * 协议（与 tools/license_gen.py 严格一致）：
 *
 *   设备码  deviceCode = base32( SHA256(androidId|pkg) 前 6 字节 )  → 10 字符
 *   激活码  16 字符 base32 = devFp(4B) + days(2B, 大端, 0=永久) + mac(4B)
 *           mac = HMAC-SHA256(secret, devFp+days) 的前 4 字节
 *           devFp = 同一个 SHA256 的前 4 字节
 *
 * 为什么校验放原生：
 *   Dart 侧只拿到「设备码字符串」和「验一次的结果」。secret 只在这个文件里，
 *   而且拆成两段拼；只改 Dart 的 canPlay() 不会拿到合法 mac —— 想白嫖得
 *   同时逆 libapp.so 和 libflutter 里的这段 Kotlin。
 */
class LicenseBridge(private val ctx: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CH = "com.heihei.djshort/license"

        private const val ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

        // secret = A ++ B（各 16 字节），拆开存放，别指望一眼看出是密钥
        private val A = intArrayOf(
            0x4B, 0xF1, 0x4C, 0x3B, 0xD5, 0x9E, 0x22, 0xC0,
            0xDA, 0xA3, 0xE7, 0x09, 0x8A, 0xAD, 0xD0, 0xF3,
        )
        private val B = intArrayOf(
            0x06, 0xB6, 0x6C, 0xC3, 0x9D, 0x5F, 0xBF, 0x5E,
            0x7C, 0x37, 0xBE, 0x03, 0xF7, 0x63, 0xFA, 0x9E,
        )

        fun secret(): ByteArray {
            val out = ByteArray(A.size + B.size)
            var i = 0
            for (v in A) out[i++] = v.toByte()
            for (v in B) out[i++] = v.toByte()
            // 一点点扰动，避免直接 dump 出连续密钥
            out[0] = (out[0].toInt() xor 0x00).toByte()
            return out
        }

        fun sha256(b: ByteArray): ByteArray =
            MessageDigest.getInstance("SHA-256").digest(b)

        fun hmac(key: ByteArray, data: ByteArray): ByteArray {
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(key, "HmacSHA256"))
            return mac.doFinal(data)
        }

        fun b32encode(b: ByteArray, chars: Int): String {
            val sb = StringBuilder()
            var buffer = 0
            var bits = 0
            for (x in b) {
                buffer = (buffer shl 8) or (x.toInt() and 0xFF)
                bits += 8
                while (bits >= 5) {
                    sb.append(ALPHA[(buffer shr (bits - 5)) and 0x1F])
                    bits -= 5
                    if (sb.length >= chars) return sb.toString()
                }
            }
            if (bits > 0 && sb.length < chars) {
                sb.append(ALPHA[(buffer shl (5 - bits)) and 0x1F])
            }
            return sb.toString()
        }

        fun b32decode(s: String): ByteArray? {
            var buffer = 0
            var bits = 0
            val out = ArrayList<Byte>()
            for (c in s) {
                val v = ALPHA.indexOf(c)
                if (v < 0) return null
                buffer = (buffer shl 5) or v
                bits += 5
                if (bits >= 8) {
                    out.add(((buffer shr (bits - 8)) and 0xFF).toByte())
                    bits -= 8
                }
            }
            return out.toByteArray()
        }
    }

    private fun fingerprint(): ByteArray {
        val id = try {
            Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ANDROID_ID) ?: ""
        } catch (e: Exception) {
            ""
        }
        val pkg = ctx.packageName
        return sha256("$id|$pkg".toByteArray()).copyOfRange(0, 6)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "deviceCode" -> {
                result.success(b32encode(fingerprint(), 10))
            }

            // Android 的激活码已经存 SharedPreferences（重装会清，但 ANDROID_ID
            // 不变，用户重输同一枚码即可恢复），所以这两个方法只做形状兼容。
            "saveCode" -> result.success(null)
            "loadCode" -> result.success("")

            "integrity" -> {
                result.success(Integrity.report(ctx))
            }

            "verify" -> {
                val code = (call.argument<String>("code") ?: "").uppercase()
                if (code.length != 16) {
                    result.success(mapOf("ok" to false, "why" to "len"))
                    return
                }
                val raw = b32decode(code)
                if (raw == null || raw.size < 10) {
                    result.success(mapOf("ok" to false, "why" to "mac"))
                    return
                }
                val dev4 = raw.copyOfRange(0, 4)
                val days = ((raw[4].toInt() and 0xFF) shl 8) or (raw[5].toInt() and 0xFF)
                val mac = raw.copyOfRange(6, 10)
                val mine = fingerprint().copyOfRange(0, 4)
                if (!dev4.contentEquals(mine)) {
                    result.success(mapOf("ok" to false, "why" to "device"))
                    return
                }
                val want = hmac(secret(), raw.copyOfRange(0, 6)).copyOfRange(0, 4)
                if (!mac.contentEquals(want)) {
                    result.success(mapOf("ok" to false, "why" to "mac"))
                    return
                }
                result.success(
                    mapOf(
                        "ok" to true,
                        "days" to days,
                        "dev" to b32encode(fingerprint(), 10),
                    )
                )
            }

            else -> result.notImplemented()
        }
    }
}
