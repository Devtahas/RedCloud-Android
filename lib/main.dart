// ignore_for_file: deprecated_member_use, avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:url_launcher/url_launcher.dart';

// ۱. آدرس ورکر مرکزی مدیریت اکانت‌های شما روی کلاودفلر (بدون اسلش انتهایی)
const String workerApiUrl = "https://round-sea-8418.redcloudir.workers.dev";

// ۲. آدرس خام فایل کانفیگ گیت‌هاب شما
const String githubRawUrl = "https://raw.githubusercontent.com/Devtahas/Devtahas-redcloud-config/main/accounts.json";

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isDarkMode = true;
  String _currentLang = "fa";

  void _toggleTheme() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
  }

  void _changeLang(String lang) {
    setState(() {
      _currentLang = lang;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RedCloud VPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: _isDarkMode ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: _isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: _isDarkMode ? Brightness.dark : Brightness.light,
        ),
      ),
      home: HomePage(
        isDarkMode: _isDarkMode,
        currentLang: _currentLang,
        toggleTheme: _toggleTheme,
        changeLang: _changeLang,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final bool isDarkMode;
  final String currentLang;
  final VoidCallback toggleTheme;
  final Function(String) changeLang;

  const HomePage({
    super.key,
    required this.isDarkMode,
    required this.currentLang,
    required this.toggleTheme,
    required this.changeLang,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  var v2rayStatus = ValueNotifier<V2RayStatus>(V2RayStatus());
  Timer? _logTimer;
  Timer? _reportTimer; 
  int _currentTabIndex = 0;
  
  // شیء flutterV2ray را به این صورت ویرایش کنید:
late final V2ray flutterV2ray = V2ray(
  onStatusChanged: (status) {
    v2rayStatus.value = status;
    
    // چک کردن کاملاً آنی و ثانیه‌ای سقف ۵ گیگابایت به محض دریافت دیتای جدید از هسته
    if (status.state == "CONNECTED" && _selectedAccountIndex >= 0) {
      _checkAndAutoSwitchLimit(
        _fetchedAccounts[_selectedAccountIndex], 
        status.download + status.upload
      );
    }
  },
);

  final TextEditingController _configController = TextEditingController();
  
  List<Map<String, String>> _fetchedAccounts = [];
  int _selectedAccountIndex = -1;
  bool _isLoadingAccounts = false;
  bool _isScanningIPs = false;
  bool _serversUpdatingMode = false;
  
  String _fastestIP = "104.18.0.14";
  int _bestPing = 0;

  String _serverName = "هیچ سروری انتخاب نشده است";
  String _protocolType = "نامشخص";
  String _fullConfigJson = "";
  String _remark = "RedCloud Server";

  // متغیرهای تله‌متری و حذف محلی برای غلبه بر تاخیر زمان‌بندی گیت‌هاب
  int _lastSentDownload = 0;
  int _lastSentUpload = 0;
  final int _maxDailyBytes = 5 * 1024 * 1024 * 1024; // سقف ۵ گیگابایت برای هر ورکر
  
  // لیست سیاه محلی جهت ثبت سرورهایی که در این پارت اتمام ترافیک شده‌اند تا گیت‌هاب همگام‌سازی شود
  final Set<String> _locallyExhaustedWorkers = {};

  final List<String> _cloudflareIPs = [
    "104.16.1.1", "104.17.2.2", "104.18.3.3", "104.19.4.4", "104.20.5.5",
    "104.21.6.6", "104.22.7.7", "104.24.8.8", "104.25.9.9", "104.26.10.10",
    "104.27.11.11", "172.67.1.1", "162.159.1.1", "104.28.1.1", "104.31.1.1",
    "188.114.96.1", "188.114.97.2"
  ];

  final Map<String, Map<String, String>> _localizedValues = {
    "fa": {
      "app_title": "RedCloud VPN",
      "tab_dashboard": "داشبورد",
      "tab_settings": "تنظیمات",
      "tab_privacy": "حریم خصوصی",
      "tab_contact": "ارتباط با ما",
      "connected": "متصل",
      "connecting": "در حال اتصال",
      "disconnected": "قطع اتصال",
      "scan_ip": "اسکن آی‌پی",
      "shared_acc": "اکانت‌های اشتراکی هوشمند",
      "acc_fetch_err": "خطا در دریافت اکانت‌ها؛ لطفاً همگام‌سازی را بزنید.",
      "ping_info": "آی‌پی زنده کلودفلر: ",
      "ms": "میلی‌ثانیه",
      "down_speed": "سرعت دانلود",
      "up_speed": "سرعت آپلود",
      "total_down": "کل دانلود",
      "total_up": "کل آپلود",
      "conn_time": "زمان اتصال: ",
      "no_config_err": "لطفاً ابتدا یک کانفیگ معتبر وارد کنید",
      "connecting_msg": "در حال برقراری اتصال...",
      "os_perm_err": "لطفاً تاییدیه کادر سیستم‌عامل را بدهید و مجدداً دکمه اتصال را بزنید.",
      "acc_sync_ok": "لیست اکانت‌های فعال با موفقیت دریافت و فیلتر شدند.",
      "acc_sync_err": "خطا در ارتباط با گیت‌هاب؛ لطفاً اینترنت خود را چک کنید.",
      "clipboard_empty": "حافظه موقت سیستم شما خالی است",
      "config_saved": "کانفیگ با موفقیت ثبت شد",
      "config_err": "کانفیگ نامعتبر است یا امکان تبدیل خودکار آن وجود ندارد.",
      "manual_input_title": "ورود دستی کانفیگ تکی",
      "paste_btn": "کپی خودکار از کلیپ‌بورد",
      "save_btn": "تایید و ذخیره",
      "theme_setting": "تم برنامه",
      "theme_dark": "حالت تاریک (Dark Mode)",
      "theme_light": "حالت روشن (Light Mode)",
      "lang_setting": "زبان برنامه (Language)",
      "privacy_title": "بیانیه حریم خصوصی",
      "privacy_text": "ما به حریم خصوصی شما احترام می‌گذاریم. اپلیکیشن RedCloud VPN هیچ‌گونه اطلاعات، لاگ یا تاریخچه ترافیکی از فعالیت‌های اینترنتی کاربران خود ذخیره یا رصد نمی‌کند. تمامی ارتباطات شما از طریق پروتکل‌های امن و کلیدهای رمزنگاری پیشرفته به صورت کاملاً کدگذاری‌شده عبور داده می‌شود.",
      "contact_title": "ارتباط با تیم پشتیبانی RedCloud",
      "contact_email": "پشتیبانی ایمیل",
      "contact_telegram": "کانال تلگرام",
      "contact_web": "وب‌سایت ما",
      "copied_msg": "در حافظه موقت کپی شد!",
      "server_updating_banner": "سرورها در حال آپدیت هستند. از شکیبایی شما متشکریم.",
      "limit_exhausted_banner": "مصرف روزانه اکانت به پایان رسید! در حال تعویض خودکار به اکانت جدید...",
    },
    "en": {
      "app_title": "RedCloud VPN",
      "tab_dashboard": "Dashboard",
      "tab_settings": "Settings",
      "tab_privacy": "Privacy",
      "tab_contact": "Contact",
      "connected": "Connected",
      "connecting": "Connecting",
      "disconnected": "Disconnected",
      "scan_ip": "Scanning IP",
      "shared_acc": "Smart Shared Accounts",
      "acc_fetch_err": "Error fetching accounts; please sync.",
      "ping_info": "Live Cloudflare IP: ",
      "ms": "ms",
      "down_speed": "Download Speed",
      "up_speed": "Upload Speed",
      "total_down": "Total Download",
      "total_up": "Total Upload",
      "conn_time": "Connection Time: ",
      "no_config_err": "Please enter a valid config first",
      "connecting_msg": "Establishing connection...",
      "os_perm_err": "Please approve the system VPN dialog and press connect again.",
      "acc_sync_ok": "Active accounts fetched and filtered successfully.",
      "acc_sync_err": "Failed to connect to GitHub. Please check your internet.",
      "clipboard_empty": "Your clipboard is empty",
      "config_saved": "Config registered successfully",
      "config_err": "Invalid config or parsing failed.",
      "manual_input_title": "Manual Config Entry",
      "paste_btn": "Auto Paste from Clipboard",
      "save_btn": "Confirm & Save",
      "theme_setting": "App Theme",
      "theme_dark": "Dark Mode",
      "theme_light": "Light Mode",
      "lang_setting": "App Language",
      "privacy_title": "Privacy Policy",
      "privacy_text": "We respect your privacy. RedCloud VPN does not store, log, or monitor any traffic history of its users' online activities. All of your connections are securely encrypted using advanced cryptographic protocols.",
      "contact_title": "Connect with RedCloud Team",
      "contact_email": "Support Email",
      "contact_telegram": "Telegram",
      "contact_web": "Our Website",
      "copied_msg": "Copied to clipboard!",
      "server_updating_banner": "Servers are currently updating. Thank you for your patience.",
      "limit_exhausted_banner": "Daily usage limit reached! Auto-switching to a new fresh account...",
    }
  };

  String _t(String key) {
    return _localizedValues[widget.currentLang]?[key] ?? key;
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    flutterV2ray.initialize(
      notificationIconResourceType: "mipmap",
      notificationIconResourceName: "ic_launcher",
    );

    _fetchAndLoadAccounts();

    _logTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final List<String> logs = await flutterV2ray.getLogs();
        if (logs.isNotEmpty) {
          for (var log in logs) {
            print("[Xray Core Log]: $log");
          }
          await flutterV2ray.clearLogs();
        }
      } catch (e) {
        // نادیده گرفتن خطاها
      }
    });

    // گزارش تله‌متری افزایشی برای ورکر کلاودفلر (بدون تغییر کدهای ویندوز و بک‌اند)
    _reportTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      _reportDeltaUsage();
    });
  }

  @override
  void dispose() {
    _logTimer?.cancel();
    _reportTimer?.cancel();
    _configController.dispose();
    super.dispose();
  }

  void _reportDeltaUsage() async {
    if (v2rayStatus.value.state != "CONNECTED" || _selectedAccountIndex < 0) return;

    final currentDownload = v2rayStatus.value.download;
    final currentUpload = v2rayStatus.value.upload;

    final int deltaDownload = currentDownload - _lastSentDownload;
    final int deltaUpload = currentUpload - _lastSentUpload;
    final int totalDeltaBytes = deltaDownload + deltaUpload;

    if (totalDeltaBytes <= 0) return;

    if (deltaDownload < 0 || deltaUpload < 0) {
      _lastSentDownload = currentDownload;
      _lastSentUpload = currentUpload;
      return;
    }

    final activeAccount = _fetchedAccounts[_selectedAccountIndex];
    final String activeWorker = activeAccount['worker'] ?? '';

    // پکت گزارش مصرف تله‌متری که عینا ورکر شما انتظار دارد
    final Map<String, dynamic> reportPayload = {
      "worker": activeWorker,
      "bytes_used": totalDeltaBytes
    };

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(Uri.parse('$workerApiUrl/api/report'));
      request.headers.set('content-type', 'application/json');
      request.add(utf8.encode(jsonEncode(reportPayload)));
      
      final response = await request.close();
      if (response.statusCode == 200) {
        _lastSentDownload = currentDownload;
        _lastSentUpload = currentUpload;
        print("Delta Telemetry reported: $totalDeltaBytes bytes to $activeWorker");

        // بررسی به پایان رسیدن سهمیه سرور متصل شده در همان لحظه
        
      }
    } catch (e) {
      print("Telemetry network failure: $e");
    } finally {
      client.close();
    }
  }

  void _checkAndAutoSwitchLimit(Map<String, String> currentAccount, int totalBytesSession) async {
    final int previouslyUsedDatabase = int.tryParse(currentAccount['used_bytes'] ?? '0') ?? 0;
    final int currentRealtimeDailyUsage = previouslyUsedDatabase + totalBytesSession;
    final String activeWorker = currentAccount['worker'] ?? '';

    if (currentRealtimeDailyUsage >= _maxDailyBytes) {
      print("Worker daily quota exhausted. Initiating auto-rotation...");
      
      // ۱. افزودن فوری ورکر به لیست سیاه محلی تا همگام‌سازی گیت‌هاب تکمیل شود
      _locallyExhaustedWorkers.add(activeWorker);
      
      _showSnackBar(_t("limit_exhausted_banner"));
      _disconnect();
      
      // ۲. دریافت مجدد لیست و انتخاب سرور فول شارژ جدید
      await _fetchAndLoadAccounts();

      if (_fetchedAccounts.isNotEmpty && !_serversUpdatingMode) {
        setState(() {
          _selectedAccountIndex = 0;
          _updateSelectedConfig();
        });
        _connect();
      }
    }
  }

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        _showSnackBar("امکان باز کردن آدرس وجود ندارد؛ لطفاً بعداً تلاش کنید.");
      }
    } catch (e) {
      _showSnackBar("خطا در برقراری ارتباط: $e");
    }
  }

  // دریافت اطلاعات فایل JSON مستقیم و خام از گیت‌هاب بدون کش شدن
  Future<void> _fetchAndLoadAccounts({bool showMessage = false}) async {
    setState(() {
      _isLoadingAccounts = true;
      _serversUpdatingMode = false;
    });
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      // استفاده از آدرس خام گیت‌هاب به همراه پارامتر زمان تصادفی جهت بایپس کامل کش CDN گیت‌هاب
      final cacheBuster = DateTime.now().millisecondsSinceEpoch;
      final request = await client.getUrl(Uri.parse('$githubRawUrl?cb=$cacheBuster'));
      final response = await request.close();
      
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final List<dynamic> jsonList = jsonDecode(body);
        
        final List<Map<String, String>> parsed = [];
        for (var item in jsonList) {
          if (item is Map<String, dynamic>) {
            final String workerName = item['worker']?.toString() ?? '';
            final String status = item['status']?.toString() ?? 'full';

            // فیلتر کردن اکانت‌های خسته از دیتابیس یا لیست سیاه موقت کلاینت
            if (status != 'exhausted' && !_locallyExhaustedWorkers.contains(workerName)) {
              parsed.add({
                'worker': workerName,
                'uuid': item['uuid']?.toString() ?? '',
                'path': item['path']?.toString() ?? '',
                'status': status,
                'used_bytes': item['used_bytes']?.toString() ?? '0',
                'priority': item['priority']?.toString() ?? '1',
              });
            }
          }
        }

        // مرتب‌سازی بر اساس فیلد اولویت (Priority) صعودی عینا مطابق ساختار دیتابیس ورکر شما
        parsed.sort((a, b) {
          final int pA = int.tryParse(a['priority'] ?? '1') ?? 1;
          final int pB = int.tryParse(b['priority'] ?? '1') ?? 1;
          return pA.compareTo(pB);
        });

        setState(() {
          _fetchedAccounts = parsed;
          if (_fetchedAccounts.isNotEmpty) {
            _selectedAccountIndex = 0;
            _updateSelectedConfig();
          } else {
            _serversUpdatingMode = true;
            _selectedAccountIndex = -1;
          }
        });
        if (showMessage) _showSnackBar(_t("acc_sync_ok"));
      } else {
        if (showMessage) _showSnackBar(_t("acc_sync_err"));
      }
    } catch (e) {
      if (showMessage) _showSnackBar(_t("acc_sync_err"));
    } finally {
      client.close();
      setState(() {
        _isLoadingAccounts = false;
      });
    }
  }

  void _updateSelectedConfig() {
    if (_selectedAccountIndex < 0 || _selectedAccountIndex >= _fetchedAccounts.length) return;
    final account = _fetchedAccounts[_selectedAccountIndex];
    final String worker = account['worker'] ?? '';
    final String uuid = account['uuid'] ?? '';
    final String path = account['path'] ?? '';
    
    final String vlessLink = "vless://$uuid@$_fastestIP:443?encryption=none&security=tls&sni=$worker&fp=chrome&alpn=http%2F1.1&type=ws&host=$worker&path=${Uri.encodeComponent(path)}#$_serverName";
    _parseAndSaveConfig(vlessLink, updateUI: false);
    
    setState(() {
      _serverName = "${_t("tab_dashboard")} ${_selectedAccountIndex + 1}";
      _protocolType = "VLESS";
    });
  }

  Future<int?> _testIP(String ip) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(ip, 443, timeout: const Duration(milliseconds: 600));
      stopwatch.stop();
      socket.destroy();
      return stopwatch.elapsedMilliseconds;
    } catch (e) {
      return null;
    }
  }

  Future<String> _findFastestIP() async {
    String bestIP = "104.18.0.14";
    int bestLatency = 9999;
    
    final List<Future<void>> tasks = [];
    for (var ip in _cloudflareIPs) {
      tasks.add(_testIP(ip).then((latency) {
        if (latency != null && latency < bestLatency) {
          bestLatency = latency;
          bestIP = ip;
        }
      }));
    }
    await Future.wait(tasks);
    setState(() {
      _bestPing = bestLatency == 9999 ? 0 : bestLatency;
    });
    return bestIP;
  }

  void _connect() async {
    if (_fetchedAccounts.isEmpty && !_serversUpdatingMode) {
      await _fetchAndLoadAccounts();
    }
    
    if (_serversUpdatingMode) {
      _showSnackBar(_t("server_updating_banner"));
      return;
    }

    if (_fetchedAccounts.isEmpty && _fullConfigJson.isEmpty) {
      _showSnackBar(_t("acc_sync_err"));
      return;
    }

    setState(() {
      _isScanningIPs = true;
    });
    
    _showSnackBar(_t("connecting_msg"));
    final String fastest = await _findFastestIP();
    
    setState(() {
      _fastestIP = fastest;
      _isScanningIPs = false;
    });

    if (_selectedAccountIndex >= 0 && _selectedAccountIndex < _fetchedAccounts.length) {
      final account = _fetchedAccounts[_selectedAccountIndex];
      final String worker = account['worker'] ?? '';
      final String uuid = account['uuid'] ?? '';
      final String path = account['path'] ?? '';
      
      final String finalLink = "vless://$uuid@$fastest:443?encryption=none&security=tls&sni=$worker&fp=chrome&alpn=http%2F1.1&type=ws&host=$worker&path=${Uri.encodeComponent(path)}#RedCloud_Fastest";
      _parseAndSaveConfig(finalLink, updateUI: false);
    }

    if (await flutterV2ray.requestPermission()) {
      _showSnackBar("Connecting to: $fastest");

      _lastSentDownload = 0;
      _lastSentUpload = 0;

      flutterV2ray.startV2Ray(
        remark: _remark,
        config: _fullConfigJson,
        proxyOnly: false,
        notificationDisconnectButtonName: "DISCONNECT",
      );
    } else {
      _showSnackBar(_t("os_perm_err"));
    }
  }

  void _disconnect() async {
    _reportDeltaUsage();
    await flutterV2ray.stopV2Ray();
  }

  String _formatBytes(int bytes, {bool isSpeed = false}) {
    if (bytes <= 0) return isSpeed ? "0 B/s" : "0 B";
    const List<String> suffixes = ["B", "KB", "MB", "GB", "TB"];
    int i = 0;
    double num = bytes.toDouble();
    while (num >= 1024 && i < suffixes.length - 1) {
      num /= 1024;
      i++;
    }
    return "${num.toStringAsFixed(1)} ${suffixes[i]}${isSpeed ? '/s' : ''}";
  }

  void _parseAndSaveConfig(String link, {bool updateUI = true}) {
    if (link.isEmpty) return;
    
    String configText = link;
    if (!configText.startsWith("{")) {
      try {
        final V2RayURL v2rayURL = V2ray.parseFromURL(configText);
        
        v2rayURL.inbound['port'] = 10808;
        v2rayURL.dns = {
          "servers": ["1.1.1.1", "1.0.0.1"]
        };
        
        configText = v2rayURL.getFullConfiguration();
        _remark = v2rayURL.remark;
        
        if (updateUI) {
          String protocol = "نامشخص";
          final String typeStr = v2rayURL.runtimeType.toString().toLowerCase();
          if (typeStr.contains("vless")) {
            protocol = "VLESS";
          } else if (typeStr.contains("vmess")) {
            protocol = "VMESS";
          } else if (typeStr.contains("trojan")) {
            protocol = "TROJAN";
          } else if (typeStr.contains("shadowsocks") || typeStr.contains("ss")) {
            protocol = "SHADOWSOCKS";
          } else if (typeStr.contains("socks")) {
            protocol = "SOCKS";
          }

          setState(() {
            _serverName = v2rayURL.remark;
            _protocolType = protocol;
          });
        }
      } catch (e) {
        _showSnackBar(_t("config_err"));
        return;
      }
    }

    try {
      final Map<String, dynamic> configMap = jsonDecode(configText);
      
      if (configMap.containsKey('inbounds')) {
        final List<dynamic> inbounds = configMap['inbounds'];
        for (var inbound in inbounds) {
          if (inbound is Map<String, dynamic>) {
            inbound['sniffing'] = {
              "enabled": true,
              "destOverride": ["http", "tls", "quic"]
            };
          }
        }
      }

      configMap['dns'] = {
        "servers": [
          "1.1.1.1",
          "1.0.0.1",
          "8.8.8.8",
          "localhost"
        ],
        "queryStrategy": "UseIP"
      };

      configMap['routing'] = {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
          {
            "type": "field",
            "port": 53,
            "outboundTag": "dns"
          }
        ]
      };

      if (configMap.containsKey('outbounds')) {
        final List<dynamic> outbounds = configMap['outbounds'];
        for (var outbound in outbounds) {
          if (outbound is Map<String, dynamic> && outbound.containsKey('streamSettings')) {
            final Map<String, dynamic> streamSettings = outbound['streamSettings'];
            if (streamSettings.containsKey('tlsSettings')) {
              final Map<String, dynamic> tlsSettings = streamSettings['tlsSettings'];
              tlsSettings.remove('allowInsecure');
            }
          }
        }
      }
      configText = jsonEncode(configMap);
      _fullConfigJson = configText;
    } catch (e) {
      _showSnackBar("Error processing configuration");
    }
  }

  void _pasteFromClipboard() async {
    final ClipboardData? clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData != null && clipboardData.text != null) {
      _parseAndSaveConfig(clipboardData.text!.trim());
    } else {
      _showSnackBar(_t("clipboard_empty"));
    }
  }

  void _openConfigBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _t("manual_input_title"),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _configController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Vless, Vmess, Trojan Link',
                  hintText: 'Paste connection link here',
                ),
              ),
              const SizedBox(height: 15),
              ElevatedButton.icon(
                onPressed: () {
                  _pasteFromClipboard();
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.paste),
                label: Text(_t("paste_btn")),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () {
                  _parseAndSaveConfig(_configController.text.trim());
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(_t("save_btn")),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: widget.currentLang == "fa" ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _t("app_title"),
            style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: _buildCurrentTabContent(),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentTabIndex,
          onTap: (index) {
            setState(() {
              _currentTabIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: widget.isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF),
          selectedItemColor: Theme.of(context).colorScheme.primary,
          unselectedItemColor: Colors.grey,
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.dashboard),
              label: _t("tab_dashboard"),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.settings),
              label: _t("tab_settings"),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.verified_user),
              label: _t("tab_privacy"),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.contact_support),
              label: _t("tab_contact"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTabContent() {
    switch (_currentTabIndex) {
      case 0:
        return _buildDashboardTab();
      case 1:
        return _buildSettingsTab();
      case 2:
        return _buildPrivacyTab();
      case 3:
        return _buildContactTab();
      default:
        return _buildDashboardTab();
    }
  }

  Widget _buildDashboardTab() {
    return ValueListenableBuilder<V2RayStatus>(
      valueListenable: v2rayStatus,
      builder: (context, value, child) {
        final isConnected = value.state == "CONNECTED";
        final isConnecting = value.state == "CONNECTING" || _isScanningIPs;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_serversUpdatingMode)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 15),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _t("server_updating_banner"),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber),
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                _t("shared_acc"),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _isLoadingAccounts
                        ? const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                          )
                        : _fetchedAccounts.isEmpty
                            ? Text(
                                _t("acc_fetch_err"),
                                style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                              )
                            : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: List.generate(_fetchedAccounts.length, (index) {
                                    final isSelected = _selectedAccountIndex == index;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 6.0),
                                      child: ChoiceChip(
                                        label: Text("${_t("tab_dashboard")} ${index + 1}"),
                                        selected: isSelected,
                                        selectedColor: Theme.of(context).colorScheme.primary,
                                        onSelected: (selected) {
                                          if (selected) {
                                            setState(() {
                                              _selectedAccountIndex = index;
                                              _updateSelectedConfig();
                                            });
                                          }
                                        },
                                      ),
                                    );
                                  }),
                                ),
                              ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cached, color: Colors.blueAccent),
                    tooltip: "Sync Accounts",
                    onPressed: () => _fetchAndLoadAccounts(showMessage: true),
                  )
                ],
              ),
              const SizedBox(height: 25),
              
              Center(
                child: GestureDetector(
                  onTap: isConnected ? _disconnect : _connect,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isConnected
                          ? const Color(0xFF10B981).withOpacity(0.15)
                          : isConnecting
                              ? const Color(0xFFF59E0B).withOpacity(0.15)
                              : const Color(0xFFEF4444).withOpacity(0.1),
                      border: Border.all(
                        color: isConnected
                            ? const Color(0xFF10B981)
                            : isConnecting
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFFEF4444).withOpacity(0.5),
                        width: 4,
                      ),
                      boxShadow: [
                        if (isConnected)
                          BoxShadow(
                            color: const Color(0xFF10B981).withOpacity(0.4),
                            blurRadius: 25,
                            spreadRadius: 5,
                          ),
                        if (isConnecting)
                          BoxShadow(
                            color: const Color(0xFFF59E0B).withOpacity(0.4),
                            blurRadius: 25,
                            spreadRadius: 5,
                          ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isConnecting)
                          const SizedBox(
                            width: 45,
                            height: 45,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                              strokeWidth: 4,
                            ),
                          )
                        else
                          Icon(
                            Icons.power_settings_new,
                            size: 60,
                            color: isConnected
                                ? const Color(0xFF10B981)
                                : const Color(0xFF94A3B8),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          isConnected
                              ? _t("connected")
                              : _isScanningIPs
                                  ? _t("scan_ip")
                                  : isConnecting
                                      ? _t("connecting")
                                      : _t("disconnected"),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isConnected
                              ? const Color(0xFF10B981)
                              : isConnecting
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 25),

              GestureDetector(
                onTap: _openConfigBottomSheet,
                child: Card(
                  color: Theme.of(context).colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(color: Colors.grey.withOpacity(0.1)),
                  ),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: Color(0xFF3B82F6),
                          child: Icon(Icons.public, color: Colors.white),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _serverName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Protocol: $_protocolType",
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ),

              if (_fastestIP != "104.18.0.14" && _bestPing > 0)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      "${_t("ping_info")}$_fastestIP ($_bestPing ${_t("ms")})",
                      style: const TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

              const SizedBox(height: 15),

              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 1.6,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  _buildStatCard(
                    _t("down_speed"),
                    _formatBytes(value.downloadSpeed, isSpeed: true),
                    Icons.arrow_downward,
                    const Color(0xFF10B981),
                  ),
                  _buildStatCard(
                    _t("up_speed"),
                    _formatBytes(value.uploadSpeed, isSpeed: true),
                    Icons.arrow_upward,
                    const Color(0xFF3B82F6),
                  ),
                  _buildStatCard(
                    _t("total_down"),
                    _formatBytes(value.download),
                    Icons.cloud_download,
                    Colors.blueGrey,
                  ),
                  _buildStatCard(
                    _t("total_up"),
                    _formatBytes(value.upload),
                    Icons.cloud_upload,
                    Colors.blueGrey,
                  ),
                ],
              ),
              
              const SizedBox(height: 15),

              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "${_t("conn_time")}${value.duration}",
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(height: 15),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _t("lang_setting"),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      DropdownButton<String>(
                        value: widget.currentLang,
                        dropdownColor: const Color(0xFF1E293B),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            widget.changeLang(newValue);
                          }
                        },
                        items: const [
                          DropdownMenuItem(value: "fa", child: Text("فارسی")),
                          DropdownMenuItem(value: "en", child: Text("English")),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _t("theme_setting"),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      Switch(
                        value: widget.isDarkMode,
                        onChanged: (value) {
                          widget.toggleTheme();
                        },
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Align(
                      alignment: widget.currentLang == "fa" ? Alignment.centerRight : Alignment.centerLeft,
                      child: Text(
                        widget.isDarkMode ? _t("theme_dark") : _t("theme_light"),
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Card(
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shield_outlined, color: Theme.of(context).colorScheme.secondary, size: 28),
                  const SizedBox(width: 10),
                  Text(
                    _t("privacy_title"),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Text(
                _t("privacy_text"),
                style: const TextStyle(fontSize: 14, height: 1.6, color: Colors.white70),
                textAlign: TextAlign.justify,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactTab() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _t("contact_title"),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 25),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.1,
              children: [
                _buildContactGridCard(
                  _t("contact_telegram"),
                  "https://t.me/RedCloudChannel",
                  Icons.telegram,
                  const Color(0xFF229ED9),
                ),
                _buildContactGridCard(
                  _t("contact_web"),
                  "https://www.redcloudvpn.com",
                  Icons.language,
                  const Color(0xFF10B981),
                ),
                _buildContactGridCard(
                  _t("contact_email"),
                  "mailto:support@redcloudvpn.com",
                  Icons.alternate_email,
                  const Color(0xFFEF4444),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactGridCard(String title, String url, IconData icon, Color color) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _launchURL(url),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: color.withOpacity(0.12),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                Icon(icon, size: 16, color: color),
              ],
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}