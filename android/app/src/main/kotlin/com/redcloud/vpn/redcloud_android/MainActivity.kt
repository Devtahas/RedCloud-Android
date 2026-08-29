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
    // مکان‌یابی باینری‌های Native
    // =========================================================================
    private fun getExecutableBinaryPath(binaryName: String): String? {
        val nativeDir = applicationInfo.nativeLibraryDir
        val nativeLib = File(nativeDir, "lib$binaryName.so")

        if (nativeLib.exists()) {
            logFlutter("[NativeLoader] Found native binary: ${nativeLib.absolutePath}")
            return nativeLib.absolutePath
        }

        val destinationFile = File(filesDir, binaryName)
        if (!destinationFile.exists() || destinationFile.length() == 0L) {
            val primaryAbi = Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"
            val assetPath = "bin/$primaryAbi/$binaryName"

            try {
                assets.open(assetPath).use { input ->
                    FileOutputStream(destinationFile).use { output ->
                        input.copyTo(output)
                    }
                }
                destinationFile.setExecutable(true, false)
                Runtime.getRuntime().exec("chmod 755 ${destinationFile.absolutePath}").waitFor()
                logFlutter("[NativeLoader] Extracted fallback binary to: ${destinationFile.absolutePath}")
            } catch (e: Exception) {
                logFlutter("[NativeLoader] Extraction error: ${e.message}")
            }
        } else {
            destinationFile.setExecutable(true, false)
        }

        return if (destinationFile.exists()) destinationFile.absolutePath else nativeLib.absolutePath
    }

    private fun prepareTorDataFiles() {
        val torDir = File(filesDir, "tor_data")
        if (!torDir.exists()) torDir.mkdirs()
        torDir.setReadable(true, true)
        torDir.setWritable(true, true)
        torDir.setExecutable(true, true)

        val geoipTarget = File(filesDir, "geoip")
        val geoip6Target = File(filesDir, "geoip6")

        if (!geoipTarget.exists() || geoipTarget.length() == 0L) {
            try {
                assets.open("tor/geoip").use { input ->
                    FileOutputStream(geoipTarget).use { output -> input.copyTo(output) }
                }
                logFlutter("[Tor-Init] geoip database prepared.")
            } catch (e: Exception) {
                logFlutter("[Tor-Init] Error extracting geoip: ${e.message}")
            }
        }

        if (!geoip6Target.exists() || geoip6Target.length() == 0L) {
            try {
                assets.open("tor/geoip6").use { input ->
                    FileOutputStream(geoip6Target).use { output -> input.copyTo(output) }
                }
                logFlutter("[Tor-Init] geoip6 database prepared.")
            } catch (e: Exception) {
                logFlutter("[Tor-Init] Error extracting geoip6: ${e.message}")
            }
        }
    }

    // =========================================================================
    // اجرای هسته تور (Tor Engine) با بهینه‌سازی سرعت و دی‌ان‌اس ضد نشت
    // =========================================================================
    private fun startTorEngine(socksPort: Int, upstreamPort: Int?, mode: String, customBridges: List<String>): Boolean {
        stopTorEngine()
        prepareTorDataFiles()

        val torBinary = getExecutableBinaryPath("tor")
        if (torBinary == null) {
            logFlutter("[Tor-Error] Could not locate tor binary!")
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

        // بهینه‌سازی سرعت و مصرف مدارها
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

        // زنجیره‌سازی با پراکسی اَتر مسک در صورت وجود
        if (upstreamPort != null && upstreamPort > 0) {
            torrcContent.append("Socks5Proxy 127.0.0.1:$upstreamPort\n")
            logFlutter("[Tor-Config] Chained outbound via Aether SOCKS: 127.0.0.1:$upstreamPort")
        }

        when (mode.lowercase()) {
            "snowflake" -> {
                torrcContent.append("UseBridges 1\n")
                torrcContent.append("ClientTransportPlugin snowflake exec ${getExecutableBinaryPath("snowflake") ?: "snowflake"}\n")
                torrcContent.append("Bridge snowflake 192.0.2.3:1 2B280B23E1107BB62ABFC40DDCC82248C5EC2F6E\n")
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
        logFlutter("[Tor-Config] Torrc configuration updated.")

        val command = listOf(torBinary, "-f", torrcFile.absolutePath)

        return try {
            val processBuilder = ProcessBuilder(command)
            processBuilder.directory(filesDir)
            val env = processBuilder.environment()
            env["HOME"] = filesDir.absolutePath
            env["TMPDIR"] = cacheDir.absolutePath
            env["LD_LIBRARY_PATH"] = applicationInfo.nativeLibraryDir
            processBuilder.redirectErrorStream(true)

            val process = processBuilder.start()
            torProcess = process
            logFlutter("[Tor-Process] Fast Tor spawned successfully")

            val bootstrapPattern = Pattern.compile("Bootstrapped\\s+(\\d+)%")

            thread {
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
                logFlutter("[Tor-Crash] Tor process terminated immediately with exit code: $exitCode")
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
            env["LD_LIBRARY_PATH"] = applicationInfo.nativeLibraryDir
            processBuilder.redirectErrorStream(true)

            val process = processBuilder.start()
            aetherProcess = process

            thread {
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
            // استفاده از IP مستقیم جهت جلوگیری از شکست DNS محلی حین تست سلامت اتصال
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