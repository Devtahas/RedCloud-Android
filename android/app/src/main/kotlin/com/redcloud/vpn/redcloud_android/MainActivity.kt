package com.redcloud.vpn.redcloud_android

import android.os.Build
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.File
import java.io.FileOutputStream
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.Socket
import java.net.URL
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.TimeUnit
import java.util.regex.Pattern
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val TAG = "flutter"
    private val AETHER_CHANNEL = "com.redcloud.vpn/aether_channel"
    private val TOR_CHANNEL = "com.redcloud.vpn/tor_channel"

    private var aetherProcess: Process? = null
    private var torProcess: Process? = null

    @Volatile
    private var torBootstrapPercent: Int = 0

    @Volatile
    private var torLastLogLine: String = "آماده‌سازی"

    private val torLogsBuffer = ConcurrentLinkedQueue<String>()

    private fun logFlutter(message: String) {
        Log.i(TAG, message)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // =========================================================================
        // ۱. کانال متد اَتر (Aether Engine)
        // =========================================================================
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AETHER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAether" -> {
                    val mode = call.argument<String>("mode") ?: "auto"
                    val port = call.argument<Int>("port") ?: 1819
                    val noize = call.argument<String>("noize") ?: "firewall"
                    val customArgs = call.argument<List<String>>("args") ?: emptyList()

                    thread {
                        val launched = startAetherEngine(mode, port, noize, customArgs)
                        runOnUiThread {
                            if (launched) {
                                result.success(true)
                            } else {
                                result.error("START_FAILED", "امکان اجرای باینری Aether وجود ندارد", null)
                            }
                        }
                    }
                }

                "stopAether" -> {
                    stopAetherEngine()
                    result.success(true)
                }

                "isAetherRunning" -> {
                    result.success(aetherProcess?.isAlive == true)
                }

                "checkSocksReady" -> {
                    val port = call.argument<Int>("port") ?: 1819
                    val timeoutMs = call.argument<Int>("timeoutMs") ?: 1500

                    thread {
                        val isReady = testSocksPort(port, timeoutMs)
                        runOnUiThread {
                            result.success(isReady)
                        }
                    }
                }

                "testAetherEgress" -> {
                    val port = call.argument<Int>("port") ?: 1819
                    val timeoutMs = call.argument<Int>("timeoutMs") ?: 3500

                    thread {
                        val canPassTraffic = testHttpThroughSocks(port, timeoutMs)
                        runOnUiThread {
                            result.success(canPassTraffic)
                        }
                    }
                }

                "resetIdentity" -> {
                    val mode = call.argument<String>("mode")
                    if (mode != null) {
                        val modeDir = File(filesDir, "identity_${mode.lowercase()}")
                        if (modeDir.exists()) modeDir.deleteRecursively()
                    } else {
                        filesDir.listFiles()?.forEach { file ->
                            if (file.name.startsWith("identity_") || file.name == "tor_data") {
                                file.deleteRecursively()
                            }
                        }
                    }
                    result.success(true)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        // =========================================================================
        // ۲. کانال متد تور (Tor Engine)
        // =========================================================================
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TOR_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startTor" -> {
                    val socksPort = call.argument<Int>("socksPort") ?: 9050
                    val upstreamPort = call.argument<Int>("upstreamPort")
                    val mode = call.argument<String>("mode") ?: "aether_masque"
                    val customBridges = call.argument<List<String>>("bridges") ?: emptyList()

                    torBootstrapPercent = 0
                    torLastLogLine = "در حال راه‌اندازی هسته تور..."
                    torLogsBuffer.clear()

                    thread {
                        val launched = startTorEngine(socksPort, upstreamPort, mode, customBridges)
                        runOnUiThread {
                            if (launched) {
                                result.success(true)
                            } else {
                                result.error("TOR_START_FAILED", "خطا در استارت باینری تور", null)
                            }
                        }
                    }
                }

                "stopTor" -> {
                    stopTorEngine()
                    result.success(true)
                }

                "isTorRunning" -> {
                    result.success(torProcess?.isAlive == true)
                }

                "getTorStatus" -> {
                    val recentLogs = ArrayList(torLogsBuffer)
                    val statusMap = mapOf(
                        "percent" to torBootstrapPercent,
                        "lastLog" to torLastLogLine,
                        "isRunning" to (torProcess?.isAlive == true),
                        "logs" to recentLogs
                    )
                    result.success(statusMap)
                }

                "checkTorReady" -> {
                    val socksPort = call.argument<Int>("socksPort") ?: 9050
                    val timeoutMs = call.argument<Int>("timeoutMs") ?: 1200

                    thread {
                        val isReady = testSocksPort(socksPort, timeoutMs)
                        runOnUiThread {
                            result.success(isReady)
                        }
                    }
                }

                "killAllCores" -> {
                    stopTorEngine()
                    stopAetherEngine()
                    result.success(true)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    // =========================================================================
    // مکان‌یابی مستقیم و مطمئن باینری‌های Native
    // =========================================================================
    private fun getExecutableBinaryPath(binaryName: String): String? {
        val nativeDir = applicationInfo.nativeLibraryDir
        val nativeLib = File(nativeDir, "lib$binaryName.so")

        // ۱. اولویت اول: اجرای مستقیم از دایرکتوری رسمی jniLibs داخل APK
        if (nativeLib.exists() && nativeLib.length() > 0L) {
            nativeLib.setExecutable(true, false)
            logFlutter("[NativeLoader] Found native binary in libDir: ${nativeLib.absolutePath}")
            return nativeLib.absolutePath
        }

        // ۲. اولویت دوم: استخراج یا کپی در دایرکتوری محلی فایل‌ها
        val destinationFile = File(filesDir, binaryName)
        if (destinationFile.exists() && destinationFile.length() > 0L) {
            destinationFile.setExecutable(true, false)
            return destinationFile.absolutePath
        }

        val primaryAbi = Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"
        val possibleAssetPaths = listOf(
            "bin/$primaryAbi/$binaryName",
            "bin/$primaryAbi/lib$binaryName.so",
            "assets/bin/$primaryAbi/$binaryName",
            binaryName
        )

        for (assetPath in possibleAssetPaths) {
            try {
                assets.open(assetPath).use { input ->
                    FileOutputStream(destinationFile).use { output ->
                        input.copyTo(output)
                    }
                }
                if (destinationFile.exists() && destinationFile.length() > 0L) {
                    destinationFile.setExecutable(true, false)
                    try {
                        Runtime.getRuntime().exec("chmod 755 ${destinationFile.absolutePath}").waitFor()
                    } catch (_: Exception) {}
                    logFlutter("[NativeLoader] Extracted fallback asset $assetPath to: ${destinationFile.absolutePath}")
                    return destinationFile.absolutePath
                }
            } catch (_: Exception) {}
        }

        return if (nativeLib.exists()) nativeLib.absolutePath else null
    }

    private fun extractAssetFile(possiblePaths: List<String>, targetFile: File) {
        if (targetFile.exists() && targetFile.length() > 0L) return
        for (path in possiblePaths) {
            try {
                assets.open(path).use { input ->
                    FileOutputStream(targetFile).use { output -> input.copyTo(output) }
                }
                if (targetFile.exists() && targetFile.length() > 0L) {
                    logFlutter("[Tor-Init] Prepared asset $path at ${targetFile.absolutePath}")
                    return
                }
            } catch (_: Exception) {}
        }
    }

    private fun prepareTorDataFiles() {
        val torDir = File(filesDir, "tor_data")
        if (!torDir.exists()) torDir.mkdirs()
        torDir.setReadable(true, false)
        torDir.setWritable(true, false)
        torDir.setExecutable(true, false)

        val lockFile = File(torDir, "lock")
        if (lockFile.exists()) {
            try { lockFile.delete() } catch (_: Exception) {}
        }

        val geoipTarget = File(filesDir, "geoip")
        val geoip6Target = File(filesDir, "geoip6")

        extractAssetFile(listOf("tor/geoip", "assets/tor/geoip", "geoip"), geoipTarget)
        extractAssetFile(listOf("tor/geoip6", "assets/tor/geoip6", "geoip6"), geoip6Target)
    }

    // =========================================================================
    // اجرای هسته تور (Tor Engine)
    // =========================================================================
    private fun startTorEngine(socksPort: Int, upstreamPort: Int?, mode: String, customBridges: List<String>): Boolean {
        stopTorEngine()
        prepareTorDataFiles()

        val torBinary = getExecutableBinaryPath("tor")
        if (torBinary == null) {
            logFlutter("[Tor-Error] Could not locate executable tor binary!")
            return false
        }

        val torDataDir = File(filesDir, "tor_data")
        val geoipFile = File(filesDir, "geoip")
        val geoip6File = File(filesDir, "geoip6")
        val torrcFile = File(filesDir, "torrc")

        val torrcContent = StringBuilder()
        torrcContent.append("DataDirectory ${torDataDir.absolutePath}\n")
        torrcContent.append("DataDirectoryGroupReadable 1\n")
        torrcContent.append("RunAsDaemon 0\n")
        torrcContent.append("SocksPort 127.0.0.1:$socksPort\n")
        torrcContent.append("DNSPort 127.0.0.1:5350\n")
        torrcContent.append("AutomapHostsOnResolve 1\n")
        torrcContent.append("VirtualAddrNetworkIPv4 10.192.0.0/10\n")
        torrcContent.append("ClientOnly 1\n")
        torrcContent.append("AvoidDiskWrites 1\n")
        torrcContent.append("Log notice stdout\n")

        torrcContent.append("UseEntryGuards 0\n")
        torrcContent.append("ConnectionPadding 0\n")
        torrcContent.append("ReducedConnectionPadding 1\n")
        torrcContent.append("MaxCircuitDirtiness 600\n")

        if (geoipFile.exists()) {
            torrcContent.append("GeoIPFile ${geoipFile.absolutePath}\n")
        }
        if (geoip6File.exists()) {
            torrcContent.append("GeoIPv6File ${geoip6File.absolutePath}\n")
        }

        if (upstreamPort != null && upstreamPort > 0) {
            torrcContent.append("Socks5Proxy 127.0.0.1:$upstreamPort\n")
            logFlutter("[Tor-Config] Chained outbound via Aether SOCKS: 127.0.0.1:$upstreamPort")
        }

        when (mode.lowercase()) {
            "snowflake" -> {
                val snowflakePath = getExecutableBinaryPath("snowflake")
                if (snowflakePath != null) {
                    torrcContent.append("UseBridges 1\n")
                    torrcContent.append("ClientTransportPlugin snowflake exec $snowflakePath\n")
                    torrcContent.append("Bridge snowflake 192.0.2.3:1 2B280B23E1107BB62ABFC40DDCC82248C5EC2F6E\n")
                }
            }
            "obfs4" -> {
                val obfsPath = getExecutableBinaryPath("obfs4proxy")
                if (obfsPath != null) {
                    torrcContent.append("UseBridges 1\n")
                    torrcContent.append("ClientTransportPlugin obfs4 exec $obfsPath\n")
                }
            }
            "custom" -> {
                if (customBridges.isNotEmpty()) {
                    torrcContent.append("UseBridges 1\n")
                    for (bridge in customBridges) {
                        if (bridge.isNotBlank()) {
                            torrcContent.append("Bridge ${bridge.trim()}\n")
                        }
                    }
                }
            }
        }

        torrcFile.writeText(torrcContent.toString())
        logFlutter("[Tor-Config] Torrc configuration prepared.")

        val command = listOf(torBinary, "-f", torrcFile.absolutePath)

        return try {
            val processBuilder = ProcessBuilder(command)
            processBuilder.directory(filesDir)
            val env = processBuilder.environment()
            env["HOME"] = filesDir.absolutePath
            env["TMPDIR"] = cacheDir.absolutePath
            env["LD_LIBRARY_PATH"] = "${applicationInfo.nativeLibraryDir}:/system/lib64:/system/lib"
            processBuilder.redirectErrorStream(true)

            val process = processBuilder.start()
            torProcess = process
            logFlutter("[Tor-Process] Tor process spawned successfully.")

            val bootstrapPattern = Pattern.compile("Bootstrapped\\s+(\\d+)%")

            thread(isDaemon = true) {
                try {
                    val reader = BufferedReader(InputStreamReader(process.inputStream))
                    reader.forEachLine { line ->
                        torLastLogLine = line
                        if (torLogsBuffer.size > 20) torLogsBuffer.poll()
                        torLogsBuffer.offer(line)

                        val matcher = bootstrapPattern.matcher(line)
                        if (matcher.find()) {
                            val percent = matcher.group(1)?.toIntOrNull()
                            if (percent != null) {
                                torBootstrapPercent = percent
                            }
                        }
                        logFlutter("[Tor-Log]: $line")
                    }
                } catch (e: Exception) {
                    logFlutter("[Tor-Reader-Error]: ${e.message}")
                }
            }

            Thread.sleep(400)
            if (!process.isAlive) {
                val exitCode = process.exitValue()
                logFlutter("[Tor-Crash] Tor process died with code: $exitCode")
                return false
            }

            true
        } catch (e: Exception) {
            logFlutter("[Tor-Error] Launch failed: ${e.message}")
            e.printStackTrace()
            false
        }
    }

    private fun stopTorEngine() {
        try {
            torProcess?.let { process ->
                if (process.isAlive) {
                    process.destroy()
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        process.destroyForcibly()
                        process.waitFor(500, TimeUnit.MILLISECONDS)
                    }
                }
            }
        } catch (e: Exception) {
            logFlutter("[Tor-Stop-Error]: ${e.message}")
        } finally {
            torProcess = null
            torBootstrapPercent = 0
            torLastLogLine = "متوقف شد"
        }
    }

    // =========================================================================
    // اجرای هسته اتر (Aether Engine)
    // =========================================================================
    private fun startAetherEngine(mode: String, port: Int, noize: String, extraArgs: List<String>): Boolean {
        stopAetherEngine()

        val binaryPath = getExecutableBinaryPath("aether") ?: return false
        val command = mutableListOf<String>()
        command.add(binaryPath)
        command.add("--bind")
        command.add("127.0.0.1:$port")
        command.add("-4")
        command.add("--turbo")
        command.add("--quick-reconnect")
        command.add("--noize")
        command.add(noize)

        val normalizedMode = mode.lowercase()
        val modeDir = File(filesDir, "identity_$normalizedMode")
        if (!modeDir.exists()) modeDir.mkdirs()

        when (normalizedMode) {
            "auto", "masque_h2", "h2" -> {
                command.add("--h2")
                command.add("--fragment")
                command.add("--fragment-size")
                command.add("16-32")
                command.add("--fragment-delay")
                command.add("2-8")
            }
            "masque", "masque_h3" -> {
                command.add("--masque")
            }
            "wireguard", "wg" -> {
                command.add("--wireguard")
                command.add("--keepalive")
                command.add("5")
            }
            "gool", "warp_in_warp" -> {
                command.add("--gool")
                command.add("--keepalive")
                command.add("5")
            }
            else -> {
                command.add("--h2")
                command.add("--fragment")
            }
        }

        command.addAll(extraArgs)
        logFlutter("[Aether-Cmd]: ${command.joinToString(" ")}")

        return try {
            val processBuilder = ProcessBuilder(command)
            processBuilder.directory(modeDir)
            val env = processBuilder.environment()
            env["HOME"] = filesDir.absolutePath
            env["TMPDIR"] = cacheDir.absolutePath
            env["LD_LIBRARY_PATH"] = "${applicationInfo.nativeLibraryDir}:/system/lib64:/system/lib"
            processBuilder.redirectErrorStream(true)

            val process = processBuilder.start()
            aetherProcess = process

            thread(isDaemon = true) {
                try {
                    val reader = BufferedReader(InputStreamReader(process.inputStream))
                    reader.forEachLine { line ->
                        logFlutter("[Aether-Log]: $line")
                    }
                } catch (_: Exception) {}
            }

            Thread.sleep(300)
            if (!process.isAlive) {
                logFlutter("[Aether-Crash] Process died with code: ${process.exitValue()}")
                return false
            }

            true
        } catch (e: Exception) {
            logFlutter("[Aether-Error] Failed to start: ${e.message}")
            false
        }
    }

    private fun stopAetherEngine() {
        try {
            aetherProcess?.let { process ->
                if (process.isAlive) {
                    process.destroy()
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        process.destroyForcibly()
                        process.waitFor(500, TimeUnit.MILLISECONDS)
                    }
                }
            }
        } catch (e: Exception) {
            logFlutter("[Aether-Stop-Error]: ${e.message}")
        } finally {
            aetherProcess = null
        }
    }

    private fun testSocksPort(port: Int, timeoutMs: Int): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress("127.0.0.1", port), timeoutMs)
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun testHttpThroughSocks(socksPort: Int, timeoutMs: Int): Boolean {
        return try {
            val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", socksPort))
            val url = URL("http://1.1.1.1/generate_204")
            val connection = url.openConnection(proxy) as HttpURLConnection
            connection.connectTimeout = timeoutMs
            connection.readTimeout = timeoutMs
            connection.instanceFollowRedirects = false
            connection.requestMethod = "GET"
            val responseCode = connection.responseCode
            connection.disconnect()
            logFlutter("[Aether-Probe] Egress HTTP probe status code: $responseCode")
            responseCode in 200..399
        } catch (e: Exception) {
            logFlutter("[Aether-Probe] Egress HTTP probe failed: ${e.message}")
            false
        }
    }

    override fun onDestroy() {
        stopAetherEngine()
        stopTorEngine()
        super.onDestroy()
    }
}