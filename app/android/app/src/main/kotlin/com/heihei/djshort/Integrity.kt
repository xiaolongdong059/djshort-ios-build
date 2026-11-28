package com.heihei.djshort

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket
import java.security.MessageDigest

/**
 * 完整性 / 运行环境自检（2026-11-26）。
 *
 * 目的不是"让破解变不可能"（不可能），而是把**改包重签**和**动态 hook** 这两条
 * 最省事的路堵掉，逼破解者至少付出改 so / 改壳的成本。
 *
 * 检测结果不直接崩 —— 而是让授权降级为「未激活」：正常用户误判最多是重输一次码，
 * 破解者拿到的包则播不了第 6 集以后。
 *
 * 三项：
 *  1. 包名 + 签名 SHA-256（防二次打包：改包必须重签，签名对不上）
 *  2. TracerPid（防 jdwp/gdb 附加调试）
 *  3. frida/xposed 特征（maps 关键字、常见落地路径、27042 端口）
 */
object Integrity {

    private const val PKG = "com.heihei.djshort"

    /** 当前 debug keystore 的证书指纹（2026-11-26 由 apksigner 取）。
     *  换 keystore（比如上架用正式签名）时**必须同步改这里**，否则全量降级。 */
    private const val EXPECTED_SIGN =
        "dbf842f2743f200b5beb0a16a67ec85628b298f6fbe2205cd65fba2c2e9ff8a1"

    fun signSha256(ctx: Context): String? = try {
        val pm = ctx.packageManager
        val certs = if (Build.VERSION.SDK_INT >= 28) {
            pm.getPackageInfo(ctx.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                .signingInfo?.apkContentsSigners
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(ctx.packageName, PackageManager.GET_SIGNATURES).signatures
        }
        val c = certs?.firstOrNull() ?: return null
        MessageDigest.getInstance("SHA-256")
            .digest(c.toByteArray())
            .joinToString("") { "%02x".format(it) }
    } catch (e: Exception) {
        null
    }

    fun report(ctx: Context): Map<String, Any> {
        val got = signSha256(ctx)
        return mapOf(
            "pkg" to (ctx.packageName == PKG),
            "sign" to (got == EXPECTED_SIGN),
            "signGot" to (got ?: "-"),
            "debugger" to debuggerAttached(),
            "hook" to hookLike(),
        )
    }

    private fun debuggerAttached(): Boolean = try {
        val st = File("/proc/self/status").readText()
        val m = Regex("TracerPid:\\s*(\\d+)").find(st)
        (m?.groupValues?.get(1)?.toIntOrNull() ?: 0) != 0
    } catch (e: Exception) {
        false
    }

    private fun hookLike(): Boolean {
        // ① 进程内存映射里的注入库特征（frida-gadget / gum 的 JS 线程）
        try {
            val maps = File("/proc/self/maps").readText()
            for (k in arrayOf("frida", "gum-js-loop", "linjector", "libgadget")) {
                if (maps.contains(k, ignoreCase = true)) return true
            }
        } catch (_: Exception) {
        }
        // ② 常见落地路径
        for (p in arrayOf(
            "/data/local/tmp/frida-server",
            "/data/local/tmp/re.frida.server",
            "/sdcard/frida-server",
        )) {
            try {
                if (File(p).exists()) return true
            } catch (_: Exception) {
            }
        }
        // ③ 默认端口监听（120ms 超时，别让启动变慢）
        return try {
            Socket().use { s ->
                s.connect(InetSocketAddress("127.0.0.1", 27042), 120)
                true
            }
        } catch (e: Exception) {
            false
        }
    }
}
