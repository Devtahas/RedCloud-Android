package com.redcloud.vpn.redcloud_android

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.FileOutputStream
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.Socket
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.TimeUnit
import java.util.regex.Pattern
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "RedCloudNative"
        private const val AETHER_CHANNEL = "com.redcloud.vpn/aether_channel"
        private const val TOR_CHANNEL = "com.redcloud.vpn/tor_channel"

        @Volatile
        var aetherProcess: Process? = null

        @Volatile
        var torProcess: Process? = null

        @Volatile
        var torBootstrapPercent: Int = 0

        @Volatile
        var torLastLogLine: String = "آماده‌سازی"

        private const val MAX_NATIVE_LOGS = 400
        val nativeLogsBuffer = ConcurrentLinkedQueue<String>()

        @Volatile
        private var wakeLock: PowerManager.WakeLock? = null

        fun appendNativeLog(tag: String, message: String) {
            val timestamp = SimpleDateFormat("HH:mm:ss.SSS", Locale.US).format(Date())
            val formattedLog = "[$timestamp] [$tag] $message"
            Log.i(TAG, formattedLog)

            while (nativeLogsBuffer.size >= MAX_NATIVE_LOGS) {
                nativeLogsBuffer.poll()
            }
            nativeLogsBuffer.offer(formattedLog)
        }
    }

    @SuppressLint("WakelockTimeout")
    private fun acquireWakeLock() {
        try {
            if (wakeLock == null) {
                val powerManager = applicationContext.getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = powerManager.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "RedCloudVPN::CoreWakeLock"
                )
                wakeLock?.setReferenceCounted(false)
            }
            if (wakeLock?.isHeld == false) {
                wakeLock?.acquire()
                appendNativeLog("Power", "قفل پردازنده (WakeLock) فعال شد.")
            }
        } catch (e: Exception) {
            appendNativeLog("PowerError", "خطا در فعال‌سازی WakeLock: ${e.message}")
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
                appendNativeLog("Power", "قفل پردازنده (WakeLock) آزاد شد.")
            }
        } catch (e: Exception) {
            appendNativeLog("PowerError", "خطا در آزادسازی WakeLock: ${e.message}")
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = applicationContext.getSystemService(Context.POWER_SERVICE) as PowerManager
            powerManager.isIgnoringBatteryOptimizations(packageName)
        } else {
            true
        }
    }

    @SuppressLint("BatteryLife")
    private fun requestIgnoreBatteryOptimizations() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !isIgnoringBatteryOptimizations()) {
            try {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
                appendNativeLog("Power", "درخواست عدم بهینه‌سازی باتری ارسال شد.")
            } catch (e: Exception) {
                try {
                    val fallbackIntent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                    startActivity(fallbackIntent)
                } catch (_: Exception) {}
            }
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // =========================================================================
        // ۱. کانال متد هسته اَتر (Aether Engine)
        // =========================================================================
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AETHER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAether" -> {
                    val mode = call.argument<String>("mode") ?: "auto"
                    val port = call.argument<Int>("port") ?: 1819
                    val noize = call.argument<String>("noize")
                    val customArgs = call.argument<List<String>>("args") ?: emptyList()

                    thread {
                        val launched = startAetherEngine(mode, port, noize, customArgs)
                        runOnUiThread {
                            if (launched) {
                                acquireWakeLock()
                                RedCloudCoreService.start(applicationContext)
                                result.success(true)
                            } else {
                                result.error("START_FAILED", "امکان اجرای باینری Aether وجود ندارد", null)
                            }
                        }
                    }
                }

                "stopAether" -> {
                    stopAetherEngine()
                    if (torProcess == null || torProcess?.isAlive == false) {
                        releaseWakeLock()
                        RedCloudCoreService.stop(applicationContext)
                    }
                    result.success(true)
                }

                "isAetherRunning" -> {
                    result.success(aetherProcess?.isAlive == true)
                }

                "checkSocksReady" -> {
                    val port = call.argument<Int>("port") ?: 1819
                    val timeoutMs = call.argument<Int>("timeoutMs") ?: 1500

                    thread {
                        val isReady = testSocksPort("Aether", port, timeoutMs)
                        runOnUiThread { result.success(isReady) }
                    }
                }

                "testAetherEgress" -> {
                    val port = call.argument<Int>("port") ?: 1819
                    val timeoutMs = call.argument<Int>("timeoutMs") ?: 3500

                    thread {
                        val canPassTraffic = testHttpThroughSocks(port, timeoutMs)
                        runOnUiThread { result.success(canPassTraffic) }
                    }
                }

                "getTunneledIpInfo" -> {
                    val port = call.argument<Int>("socksPort") ?: 1819
                    val timeoutMs = call.argument<Int>("timeoutMs") ?: 6000

                    thread {
                        val info = fetchTunneledIp(port, timeoutMs)
                        runOnUiThread { result.success(info) }
                    }
                }

                "resetIdentity" -> {
                    val mode = call.argument<String>("mode")
                    thread {
                        try {
                            if (mode != null) {
                                val modeDir = File(filesDir, "identity_${mode.lowercase()}")
                                if (modeDir.exists()) modeDir.deleteRecursively()
                                appendNativeLog("Aether", "دایرکتوری هویت برای حالت $mode بازنشانی شد.")
                            } else {
                                filesDir.listFiles()?.forEach { file ->
                                    if (file.name.startsWith("identity_") || file.name == "tor_data") {
                                        file.deleteRecursively()
                                    }
                                }
                                appendNativeLog("Aether", "تمام هویت‌ها و فایل‌های کش پاک‌سازی شدند.")
                            }
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            appendNativeLog("Error", "خطا در ریست هویت: ${e.message}")
                            runOnUiThread { result.error("RESET_ERR", e.message, null) }
                        }
                    }
                }

                "isIgnoringBatteryOptimizations" -> {
                    result.success(isIgnoringBatteryOptimizations())
                }

                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(true)
                }

                "getNativeLogs" -> {
                    result.success(ArrayList(nativeLogsBuffer))
                }

                "clearNativeLogs" -> {
                    nativeLogsBuffer.clear()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        // =========================================================================
        // ۲. کانال متد هسته تور (Tor Engine)
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

                    thread {
                        val launched = startTorEngine(socksPort, upstreamPort, mode, customBridges)
                        runOnUiThread {
                            if (launched) {
                                acquireWakeLock()
                                RedCloudCoreService.start(applicationContext)
                                result.success(true)
                            } else {
                                result.error("TOR_START_FAILED", "خطا در اجرای باینری تور", null)
                            }
                        }
                    }
                }

                "stopTor" -> {
                    stopTorEngine()
                    if (aetherProcess == null || aetherProcess?.isAlive == false) {
                        releaseWakeLock()
                        RedCloudCoreService.stop(applicationContext)
                    }
                    result.success(true)
                }

                "isTorRunning" -> {
                    result.success(torProcess?.isAlive == true)
                }

                "getTorStatus" -> {
                    val statusMap = mapOf(
                        "percent" to torBootstrapPercent,
                        "lastLog" to torLastLogLine,
                        "isRunning" to (torProcess?.isAlive == true)
                    )
                    result.success(statusMap)
                }

                "checkTorReady" -> {
                    val socksPort = call.argument<Int>("socksPort") ?: 9050
                    val timeoutMs = call.argument<Int>("timeoutMs") ?: 1200

                    thread {
                        val isReady = testSocksPort("Tor", socksPort, timeoutMs)
                        runOnUiThread { result.success(isReady) }
                    }
                }

                "getTunneledIpInfo" -> {
                    val port = call.argument<Int>("socksPort") ?: 9050
                    val timeoutMs = call.argument<Int>("timeoutMs") ?: 7000

                    thread {
                        val info = fetchTunneledIp(port, timeoutMs)
                        runOnUiThread { result.success(info) }
                    }
                }

                "killAllCores" -> {
                    appendNativeLog("Lifecycle", "متوقف‌سازی تمامی هسته‌ها و آزادسازی کامل حافظه...")
                    stopTorEngine()
                    stopAetherEngine()
                    releaseWakeLock()
                    RedCloudCoreService.stop(applicationContext)
                    result.success(true)
                }

                "isIgnoringBatteryOptimizations" -> {
                    result.success(isIgnoringBatteryOptimizations())
                }

                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(true)
                }

                "getNativeLogs" -> {
                    result.success(ArrayList(nativeLogsBuffer))
                }

                "clearNativeLogs" -> {
                    nativeLogsBuffer.clear()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun getExecutableBinaryPath(binaryName: String): String? {
        val nativeDir = applicationInfo.nativeLibraryDir
        val nativeLib = File(nativeDir, "lib$binaryName.so")

        if (nativeLib.exists() && nativeLib.length() > 0L) {
            nativeLib.setExecutable(true, false)
            appendNativeLog("NativeLoader", "یافتن باینری در libDir: ${nativeLib.absolutePath} (${nativeLib.length()} bytes)")
            return nativeLib.absolutePath
        }

        val destinationFile = File(filesDir, binaryName)
        if (destinationFile.exists() && destinationFile.length() > 0L) {
            destinationFile.setExecutable(true, false)
            appendNativeLog("NativeLoader", "استفاده از باینری موجود در filesDir: ${destinationFile.absolutePath}")
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
                    FileOutputStream(destinationFile).use { output -> input.copyTo(output) }
                }
                if (destinationFile.exists() && destinationFile.length() > 0L) {
                    destinationFile.setExecutable(true, false)
                    try {
                        Runtime.getRuntime().exec("chmod 755 ${destinationFile.absolutePath}").waitFor()
                    } catch (_: Exception) {}
                    appendNativeLog("NativeLoader", "استخراج باینری از $assetPath به ${destinationFile.absolutePath}")
                    return destinationFile.absolutePath
                }
            } catch (_: Exception) {}
        }

        appendNativeLog("NativeLoader", "هشدار: باینری $binaryName در هیچ مسیری یافت نشد.")
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
                    appendNativeLog("TorInit", "فایل دارایی آماده شد: $path -> ${targetFile.absolutePath}")
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
            try {
                lockFile.delete()
                appendNativeLog("TorInit", "فایل lock قدیمی حذف شد.")
            } catch (_: Exception) {}
        }

        val geoipTarget = File(filesDir, "geoip")
        val geoip6Target = File(filesDir, "geoip6")

        extractAssetFile(listOf("tor/geoip", "assets/tor/geoip", "geoip"), geoipTarget)
        extractAssetFile(listOf("tor/geoip6", "assets/tor/geoip6", "geoip6"), geoip6Target)
    }

    private fun startTorEngine(socksPort: Int, upstreamPort: Int?, mode: String, customBridges: List<String>): Boolean {
        stopTorEngine()
        prepareTorDataFiles()

        val torBinary = getExecutableBinaryPath("tor")
        if (torBinary == null) {
            appendNativeLog("TorError", "عدم دسترسی به باینری tor.")
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
            appendNativeLog("TorConfig", "اتصال تور از بستر پراکسی بالادستی ساکس: 127.0.0.1:$upstreamPort")
        }

        when (mode.lowercase()) {
            "snowflake" -> {
                val snowflakePath = getExecutableBinaryPath("snowflake")
                if (snowflakePath != null) {
                    torrcContent.append("UseBridges 1\n")
                    torrcContent.append("ClientTransportPlugin snowflake exec $snowflakePath\n")
                    torrcContent.append("Bridge snowflake 192.0.2.3:1 2B280B23E1107BB62ABFC40DDCC82248C5EC2F6E\n")
                    appendNativeLog("TorConfig", "پلاگین Snowflake فعال شد.")
                }
            }
            "obfs4" -> {
                val obfsPath = getExecutableBinaryPath("obfs4proxy")
                if (obfsPath != null) {
                    torrcContent.append("UseBridges 1\n")
                    torrcContent.append("ClientTransportPlugin obfs4 exec $obfsPath\n")
                    appendNativeLog("TorConfig", "پلاگین obfs4 فعال شد.")
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
                    appendNativeLog("TorConfig", "تعداد ${customBridges.size} پل اختصاصی تزریق شد.")
                }
            }
        }

        torrcFile.writeText(torrcContent.toString())
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
            appendNativeLog("TorProcess", "پروسس تور آغاز شد.")

            val bootstrapPattern = Pattern.compile("Bootstrapped\\s+(\\d+)%")

            thread(isDaemon = true) {
                try {
                    val reader = BufferedReader(InputStreamReader(process.inputStream))
                    reader.forEachLine { line ->
                        torLastLogLine = line
                        appendNativeLog("TorCore", line)

                        val matcher = bootstrapPattern.matcher(line)
                        if (matcher.find()) {
                            val percent = matcher.group(1)?.toIntOrNull()
                            if (percent != null) {
                                torBootstrapPercent = percent
                            }
                        }
                    }
                } catch (e: Exception) {
                    appendNativeLog("TorReaderError", "خطا در خواندن لاگ تور: ${e.message}")
                }
            }

            Thread.sleep(400)
            if (!process.isAlive) {
                val exitCode = process.exitValue()
                appendNativeLog("TorCrash", "پروسس تور متوقف شد با کد خروج: $exitCode")
                return false
            }

            true
        } catch (e: Exception) {
            appendNativeLog("TorError", "خطا در اجرای تور: ${e.message}")
            false
        }
    }

    private fun stopTorEngine() {
        try {
            torProcess?.let { process ->
                if (process.isAlive) {
                    appendNativeLog("TorLifecycle", "در حال توقف هسته تور...")
                    process.destroy()
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        process.destroyForcibly()
                        process.waitFor(300, TimeUnit.MILLISECONDS)
                    }
                }
            }
        } catch (e: Exception) {
            appendNativeLog("TorStopError", "خطا در توقف تور: ${e.message}")
        } finally {
            torProcess = null
            torBootstrapPercent = 0
            torLastLogLine = "متوقف شد"
        }
    }

    private fun startAetherEngine(mode: String, port: Int, customNoize: String?, extraArgs: List<String>): Boolean {
        stopAetherEngine()

        val binaryPath = getExecutableBinaryPath("aether") ?: run {
            appendNativeLog("AetherError", "باینری aether یافت نشد.")
            return false
        }

        val normalizedMode = mode.lowercase()
        val modeDir = File(filesDir, "identity_$normalizedMode")
        if (!modeDir.exists()) {
            modeDir.mkdirs()
        }

        try {
            modeDir.listFiles()?.forEach { file ->
                if (file.name.endsWith(".toml") || file.name.contains("cache") || file.name.contains("endpoint")) {
                    file.delete()
                    appendNativeLog("AetherClean", "کَش قدیمی اندپوینت حذف شد: ${file.name}")
                }
            }
        } catch (_: Exception) {}

        val command = mutableListOf<String>()
        command.add(binaryPath)
        command.add("--bind")
        command.add("127.0.0.1:$port")
        command.add("-4")
        command.add("--startup-secs")
        command.add("30")

        when (normalizedMode) {
            "auto", "masque_h2", "h2" -> {
                command.add("--h2")
                command.add("--fragment")
                command.add("--fragment-size")
                command.add("16-32")
                command.add("--fragment-delay")
                command.add("2-8")
                command.add("--noize")
                command.add(customNoize ?: "firewall")
                command.add("--turbo")
            }
            "masque", "masque_h3", "quic" -> {
                command.add("--masque")
                command.add("--noize")
                command.add(customNoize ?: "quic")
                command.add("--turbo")
            }
            "wireguard", "wg" -> {
                command.add("--wireguard")
                command.add("--noize")
                command.add(customNoize ?: "gfw")
                command.add("--keepalive")
                command.add("25")
                command.add("--turbo")
            }
            "gool", "warp_in_warp" -> {
                command.add("--gool")
                command.add("--noize")
                command.add(customNoize ?: "firewall")
                command.add("--keepalive")
                command.add("25")
                command.add("--turbo")
            }
            else -> {
                command.add("--h2")
                command.add("--fragment")
                command.add("--noize")
                command.add("firewall")
                command.add("--turbo")
            }
        }

        command.addAll(extraArgs)
        appendNativeLog("AetherCommand", command.joinToString(" "))

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
            appendNativeLog("AetherProcess", "پروسس اَتر شروع شد.")

            thread(isDaemon = true) {
                try {
                    val reader = BufferedReader(InputStreamReader(process.inputStream))
                    reader.forEachLine { line ->
                        appendNativeLog("AetherCore", line)
                    }
                } catch (_: Exception) {}
            }

            Thread.sleep(400)
            if (!process.isAlive) {
                val exitCode = process.exitValue()
                appendNativeLog("AetherCrash", "اَتر با کد خروج متوقف شد: $exitCode")
                return false
            }

            true
        } catch (e: Exception) {
            appendNativeLog("AetherError", "خطا در استارت Aether: ${e.message}")
            false
        }
    }

    private fun stopAetherEngine() {
        try {
            aetherProcess?.let { process ->
                if (process.isAlive) {
                    appendNativeLog("AetherLifecycle", "در حال توقف هسته اَتر...")
                    process.destroy()
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        process.destroyForcibly()
                        process.waitFor(400, TimeUnit.MILLISECONDS)
                    }
                }
            }
        } catch (e: Exception) {
            appendNativeLog("AetherStopError", "خطا در توقف اَتر: ${e.message}")
        } finally {
            aetherProcess = null
        }
    }

    private fun testSocksPort(engineName: String, port: Int, timeoutMs: Int): Boolean {
        val start = System.currentTimeMillis()
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress("127.0.0.1", port), timeoutMs)
                val elapsed = System.currentTimeMillis() - start
                appendNativeLog("Probe", "$engineName ساکس پورت $port آماده است (${elapsed}ms)")
                true
            }
        } catch (e: Exception) {
            val elapsed = System.currentTimeMillis() - start
            appendNativeLog("Probe", "$engineName پورت $port هنوز آماده نیست (${elapsed}ms)")
            false
        }
    }

    private fun testHttpThroughSocks(socksPort: Int, timeoutMs: Int): Boolean {
        val start = System.currentTimeMillis()
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
            val elapsed = System.currentTimeMillis() - start
            val success = responseCode in 200..399
            appendNativeLog("Probe", "تست گذردهی ترافیک اَتر -> کد: $responseCode (${elapsed}ms)")
            success
        } catch (e: Exception) {
            val elapsed = System.currentTimeMillis() - start
            appendNativeLog("Probe", "تست گذردهی ترافیک اَتر ناموفق بود (${elapsed}ms): ${e.message}")
            false
        }
    }

    private fun fetchTunneledIp(socksPort: Int, timeoutMs: Int): Map<String, Any>? {
        val start = System.currentTimeMillis()
        return try {
            val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", socksPort))
            val url = URL("http://ip-api.com/json/")
            val connection = url.openConnection(proxy) as HttpURLConnection
            connection.connectTimeout = timeoutMs
            connection.readTimeout = timeoutMs
            connection.requestMethod = "GET"
            connection.instanceFollowRedirects = true

            if (connection.responseCode in 200..299) {
                val responseText = connection.inputStream.bufferedReader().use { it.readText() }
                val elapsed = (System.currentTimeMillis() - start).toInt()
                connection.disconnect()

                val jsonObj = JSONObject(responseText)
                if (jsonObj.optString("status") == "success") {
                    mapOf(
                        "ip" to jsonObj.optString("query"),
                        "country" to jsonObj.optString("country"),
                        "countryCode" to jsonObj.optString("countryCode"),
                        "pingMs" to elapsed
                    )
                } else {
                    null
                }
            } else {
                connection.disconnect()
                null
            }
        } catch (e: Exception) {
            try {
                val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", socksPort))
                val url = URL("https://cloudflare.com/cdn-cgi/trace")
                val connection = url.openConnection(proxy) as HttpURLConnection
                connection.connectTimeout = timeoutMs
                connection.readTimeout = timeoutMs
                connection.requestMethod = "GET"

                if (connection.responseCode in 200..299) {
                    val responseText = connection.inputStream.bufferedReader().use { it.readText() }
                    val elapsed = (System.currentTimeMillis() - start).toInt()
                    connection.disconnect()

                    var ip = ""
                    var loc = ""
                    responseText.lines().forEach { line ->
                        if (line.startsWith("ip=")) ip = line.substring(3).trim()
                        if (line.startsWith("loc=")) loc = line.substring(4).trim()
                    }

                    if (ip.isNotEmpty()) {
                        mapOf(
                            "ip" to ip,
                            "country" to loc,
                            "countryCode" to loc,
                            "pingMs" to elapsed
                        )
                    } else null
                } else {
                    connection.disconnect()
                    null
                }
            } catch (_: Exception) {
                null
            }
        }
    }

    override fun onDestroy() {
        appendNativeLog("Lifecycle", "پنجره برنامه بسته شد؛ هسته‌های ارتباطی در پس‌زمینه برای حفظ اینترنت زنده می‌مانند.")
        super.onDestroy()
    }
}