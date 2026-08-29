// ignore_for_file: deprecated_member_use, avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// ۱. آدرس ورکر مرکزی مدیریت اکانت‌های کلاودفلر
const String workerApiUrl = "https://round-sea-8418.redcloudir.workers.dev";

// ۲. آدرس خام فایل کانفیگ گیت‌هاب
const String githubRawUrl = "https://raw.githubusercontent.com/Devtahas/Devtahas-redcloud-config/main/accounts.json";

// ۳. اطلاعات تلگرام و کیف پول حمایت مالی
const String telegramChannelUrl = "https://t.me/DevTaha_project";
const String usdtBnbAddress = "0xDeda28Aa73Ec089A77B3fC616E0011a8fce12900";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  static const MethodChannel _aetherChannel = MethodChannel('com.redcloud.vpn/aether_channel');
  static const MethodChannel _torChannel = MethodChannel('com.redcloud.vpn/tor_channel');

  final ValueNotifier<V2RayStatus> v2rayStatus = ValueNotifier<V2RayStatus>(V2RayStatus());
  Timer? _logTimer;
  Timer? _reportTimer;
  Timer? _torProgressTimer;
  Timer? _bannerTimer;
  int _currentTabIndex = 0;
  
  late final V2ray flutterV2ray = V2ray(
    onStatusChanged: (status) {
      v2rayStatus.value = status;
      
      if (!_isAetherActive && !_isTorActive && status.state == "CONNECTED" && _selectedAccountIndex >= 0) {
        _checkAndAutoSwitchLimit(
          _fetchedAccounts[_selectedAccountIndex], 
          status.download + status.upload,
        );
      }
    },
  );

  final TextEditingController _configController = TextEditingController();
  final TextEditingController _customBridgeController = TextEditingController();
  
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

  // اعلان بنر هوشمند بالای صفحه با زمان‌بندی ۵ ثانیه‌ای
  String? _bannerMessage;
  Color _bannerColor = const Color(0xFF3B82F6);
  IconData _bannerIcon = Icons.info_outline_rounded;

  // متغیرهای اختصاصی هسته اَتر (Aether Engine)
  String _selectedAetherMode = "auto";
  bool _isAetherConnecting = false;
  bool _isAetherActive = false;

  // متغیرهای اختصاصی هسته تور (Tor Engine)
  String _selectedTorMode = "aether_masque";
  bool _isTorConnecting = false;
  bool _isTorActive = false;
  int _torBootstrapProgress = 0;
  String _torStepStatus = "آماده اتصال";
  int _torCurrentStep = 0;

  int _lastSentDownload = 0;
  int _lastSentUpload = 0;
  final int _maxDailyBytes = 5 * 1024 * 1024 * 1024;
  
  final Set<String> _locallyExhaustedWorkers = {};

  final List<String> _defaultCloudflareIPs = [
    "104.16.1.1", "104.17.2.2", "104.18.3.3", "104.19.4.4", "104.20.5.5",
    "104.21.6.6", "104.22.7.7", "104.24.8.8", "104.25.9.9", "104.26.10.10",
    "104.27.11.11", "172.67.1.1", "162.159.1.1", "104.28.1.1", "104.31.1.1",
    "188.114.96.1", "188.114.97.2"
  ];

  List<String> _activeVerifiedDnsList = ["1.1.1.1", "1.0.0.1", "8.8.8.8"];

  final Map<String, Map<String, String>> _localizedValues = {
    "fa": {
      "app_title": "RedCloud VPN",
      "tab_dashboard": "داشبورد",
      "tab_aether": "اَتر (Aether)",
      "tab_tor": "تور (Tor)",
      "tab_settings": "تنظیمات",
      "tab_privacy": "حریم خصوصی",
      "tab_contact": "ارتباط و حمایت",
      "connected": "متصل",
      "connecting": "در حال اتصال",
      "disconnected": "قطع اتصال",
      "scan_ip": "اسکن لایه ۷ کلودفلر",
      "shared_acc": "اکانت‌های اشتراکی هوشمند",
      "acc_fetch_err": "خطا در دریافت اکانت‌ها؛ لطفاً همگام‌سازی را بزنید.",
      "ping_info": "آی‌پی سالم لایه ۷: ",
      "ms": "میلی‌ثانیه",
      "down_speed": "سرعت دانلود",
      "up_speed": "سرعت آپلود",
      "total_down": "کل دانلود",
      "total_up": "کل آپلود",
      "conn_time": "زمان اتصال: ",
      "no_config_err": "لطفاً ابتدا یک کانفیگ معتبر وارد کنید",
      "connecting_msg": "در حال بررسی و اتصال...",
      "os_perm_err": "لطفاً تاییدیه کادر سیستم‌عامل را بدهید و مجدداً دکمه اتصال را بزنید.",
      "acc_sync_ok": "لیست اکانت‌های فعال با موفقیت دریافت و فیلتر شدند.",
      "acc_sync_err": "خطا در ارتباط با سرور؛ اینترنت خود را چک کنید.",
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
      "contact_title": "ارتباط با ما و حمایت مالی",
      "contact_telegram": "کانال تلگرام ما",
      "contact_donate": "حمایت مالی (Donate)",
      "copied_msg": "در حافظه موقت کپی شد!",
      "server_updating_banner": "سرورها در حال آپدیت هستند. از شکیبایی شما متشکریم.",
      "limit_exhausted_banner": "مصرف روزانه اکانت به پایان رسید! در حال تعویض خودکار...",
      
      "banner_dns_rescue": "در حال رفع مسمومیت دی‌ان‌اس و گزینش امن‌ترین سرورها...",
      "banner_cf_fallback": "آی‌پی‌های پیش‌فرض پاسخگو نبودند؛ در حال استخراج و اسکن از دیتابیس بزرگ رنج‌های کلودفلر...",

      "aether_title": "هسته ضدسانسور اَتر (WARP Engine)",
      "aether_subtitle": "تونل کل دستگاه با پروتکل‌های پیشرفته کلودفلر",
      "aether_mode_select": "حالت پروتکل (Protocol Mode)",
      "mode_auto_title": "(پیشنهادی - Auto Failover) انتخاب خودکار هوشمند",
      "mode_auto_desc": "تست خودکار تمام مسیرها و نویزها و اتصال به پایدارترین حالت",
      "mode_masque_h2_title": "MASQUE (HTTP/2 - TCP)",
      "mode_masque_h2_desc": "دارای فرگمنت TLS جهت عبور تضمینی از فیلترینگ شدید",
      "mode_masque_title": "MASQUE (HTTP/3 - QUIC)",
      "mode_masque_desc": "پرسرعت‌ترین حالت مبتنی بر پروتکل وب QUIC و UDP",
      "mode_gool_title": "Gool (WARP in WARP)",
      "mode_gool_desc": "دو لایه وایرگارد تودرتو برای بالاترین ضریب عبور",
      "mode_wireguard_title": "WireGuard (WARP)",
      "mode_wireguard_desc": "پروتکل وایرگارد مستقیم کلودفلر با مصرف بهینه باتری",
      "aether_launching": "در حال اسکن و آزمایش خودکار پروتکل‌های ضدسانسور...",
      "aether_connected_banner": "تونل اَتر فعال است (کل گوشی تونل شد)",
      "aether_start_err": "خطا در راه‌اندازی هسته اَتر؛ لطفاً مجدداً تلاش کنید.",

      "tor_title": "شبکه پیازی تور (Tor Network)",
      "tor_subtitle": "ناشناسی کامل و تونل چندلایه‌ای (Tor over MASQUE)",
      "tor_mode_select": "نوع مسیر اتصال به تور",
      "tor_mode_aether_masque_title": "(پیشنهادی - ضد فیلتر قطعی) اَتر مسک + تور",
      "tor_mode_aether_masque_desc": "عبور هوشمند ترافیک تور از بستر TLS Fragment اَتر",
      "tor_mode_aether_quic_title": "اَتر کوئیک + تور (MASQUE QUIC)",
      "tor_mode_aether_quic_desc": "ترکیب سریع‌ترین لایه پروتکل QUIC کلودفلر با مدارهای پیازی تور",
      "tor_mode_direct_title": "اتصال مستقیم (Direct Tor Relay)",
      "tor_mode_direct_desc": "اتصال مستقیم به رله‌های تور بدون واسطه",
      "tor_mode_snowflake_title": "پل اسنوفلیک (Snowflake Bridge)",
      "tor_mode_snowflake_desc": "دور زدن فیلترینگ از طریق پروکسی‌های موقت WebRTC",
      "tor_mode_custom_title": "پل سفارشی (Custom Bridges)",
      "tor_mode_custom_desc": "ورود خطوط پل‌های اختصاصی شما",
      "tor_connected_banner": "شبکه تور فعال است (کل دستگاه ناشناس و تونل شد)",
      "tor_start_err": "خطا در برقراری ارتباط با شبکه تور؛ اتصال اینترنت را چک کنید.",
      "tor_custom_bridge_hint": "خطوط پل (Bridge lines) را اینجا وارد کنید...",
      "tor_building_circuits": "در حال ساخت مدارهای امن: ",

      "tor_step_cleanup": "آزادسازی پورت‌ها و ریست هسته‌ها...",
      "tor_step_aether_start": "راه‌اندازی پل اَتر مسک...",
      "tor_step_aether_test": "تست گذردهی واقعی اینترنت اَتر...",
      "tor_step_tor_start": "راه‌اندازی مدارهای پیازی تور...",
      "tor_step_vpn_start": "برقراری تونل امن کل گوشی...",
      "aether_egress_err": "خطا: پل اَتر متصل شد اما امکان رد کردن ترافیک را ندارد. اینترنت را بررسی کنید.",
      "aether_port_timeout": "تایم‌اوت پورت اَتر (۱۸۱۹)",
      "tor_socks_timeout": "تایم‌اوت شبکه تور (پورت ۹۰۵۰)",
      "tor_layer_aether": "پل اَتر مسک (MASQUE)",
      "tor_layer_tor": "مدارهای پیازی تور (Tor)",
      "tor_layer_vpn": "تونل کل دستگاه (V2Ray TUN)",
    },
    "en": {
      "app_title": "RedCloud VPN",
      "tab_dashboard": "Dashboard",
      "tab_aether": "Aether",
      "tab_tor": "Tor",
      "tab_settings": "Settings",
      "tab_privacy": "Privacy",
      "tab_contact": "Contact & Donate",
      "connected": "Connected",
      "connecting": "Connecting",
      "disconnected": "Disconnected",
      "scan_ip": "L7 Cloudflare Scan",
      "shared_acc": "Smart Shared Accounts",
      "acc_fetch_err": "Error fetching accounts; please sync.",
      "ping_info": "Live L7 Cloudflare IP: ",
      "ms": "ms",
      "down_speed": "Download Speed",
      "up_speed": "Upload Speed",
      "total_down": "Total Download",
      "total_up": "Total Upload",
      "conn_time": "Connection Time: ",
      "no_config_err": "Please enter a valid config first",
      "connecting_msg": "Probing & connecting...",
      "os_perm_err": "Please approve the system VPN dialog and press connect again.",
      "acc_sync_ok": "Active accounts fetched successfully.",
      "acc_sync_err": "Failed to connect to server. Check your internet.",
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
      "contact_title": "Connect & Support Us",
      "contact_telegram": "Telegram Channel",
      "contact_donate": "Donate (Crypto)",
      "copied_msg": "Copied to clipboard!",
      "server_updating_banner": "Servers are currently updating. Thank you for your patience.",
      "limit_exhausted_banner": "Daily usage limit reached! Auto-switching...",

      "banner_dns_rescue": "Resolving DNS poisoning & selecting cleanest resolvers...",
      "banner_cf_fallback": "Default IPs unviable; deep scanning large Cloudflare CIDR pools...",

      "aether_title": "Aether Anti-Censorship Engine",
      "aether_subtitle": "Full-Device Tunnel Powered by Cloudflare WARP",
      "aether_mode_select": "Protocol Mode",
      "mode_auto_title": "(Recommended - Auto Failover) Smart Auto-Select",
      "mode_auto_desc": "Auto probes all paths and noises to pick the most stable tunnel",
      "mode_masque_h2_title": "MASQUE (HTTP/2 - TCP)",
      "mode_masque_h2_desc": "TLS Fragmentation to bypass heavy censorship",
      "mode_masque_title": "MASQUE (HTTP/3 - QUIC)",
      "mode_masque_desc": "Ultra-fast mode over QUIC & UDP protocol",
      "mode_gool_title": "Gool (WARP in WARP)",
      "mode_gool_desc": "Nested dual WireGuard for deepest censorship bypass",
      "mode_wireguard_title": "WireGuard (WARP)",
      "mode_wireguard_desc": "Native Cloudflare WireGuard with low battery drain",
      "aether_launching": "Starting Aether core & scanning gateway...",
      "aether_connected_banner": "Aether Active (Full Device Tunneled)",
      "aether_start_err": "Failed to start Aether core. Please try again.",

      "tor_title": "Tor Onion Network",
      "tor_subtitle": "Full Anonymity & Multi-Layered Tunnel (Tor over MASQUE)",
      "tor_mode_select": "Tor Routing Mode",
      "tor_mode_aether_masque_title": "(Top Recommended) Aether MASQUE + Tor",
      "tor_mode_aether_masque_desc": "Tunnel Tor through Aether TLS Fragment to guarantee 100% censorship bypass",
      "tor_mode_aether_quic_title": "Aether QUIC + Tor (MASQUE H3)",
      "tor_mode_aether_quic_desc": "Ultra-fast Cloudflare QUIC layer paired with Onion routing",
      "tor_mode_direct_title": "Direct Connection (Standard Relays)",
      "tor_mode_direct_desc": "Direct connection to Tor relays without upstream bridge",
      "tor_mode_snowflake_title": "Snowflake Bridge",
      "tor_mode_snowflake_desc": "Bypass DPI using temporary WebRTC proxies",
      "tor_mode_custom_title": "Custom Bridges",
      "tor_mode_custom_desc": "Manually enter personal Tor bridge lines",
      "tor_connected_banner": "Tor Active (Full Device Tunneled)",
      "tor_start_err": "Failed to connect to Tor network. Check your internet.",
      "tor_custom_bridge_hint": "Enter bridge lines here...",
      "tor_building_circuits": "Building Secure Circuits: ",

      "tor_step_cleanup": "Cleaning ports & resetting cores...",
      "tor_step_aether_start": "Starting Aether MASQUE bridge...",
      "tor_step_aether_test": "Testing Aether real internet egress...",
      "tor_step_tor_start": "Starting Tor Onion circuits...",
      "tor_step_vpn_start": "Establishing full device VPN tunnel...",
      "aether_egress_err": "Error: Aether connected but failed to pass traffic. Check your connection.",
      "aether_port_timeout": "Aether port timeout (1819)",
      "tor_socks_timeout": "Tor SOCKS timeout (9050)",
      "tor_layer_aether": "Aether MASQUE Bridge",
      "tor_layer_tor": "Tor Onion Circuits",
      "tor_layer_vpn": "Full Device Tunnel",
    }
  };

  String _t(String key) {
    return _localizedValues[widget.currentLang]?[key] ?? _localizedValues["en"]?[key] ?? key;
  }

  void _showBannerNotification(String message, {Color color = const Color(0xFF3B82F6), IconData icon = Icons.info_outline_rounded}) {
    if (!mounted) return;
    _bannerTimer?.cancel();
    setState(() {
      _bannerMessage = message;
      _bannerColor = color;
      _bannerIcon = icon;
    });

    _bannerTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _bannerMessage = null;
        });
      }
    });
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    flutterV2ray.initialize(
      notificationIconResourceType: "mipmap",
      notificationIconResourceName: "ic_launcher",
    );

    _initApp();
  }

  Future<void> _initApp() async {
    await _loadExhaustedWorkers();
    await _fetchAndLoadAccounts();

    if (kDebugMode) {
      _logTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        try {
          final List<String> logs = await flutterV2ray.getLogs();
          if (logs.isNotEmpty) {
            for (var log in logs) {
              print("[Core Log]: $log");
            }
            await flutterV2ray.clearLogs();
          }
        } catch (_) {}
      });
    }

    _reportTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      if (!_isAetherActive && !_isTorActive) {
        _reportDeltaUsage();
      }
    });
  }

  @override
  void dispose() {
    _logTimer?.cancel();
    _reportTimer?.cancel();
    _torProgressTimer?.cancel();
    _bannerTimer?.cancel();
    _configController.dispose();
    _customBridgeController.dispose();
    v2rayStatus.dispose();
    super.dispose();
  }

  // =========================================================================
  // الگوریتم پکت خام UDP جهت تست و فیلتر کردن مسمومیت دی‌ان‌اس (DNS Anti-Poisoning)
  // =========================================================================
  Future<Map<String, dynamic>?> _verifyDnsIp(String ip, {int timeoutMs = 1500}) async {
    RawDatagramSocket? socket;
    try {
      final InternetAddress targetAddress = InternetAddress(ip.trim());
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      
      // پکت استاندارد پرس‌وجوی DNS برای google.com (A Record)
      final List<int> dnsQuery = [
        0x12, 0x34,
        0x01, 0x00,
        0x00, 0x01,
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x00,
        0x06, 0x67, 0x6f, 0x6f, 0x67, 0x6c, 0x65,
        0x03, 0x63, 0x6f, 0x6d,
        0x00,
        0x00, 0x01,
        0x00, 0x01
      ];

      final stopwatch = Stopwatch()..start();
      socket.send(dnsQuery, targetAddress, 53);

      final completer = Completer<Map<String, dynamic>?>();
      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket?.receive();
          if (datagram != null && datagram.data.length >= 32) {
            stopwatch.stop();
            final data = datagram.data;
            final int ancount = (data[6] << 8) | data[7];
            if (ancount > 0) {
              final int len = data.length;
              final int o1 = data[len - 4];
              final int o2 = data[len - 3];
              final int o3 = data[len - 2];
              final int o4 = data[len - 1];

              // فیلتر کردن مسمومیت DNS و صفحات فیلترینگ ایران (10.10.34.x و 10.x.x.x و رنج‌های لوکال)
              final bool isPoisoned = (o1 == 10) || 
                                     (o1 == 127) || 
                                     (o1 == 0) || 
                                     (o1 == 192 && o2 == 168) || 
                                     (o1 == 172 && o2 >= 16 && o2 <= 31);

              if (!isPoisoned && !completer.isCompleted) {
                completer.complete({
                  'ip': ip,
                  'latency': stopwatch.elapsedMilliseconds,
                });
                return;
              }
            }
          }
          if (!completer.isCompleted) completer.complete(null);
        }
      }, onError: (_) {
        if (!completer.isCompleted) completer.complete(null);
      });

      Timer(Duration(milliseconds: timeoutMs), () {
        if (!completer.isCompleted) completer.complete(null);
      });

      final result = await completer.future;
      return result;
    } catch (_) {
      return null;
    } finally {
      try { socket?.close(); } catch (_) {}
    }
  }

  Future<List<String>> _runDnsRescueScan() async {
    List<String> candidates = [];
    try {
      final String dnsContent = await rootBundle.loadString('assets/DNS.txt');
      for (var line in dnsContent.split('\n')) {
        final clean = line.trim();
        if (clean.isNotEmpty && !clean.startsWith('#')) {
          candidates.add(clean);
        }
      }
    } catch (_) {}

    if (candidates.isEmpty) {
      candidates = [
        "8.8.8.8", "8.8.4.4", "9.9.9.9", "149.112.112.112",
        "208.67.222.222", "208.67.220.220", "94.140.14.14", "94.140.15.15",
        "185.228.168.9", "185.228.169.9", "77.88.8.8", "77.88.8.1",
        "223.5.5.5", "223.6.6.6", "119.29.29.29", "1.1.1.1", "1.0.0.1"
      ];
    }

    final List<Map<String, dynamic>> verified = [];
    final chunkPool = candidates.take(60).toList();
    
    for (int i = 0; i < chunkPool.length; i += 15) {
      final chunk = chunkPool.sublist(i, (i + 15).clamp(0, chunkPool.length));
      final tasks = chunk.map((ip) => _verifyDnsIp(ip, timeoutMs: 1400));
      final results = await Future.wait(tasks);
      for (var res in results) {
        if (res != null) {
          verified.add(res);
        }
      }
      if (verified.length >= 4) break;
    }

    verified.sort((a, b) => (a['latency'] as int).compareTo(b['latency'] as int));
    if (verified.isNotEmpty) {
      return verified.map((e) => e['ip'] as String).toList();
    }
    return ["8.8.8.8", "9.9.9.9", "1.1.1.1"];
  }

  // =========================================================================
  // اسکنر واقعی لایه ۷ کلودفلر (Layer-7 WebSocket + TLS Handshake Probe)
  // =========================================================================
  Future<int?> _testIpLayer7(String ip, String host, String path, {int timeoutMs = 1800}) async {
    final stopwatch = Stopwatch()..start();
    Socket? rawSocket;
    SecureSocket? secureSocket;
    try {
      rawSocket = await Socket.connect(ip, 443, timeout: Duration(milliseconds: timeoutMs));
      
      secureSocket = await SecureSocket.secure(
        rawSocket,
        host: host,
        onBadCertificate: (cert) => true,
        supportedProtocols: ['http/1.1'],
      ).timeout(Duration(milliseconds: timeoutMs));

      final cleanPath = path.startsWith('/') ? path : '/$path';
      final request = "GET $cleanPath HTTP/1.1\r\n"
          "Host: $host\r\n"
          "User-Agent: Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36\r\n"
          "Upgrade: websocket\r\n"
          "Connection: Upgrade\r\n"
          "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
          "Sec-WebSocket-Version: 13\r\n\r\n";

      secureSocket.write(request);
      await secureSocket.flush();

      final completer = Completer<int?>();

      secureSocket.listen((data) {
        final response = String.fromCharCodes(data);
        if (response.startsWith("HTTP/1.1 101") || response.startsWith("HTTP/1.0 101")) {
          stopwatch.stop();
          if (!completer.isCompleted) completer.complete(stopwatch.elapsedMilliseconds);
        } else {
          if (!completer.isCompleted) completer.complete(null);
        }
      }, onError: (_) {
        if (!completer.isCompleted) completer.complete(null);
      }, onDone: () {
        if (!completer.isCompleted) completer.complete(null);
      });

      Timer(Duration(milliseconds: timeoutMs), () {
        if (!completer.isCompleted) completer.complete(null);
      });

      final result = await completer.future;
      return result;
    } catch (_) {
      return null;
    } finally {
      try { secureSocket?.destroy(); } catch (_) {}
      try { rawSocket?.destroy(); } catch (_) {}
    }
  }

  // =========================================================================
  // تولید ۵۰ آی‌پی منظم و پخش‌شده از هر رنج CIDR دیتابیس کلودفلر
  // =========================================================================
  Future<List<String>> _loadDeepScanIps() async {
    final List<String> candidateIps = [];
    try {
      final String cfContent = await rootBundle.loadString('assets/cloudflare_IPs.txt');
      for (var line in cfContent.split('\n')) {
        final clean = line.trim();
        if (clean.isEmpty || clean.startsWith('#')) continue;

        if (clean.contains('/')) {
          final parts = clean.split('/');
          final baseIp = parts[0];
          final octets = baseIp.split('.');
          if (octets.length == 4) {
            final prefix = "${octets[0]}.${octets[1]}.${octets[2]}";
            // استخراج ۵۰ هاست با فواصل منظم از هر ساب‌نت
            for (int host = 1; host <= 250; host += 5) {
              candidateIps.add("$prefix.$host");
            }
          }
        } else if (clean.contains('.')) {
          candidateIps.add(clean);
        }
      }
    } catch (_) {}

    if (candidateIps.isEmpty) {
      final fallbackCidrs = [
        "104.16.0.0", "104.18.0.0", "104.19.0.0", "104.20.0.0",
        "104.21.0.0", "104.22.0.0", "104.24.0.0", "104.25.0.0",
        "104.26.0.0", "104.27.0.0", "172.64.0.0", "172.67.0.0",
        "162.159.0.0", "188.114.96.0"
      ];
      for (var prefix in fallbackCidrs) {
        final octets = prefix.split('.');
        final p = "${octets[0]}.${octets[1]}.${octets[2]}";
        for (int host = 1; host <= 250; host += 5) {
          candidateIps.add("$p.$host");
        }
      }
    }
    return candidateIps;
  }

  // =========================================================================
  // موتور اسکن هوشمند با فال‌بک خودکار به دیتابیس بزرگ
  // =========================================================================
  Future<String> _findFastestIP(String host, String path) async {
    String bestIP = "";
    int bestLatency = 9999;
    
    // ۱. اسکن سریع اولیه روی لیست پیش‌فرض
    final fastPool = _defaultCloudflareIPs;
    final List<Future<MapEntry<String, int>>> fastTasks = fastPool.map((ip) {
      return _testIpLayer7(ip, host, path, timeoutMs: 1400).then((latency) => MapEntry(ip, latency ?? 9999));
    }).toList();

    final List<MapEntry<String, int>> fastResults = await Future.wait(fastTasks);
    for (var result in fastResults) {
      if (result.value < bestLatency && result.value < 1500) {
        bestLatency = result.value;
        bestIP = result.key;
      }
    }

    if (bestIP.isNotEmpty && bestLatency < 9999) {
      if (mounted) {
        setState(() {
          _bestPing = bestLatency;
        });
      }
      return bestIP;
    }

    // ۲. ورود به حالت فال‌بک بزرگ و نمایش بنر ۵ ثانیه‌ای
    _showBannerNotification(
      _t("banner_cf_fallback"),
      color: const Color(0xFFF59E0B),
      icon: Icons.travel_explore_rounded,
    );

    final List<String> deepPool = await _loadDeepScanIps();
    final candidatePool = deepPool.take(150).toList();

    for (int i = 0; i < candidatePool.length; i += 20) {
      final chunk = candidatePool.sublist(i, (i + 20).clamp(0, candidatePool.length));
      final List<Future<MapEntry<String, int>>> scanTasks = chunk.map((ip) {
        return _testIpLayer7(ip, host, path, timeoutMs: 1800).then((latency) => MapEntry(ip, latency ?? 9999));
      }).toList();

      final List<MapEntry<String, int>> results = await Future.wait(scanTasks);
      for (var result in results) {
        if (result.value < bestLatency && result.value < 1800) {
          bestLatency = result.value;
          bestIP = result.key;
          if (bestLatency < 200) break;
        }
      }
      if (bestLatency < 200) break;
    }

    if (mounted) {
      setState(() {
        _bestPing = bestLatency == 9999 ? 0 : bestLatency;
      });
    }
    return bestIP.isNotEmpty ? bestIP : "104.18.0.14";
  }

  // =========================================================================
  // روتینگ استاندارد و کاملاً پایدار Aether
  // =========================================================================
  String _generateAetherBridgeV2RayConfig() {
    final Map<String, dynamic> bridgeConfig = {
      "log": {
        "loglevel": "none"
      },
      "inbounds": [
        {
          "tag": "socks-in",
          "port": 10808,
          "listen": "127.0.0.1",
          "protocol": "socks",
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls"],
            "routeOnly": false
          },
          "settings": {
            "auth": "noauth",
            "udp": true
          }
        }
      ],
      "outbounds": [
        {
          "tag": "proxy",
          "protocol": "socks",
          "settings": {
            "servers": [
              {
                "address": "127.0.0.1",
                "port": 1819
              }
            ]
          }
        },
        {
          "tag": "direct",
          "protocol": "freedom",
          "settings": {
            "domainStrategy": "UseIP"
          }
        },
        {
          "tag": "block",
          "protocol": "blackhole"
        }
      ],
      "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
          {
            "type": "field",
            "network": "udp",
            "port": "443,853",
            "outboundTag": "block"
          },
          {
            "type": "field",
            "ip": [
              "127.0.0.1/32",
              "162.159.192.0/18",
              "162.159.0.0/16",
              "188.114.96.0/20"
            ],
            "outboundTag": "direct"
          },
          {
            "type": "field",
            "network": "udp",
            "port": "500,854,859,864,878,880,890,891,894,903,908,928,934,939,942,943,945,946,955,968,987,988,1002,1010,1014,1018,1070,1074,1180,1387,1843,2371,2408,2506,3138,3476,3581,3854,4177,4198,4233,4500,5279,5956,7103,7152,7156,7281,7559,8319,8742,8854,8886",
            "outboundTag": "direct"
          },
          {
            "type": "field",
            "network": "tcp,udp",
            "outboundTag": "proxy"
          }
        ]
      }
    };
    return jsonEncode(bridgeConfig);
  }

  // =========================================================================
  // روتینگ اختصاصی و کاملاً هماهنگ هسته تور (Tor Engine)
  // =========================================================================
  String _generateTorBridgeV2RayConfig() {
    final Map<String, dynamic> bridgeConfig = {
      "log": {
        "loglevel": "none"
      },
      "inbounds": [
        {
          "tag": "socks-in",
          "port": 10808,
          "listen": "127.0.0.1",
          "protocol": "socks",
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls"],
            "routeOnly": false
          },
          "settings": {
            "auth": "noauth",
            "udp": true
          }
        }
      ],
      "outbounds": [
        {
          "tag": "tor-proxy",
          "protocol": "socks",
          "settings": {
            "servers": [
              {
                "address": "127.0.0.1",
                "port": 9050
              }
            ]
          }
        },
        {
          "tag": "direct",
          "protocol": "freedom",
          "settings": {
            "domainStrategy": "UseIP"
          }
        },
        {
          "tag": "block",
          "protocol": "blackhole"
        }
      ],
      "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
          {
            "type": "field",
            "network": "udp",
            "port": "443,853",
            "outboundTag": "block"
          },
          {
            "type": "field",
            "ip": [
              "127.0.0.1/32",
              "162.159.192.0/18",
              "162.159.0.0/16",
              "188.114.96.0/20"
            ],
            "outboundTag": "direct"
          },
          {
            "type": "field",
            "network": "udp",
            "port": "500,854,859,864,878,880,890,891,894,903,908,928,934,939,942,943,945,946,955,968,987,988,1002,1010,1014,1018,1070,1074,1180,1387,1843,2371,2408,2506,3138,3476,3581,3854,4177,4198,4233,4500,5279,5956,7103,7152,7156,7281,7559,8319,8742,8854,8886",
            "outboundTag": "direct"
          },
          {
            "type": "field",
            "network": "tcp,udp",
            "outboundTag": "tor-proxy"
          }
        ]
      }
    };
    return jsonEncode(bridgeConfig);
  }

  Future<void> _connectTor() async {
    if (_isTorConnecting) return;

    await _disconnectTor();
    await _disconnectAether();
    await flutterV2ray.stopV2Ray();
    await Future.delayed(const Duration(milliseconds: 300));

    setState(() {
      _isTorConnecting = true;
      _torBootstrapProgress = 0;
      _torCurrentStep = 0;
      _torStepStatus = _t("tor_step_cleanup");
    });

    try {
      await _torChannel.invokeMethod('killAllCores');
      await Future.delayed(const Duration(milliseconds: 300));

      int? upstreamPort;

      if (_selectedTorMode == "aether_masque" || _selectedTorMode == "aether_quic") {
        upstreamPort = 1819;
        final String aetherMode = _selectedTorMode == "aether_masque" ? "masque_h2" : "masque";

        if (mounted) {
          setState(() {
            _torCurrentStep = 1;
            _torStepStatus = _t("tor_step_aether_start");
          });
        }

        final bool aetherStarted = await _aetherChannel.invokeMethod('startAether', {
          'mode': aetherMode,
          'port': 1819,
          'noize': 'firewall',
        }) ?? false;

        if (!aetherStarted) {
          throw Exception(_t("aether_start_err"));
        }

        bool aetherReady = false;
        for (int i = 0; i < 40; i++) {
          await Future.delayed(const Duration(milliseconds: 300));
          aetherReady = await _aetherChannel.invokeMethod('checkSocksReady', {
            'port': 1819,
            'timeoutMs': 600,
          }) ?? false;
          if (aetherReady) break;
        }

        if (!aetherReady) {
          throw Exception(_t("aether_port_timeout"));
        }

        if (mounted) {
          setState(() {
            _torStepStatus = _t("tor_step_aether_test");
          });
        }

        bool aetherCanPassTraffic = false;
        for (int i = 0; i < 15; i++) {
          await Future.delayed(const Duration(milliseconds: 400));
          aetherCanPassTraffic = await _aetherChannel.invokeMethod('testAetherEgress', {
            'port': 1819,
            'timeoutMs': 3500,
          }) ?? false;
          if (aetherCanPassTraffic) break;
        }

        if (!aetherCanPassTraffic) {
          throw Exception(_t("aether_egress_err"));
        }
      }

      if (mounted) {
        setState(() {
          _torCurrentStep = 2;
          _torStepStatus = _t("tor_step_tor_start");
        });
      }

      final List<String> bridges = _customBridgeController.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final bool torStarted = await _torChannel.invokeMethod('startTor', {
        'socksPort': 9050,
        'upstreamPort': upstreamPort,
        'mode': _selectedTorMode,
        'bridges': bridges,
      }) ?? false;

      if (!torStarted) {
        throw Exception(_t("tor_start_err"));
      }

      _torProgressTimer?.cancel();
      bool torReached100 = false;

      _torProgressTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) async {
        try {
          final dynamic status = await _torChannel.invokeMethod('getTorStatus');
          if (status is Map) {
            final int percent = status['percent'] ?? 0;
            if (mounted) {
              setState(() {
                if (percent > _torBootstrapProgress) {
                  _torBootstrapProgress = percent;
                }
                if (percent > 0) {
                  _torStepStatus = "${_t("tor_building_circuits")} $percent%";
                }
              });
            }
            if (percent >= 100) {
              torReached100 = true;
            }
          }
        } catch (_) {}
      });

      for (int i = 0; i < 140; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final bool socksReady = await _torChannel.invokeMethod('checkTorReady', {
          'socksPort': 9050,
          'timeoutMs': 800,
        }) ?? false;

        if (socksReady && (torReached100 || _torBootstrapProgress >= 100)) {
          if (mounted) {
            setState(() {
              _torBootstrapProgress = 100;
            });
          }
          break;
        }
      }

      _torProgressTimer?.cancel();
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        setState(() {
          _torCurrentStep = 3;
          _torStepStatus = _t("tor_step_vpn_start");
        });
      }

      if (await flutterV2ray.requestPermission()) {
        final String torConfig = _generateTorBridgeV2RayConfig();
        
        flutterV2ray.startV2Ray(
          remark: "Tor (${_selectedTorMode.toUpperCase()})",
          config: torConfig,
          proxyOnly: false,
          notificationDisconnectButtonName: "DISCONNECT",
        );

        if (mounted) {
          setState(() {
            _isTorActive = true;
            _isTorConnecting = false;
            _torStepStatus = _t("tor_connected_banner");
          });
        }
        _showSnackBar(_t("tor_connected_banner"));
      } else {
        await _disconnectTor();
        _showSnackBar(_t("os_perm_err"));
      }
    } catch (e) {
      print("Tor Connection Error: $e");
      await _disconnectTor();
      _showSnackBar(e.toString().replaceAll("Exception: ", ""));
    } finally {
      _torProgressTimer?.cancel();
      if (mounted) {
        setState(() {
          _isTorConnecting = false;
        });
      }
    }
  }

  Future<void> _disconnectTor() async {
    _torProgressTimer?.cancel();
    setState(() {
      _isTorConnecting = false;
      _isTorActive = false;
      _torBootstrapProgress = 0;
      _torCurrentStep = 0;
      _torStepStatus = _t("disconnected");
    });

    await flutterV2ray.stopV2Ray();
    try {
      await _torChannel.invokeMethod('stopTor');
    } catch (_) {}
    try {
      await _aetherChannel.invokeMethod('stopAether');
    } catch (_) {}
  }

  Future<void> _connectAether() async {
    if (_isAetherConnecting) return;

    if (v2rayStatus.value.state == "CONNECTED" || _isAetherActive || _isTorActive) {
      await _disconnectTor();
      await _disconnectAether();
      await Future.delayed(const Duration(milliseconds: 600));
    }

    setState(() {
      _isAetherConnecting = true;
    });

    _showSnackBar(_t("aether_launching"));

    try {
      final bool started = await _aetherChannel.invokeMethod('startAether', {
        'mode': _selectedAetherMode,
        'port': 1819,
        'noize': 'firewall',
      }) ?? false;

      if (!started) {
        throw Exception("Failed to launch Aether binary");
      }

      bool socksReady = false;
      for (int i = 0; i < 80; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        socksReady = await _aetherChannel.invokeMethod('checkSocksReady', {
          'port': 1819,
          'timeoutMs': 700,
        }) ?? false;

        if (socksReady) break;
      }

      if (!socksReady) {
        throw Exception("Aether SOCKS5 timeout on port 1819");
      }

      if (await flutterV2ray.requestPermission()) {
        final String aetherConfig = _generateAetherBridgeV2RayConfig();
        
        flutterV2ray.startV2Ray(
          remark: "Aether (${_selectedAetherMode.toUpperCase()})",
          config: aetherConfig,
          proxyOnly: false,
          notificationDisconnectButtonName: "DISCONNECT",
        );

        if (mounted) {
          setState(() {
            _isAetherActive = true;
            _isAetherConnecting = false;
          });
        }
        _showSnackBar(_t("aether_connected_banner"));
      } else {
        await _disconnectAether();
        _showSnackBar(_t("os_perm_err"));
      }
    } catch (e) {
      print("Aether Connection Error: $e");
      await _disconnectAether();
      _showSnackBar(_t("aether_start_err"));
    } finally {
      if (mounted) {
        setState(() {
          _isAetherConnecting = false;
        });
      }
    }
  }

  Future<void> _disconnectAether() async {
    setState(() {
      _isAetherConnecting = false;
      _isAetherActive = false;
    });

    await flutterV2ray.stopV2Ray();
    try {
      await _aetherChannel.invokeMethod('stopAether');
    } catch (_) {}
  }

  Future<void> _loadExhaustedWorkers() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString('exhausted_workers_data');
      
      if (jsonStr != null) {
        final Map<String, dynamic> data = jsonDecode(jsonStr);
        final String savedDate = data['date'] ?? '';
        final String todayDate = DateTime.now().toIso8601String().substring(0, 10);

        if (savedDate == todayDate) {
          final List<dynamic>? workers = data['workers'];
          if (workers != null) {
            _locallyExhaustedWorkers.addAll(workers.cast<String>());
          }
        } else {
          await prefs.remove('exhausted_workers_data');
        }
      }
    } catch (e) {
      print("Error loading exhausted workers: $e");
    }
  }

  Future<void> _saveExhaustedWorkers() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String todayDate = DateTime.now().toIso8601String().substring(0, 10);
      
      final Map<String, dynamic> data = {
        'date': todayDate,
        'workers': _locallyExhaustedWorkers.toList(),
      };
      
      await prefs.setString('exhausted_workers_data', jsonEncode(data));
    } catch (e) {
      print("Error saving exhausted workers: $e");
    }
  }

  Future<void> _reportDeltaUsage({int? forceDownload, int? forceUpload}) async {
    if (_selectedAccountIndex < 0 || _selectedAccountIndex >= _fetchedAccounts.length) return;

    final int currentDownload = forceDownload ?? v2rayStatus.value.download;
    final int currentUpload = forceUpload ?? v2rayStatus.value.upload;

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

    if (activeWorker.isEmpty) return;

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
      }
    } catch (e) {
      print("Telemetry error: $e");
    } finally {
      client.close();
    }
  }

  void _checkAndAutoSwitchLimit(Map<String, String> currentAccount, int totalBytesSession) async {
    final int previouslyUsedDatabase = int.tryParse(currentAccount['used_bytes'] ?? '0') ?? 0;
    final int currentRealtimeDailyUsage = previouslyUsedDatabase + totalBytesSession;
    final String activeWorker = currentAccount['worker'] ?? '';

    if (currentRealtimeDailyUsage >= _maxDailyBytes) {
      _locallyExhaustedWorkers.add(activeWorker);
      await _saveExhaustedWorkers();
      
      _showSnackBar(_t("limit_exhausted_banner"));
      _disconnect();
      
      await _fetchAndLoadAccounts();

      if (_fetchedAccounts.isNotEmpty && !_serversUpdatingMode) {
        if (!mounted) return;
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
        _showSnackBar("امکان باز کردن آدرس وجود ندارد");
      }
    } catch (e) {
      _showSnackBar("خطا: $e");
    }
  }

  void _openDonationDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF3B82F6), width: 1.2),
          ),
          title: const Row(
            children: [
              Icon(Icons.favorite_rounded, color: Colors.amberAccent, size: 24),
              SizedBox(width: 10),
              Text(
                'حمایت مالی از پروژه (Donate)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'با حمایت مالی خود، به پایداری، ارتقا و نگهداری سرورهای ضدسانسور RedCloud کمک می‌کنید. بی‌نهایت سپاسگزاریم! ❤️',
                  style: TextStyle(fontSize: 12.5, color: Colors.white70, height: 1.6),
                  textAlign: TextAlign.justify,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.currency_bitcoin_rounded, color: Colors.greenAccent, size: 18),
                              SizedBox(width: 6),
                              Text(
                                'ارز: USDT (Tether)',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.amber.withOpacity(0.4)),
                            ),
                            child: const Text(
                              'BNB Smart Chain (BEP20)',
                              style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'آدرس کیف پول:',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        usdtBnbAddress,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Clipboard.setData(const ClipboardData(text: usdtBnbAddress));
                            Navigator.pop(context);
                            _showSnackBar('آدرس ولت با موفقیت کپی شد! تشکر از حمایت شما ❤️');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: const Icon(Icons.copy_rounded, color: Colors.white, size: 16),
                          label: const Text(
                            'کپی آدرس کیف پول',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('بستن', style: TextStyle(color: Colors.grey)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _fetchAndLoadAccounts({bool showMessage = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoadingAccounts = true;
      _serversUpdatingMode = false;
    });

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
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

        parsed.sort((a, b) {
          final int pA = int.tryParse(a['priority'] ?? '1') ?? 1;
          final int pB = int.tryParse(b['priority'] ?? '1') ?? 1;
          return pA.compareTo(pB);
        });

        if (!mounted) return;
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
      if (mounted) {
        setState(() {
          _isLoadingAccounts = false;
        });
      }
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
    
    if (!mounted) return;
    setState(() {
      _serverName = "${_t("tab_dashboard")} ${_selectedAccountIndex + 1}";
      _protocolType = "VLESS";
    });
  }

  void _connect() async {
    if (_isAetherActive) {
      await _disconnectAether();
    }
    if (_isTorActive) {
      await _disconnectTor();
    }

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

    if (!mounted) return;
    setState(() {
      _isScanningIPs = true;
      _isAetherActive = false;
      _isTorActive = false;
    });
    
    _showSnackBar(_t("connecting_msg"));

    // ۱. بررسی سلامت DNS و نجات خودکار از مسمومیت شبکه
    final dnsProbe = await _verifyDnsIp("1.1.1.1", timeoutMs: 1200);
    if (dnsProbe == null) {
      _showBannerNotification(
        _t("banner_dns_rescue"),
        color: const Color(0xFF8B5CF6),
        icon: Icons.security_rounded,
      );
      final rescuedDns = await _runDnsRescueScan();
      if (rescuedDns.isNotEmpty) {
        _activeVerifiedDnsList = rescuedDns;
      }
    }

    String activeWorker = "round-sea-8418.redcloudir.workers.dev";
    String activePath = "/";
    if (_selectedAccountIndex >= 0 && _selectedAccountIndex < _fetchedAccounts.length) {
      activeWorker = _fetchedAccounts[_selectedAccountIndex]['worker'] ?? activeWorker;
      activePath = _fetchedAccounts[_selectedAccountIndex]['path'] ?? activePath;
    }

    // ۲. اسکن واقعی لایه ۷ کلودفلر با فال‌بک دیتابیس بزرگ
    final String fastest = await _findFastestIP(activeWorker, activePath);
    
    if (!mounted) return;
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
    final int currentDownload = v2rayStatus.value.download;
    final int currentUpload = v2rayStatus.value.upload;

    await flutterV2ray.stopV2Ray();
    await _reportDeltaUsage(forceDownload: currentDownload, forceUpload: currentUpload);
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
          "servers": _activeVerifiedDnsList
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

          if (mounted) {
            setState(() {
              _serverName = v2rayURL.remark;
              _protocolType = protocol;
            });
          }
        }
      } catch (e) {
        _showSnackBar(_t("config_err"));
        return;
      }
    }

    try {
      final Map<String, dynamic> configMap = jsonDecode(configText);
      
      if (configMap.containsKey('inbounds') && configMap['inbounds'] is List) {
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
        "servers": _activeVerifiedDnsList,
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

      if (configMap.containsKey('outbounds') && configMap['outbounds'] is List) {
        final List<dynamic> outbounds = configMap['outbounds'];
        for (var outbound in outbounds) {
          if (outbound is Map<String, dynamic> && outbound.containsKey('streamSettings')) {
            final dynamic streamSettings = outbound['streamSettings'];
            if (streamSettings is Map<String, dynamic> && streamSettings.containsKey('tlsSettings')) {
              final dynamic tlsSettings = streamSettings['tlsSettings'];
              if (tlsSettings is Map<String, dynamic>) {
                tlsSettings.remove('allowInsecure');
              }
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
        body: Column(
          children: [
            // بنر ۵ ثانیه‌ای هوشمند و انیمیشنی اطلاع‌رسانی
            if (_bannerMessage != null)
              AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _bannerColor.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _bannerColor, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: _bannerColor.withOpacity(0.2),
                      blurRadius: 10,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: Row(
                  children: [
                    Icon(_bannerIcon, color: _bannerColor, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _bannerMessage!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _bannerColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(child: _buildCurrentTabContent()),
          ],
        ),
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
          selectedFontSize: 11,
          unselectedFontSize: 10,
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.dashboard_rounded),
              label: _t("tab_dashboard"),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.bolt_rounded),
              label: _t("tab_aether"),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.security_rounded),
              label: _t("tab_tor"),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.settings_rounded),
              label: _t("tab_settings"),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.verified_user_rounded),
              label: _t("tab_privacy"),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.volunteer_activism_rounded),
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
        return _buildAetherTab();
      case 2:
        return _buildTorTab();
      case 3:
        return _buildSettingsTab();
      case 4:
        return _buildPrivacyTab();
      case 5:
        return _buildContactTab();
      default:
        return _buildDashboardTab();
    }
  }

  Widget _buildDashboardTab() {
    return ValueListenableBuilder<V2RayStatus>(
      valueListenable: v2rayStatus,
      builder: (context, value, child) {
        final isConnected = value.state == "CONNECTED" && !_isAetherActive && !_isTorActive;
        final isConnecting = (value.state == "CONNECTING" || _isScanningIPs) && !_isAetherActive && !_isTorActive;

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
                    _formatBytes(isConnected ? value.downloadSpeed : 0, isSpeed: true),
                    Icons.arrow_downward,
                    const Color(0xFF10B981),
                  ),
                  _buildStatCard(
                    _t("up_speed"),
                    _formatBytes(isConnected ? value.uploadSpeed : 0, isSpeed: true),
                    Icons.arrow_upward,
                    const Color(0xFF3B82F6),
                  ),
                  _buildStatCard(
                    _t("total_down"),
                    _formatBytes(isConnected ? value.download : 0),
                    Icons.cloud_download,
                    Colors.blueGrey,
                  ),
                  _buildStatCard(
                    _t("total_up"),
                    _formatBytes(isConnected ? value.upload : 0),
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
                    "${_t("conn_time")}${isConnected ? value.duration : '00:00:00'}",
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

  Widget _buildAetherTab() {
    return ValueListenableBuilder<V2RayStatus>(
      valueListenable: v2rayStatus,
      builder: (context, value, child) {
        final isConnected = _isAetherActive && value.state == "CONNECTED";
        final isConnecting = _isAetherConnecting;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _t("aether_title"),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                _t("aether_subtitle"),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),

              Center(
                child: GestureDetector(
                  onTap: isConnecting
                      ? null
                      : isConnected
                          ? _disconnectAether
                          : _connectAether,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isConnected
                          ? const Color(0xFF06B6D4).withOpacity(0.15)
                          : isConnecting
                              ? const Color(0xFFF59E0B).withOpacity(0.15)
                              : const Color(0xFF64748B).withOpacity(0.1),
                      border: Border.all(
                        color: isConnected
                            ? const Color(0xFF06B6D4)
                            : isConnecting
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFF64748B).withOpacity(0.5),
                        width: 4,
                      ),
                      boxShadow: [
                        if (isConnected)
                          BoxShadow(
                            color: const Color(0xFF06B6D4).withOpacity(0.4),
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
                            width: 40,
                            height: 40,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                              strokeWidth: 3.5,
                            ),
                          )
                        else
                          Icon(
                            Icons.bolt,
                            size: 55,
                            color: isConnected
                                ? const Color(0xFF06B6D4)
                                : const Color(0xFF94A3B8),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          isConnected
                              ? _t("connected")
                              : isConnecting
                                  ? _t("connecting")
                                  : _t("disconnected"),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isConnected
                                ? const Color(0xFF06B6D4)
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

              Text(
                _t("aether_mode_select"),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueAccent),
              ),
              const SizedBox(height: 12),

              _buildAetherModeOption(
                modeKey: "auto",
                title: _t("mode_auto_title"),
                desc: _t("mode_auto_desc"),
                icon: Icons.auto_awesome,
                color: Colors.cyanAccent,
                disabled: isConnected || isConnecting,
              ),
              _buildAetherModeOption(
                modeKey: "masque_h2",
                title: _t("mode_masque_h2_title"),
                desc: _t("mode_masque_h2_desc"),
                icon: Icons.shield,
                color: Colors.cyan,
                disabled: isConnected || isConnecting,
              ),
              _buildAetherModeOption(
                modeKey: "masque",
                title: _t("mode_masque_title"),
                desc: _t("mode_masque_desc"),
                icon: Icons.flash_on,
                color: Colors.amber,
                disabled: isConnected || isConnecting,
              ),
              _buildAetherModeOption(
                modeKey: "gool",
                title: _t("mode_gool_title"),
                desc: _t("mode_gool_desc"),
                icon: Icons.layers,
                color: Colors.purpleAccent,
                disabled: isConnected || isConnecting,
              ),
              _buildAetherModeOption(
                modeKey: "wireguard",
                title: _t("mode_wireguard_title"),
                desc: _t("mode_wireguard_desc"),
                icon: Icons.vpn_lock,
                color: Colors.lightGreen,
                disabled: isConnected || isConnecting,
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
                    _formatBytes(isConnected ? value.downloadSpeed : 0, isSpeed: true),
                    Icons.arrow_downward,
                    const Color(0xFF06B6D4),
                  ),
                  _buildStatCard(
                    _t("up_speed"),
                    _formatBytes(isConnected ? value.uploadSpeed : 0, isSpeed: true),
                    Icons.arrow_upward,
                    const Color(0xFF3B82F6),
                  ),
                  _buildStatCard(
                    _t("total_down"),
                    _formatBytes(isConnected ? value.download : 0),
                    Icons.cloud_download,
                    Colors.blueGrey,
                  ),
                  _buildStatCard(
                    _t("total_up"),
                    _formatBytes(isConnected ? value.upload : 0),
                    Icons.cloud_upload,
                    Colors.blueGrey,
                  ),
                ],
              ),
              const SizedBox(height: 15),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTorTab() {
    return ValueListenableBuilder<V2RayStatus>(
      valueListenable: v2rayStatus,
      builder: (context, value, child) {
        final isConnected = _isTorActive && value.state == "CONNECTED";
        final isConnecting = _isTorConnecting;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _t("tor_title"),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                _t("tor_subtitle"),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 15),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isConnected 
                        ? const Color(0xFFA855F7) 
                        : isConnecting 
                            ? const Color(0xFFF59E0B) 
                            : Colors.white10,
                  ),
                ),
                child: Column(
                  children: [
                    _buildStepRow(
                      stepNumber: 1,
                      title: _t("tor_layer_aether"),
                      isDone: isConnected || (isConnecting && _torCurrentStep > 1),
                      isActive: isConnecting && _torCurrentStep == 1,
                    ),
                    const Divider(height: 12, color: Colors.white10),
                    _buildStepRow(
                      stepNumber: 2,
                      title: "${_t("tor_layer_tor")} ${_torBootstrapProgress > 0 ? '($_torBootstrapProgress%)' : ''}",
                      isDone: isConnected || (isConnecting && _torCurrentStep > 2),
                      isActive: isConnecting && _torCurrentStep == 2,
                    ),
                    const Divider(height: 12, color: Colors.white10),
                    _buildStepRow(
                      stepNumber: 3,
                      title: _t("tor_layer_vpn"),
                      isDone: isConnected,
                      isActive: isConnecting && _torCurrentStep == 3,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Center(
                child: GestureDetector(
                  onTap: isConnecting
                      ? null
                      : isConnected
                          ? _disconnectTor
                          : _connectTor,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 155,
                    height: 155,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isConnected
                          ? const Color(0xFF9333EA).withOpacity(0.15)
                          : isConnecting
                              ? const Color(0xFFF59E0B).withOpacity(0.15)
                              : const Color(0xFF64748B).withOpacity(0.1),
                      border: Border.all(
                        color: isConnected
                            ? const Color(0xFFA855F7)
                            : isConnecting
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFF64748B).withOpacity(0.5),
                        width: 4,
                      ),
                      boxShadow: [
                        if (isConnected)
                          BoxShadow(
                            color: const Color(0xFF9333EA).withOpacity(0.4),
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
                        if (isConnecting) ...[
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 45,
                                height: 45,
                                child: CircularProgressIndicator(
                                  value: _torBootstrapProgress > 0 ? _torBootstrapProgress / 100 : null,
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                                  strokeWidth: 3.5,
                                ),
                              ),
                              if (_torBootstrapProgress > 0)
                                Text(
                                  "$_torBootstrapProgress%",
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                                )
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _t("connecting"),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)),
                          ),
                        ] else ...[
                          Icon(
                            Icons.security_rounded,
                            size: 55,
                            color: isConnected
                                ? const Color(0xFFC084FC)
                                : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isConnected
                                ? _t("connected")
                                : _t("disconnected"),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isConnected
                                  ? const Color(0xFFC084FC)
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.only(top: 14.0),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _torStepStatus,
                      style: TextStyle(
                        fontSize: 12,
                        color: isConnected ? const Color(0xFFC084FC) : Colors.amberAccent,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 25),

              Text(
                _t("tor_mode_select"),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFC084FC)),
              ),
              const SizedBox(height: 12),

              _buildTorModeOption(
                modeKey: "aether_masque",
                title: _t("tor_mode_aether_masque_title"),
                desc: _t("tor_mode_aether_masque_desc"),
                icon: Icons.shield_rounded,
                color: const Color(0xFFA855F7),
                disabled: isConnected || isConnecting,
              ),
              _buildTorModeOption(
                modeKey: "aether_quic",
                title: _t("tor_mode_aether_quic_title"),
                desc: _t("tor_mode_aether_quic_desc"),
                icon: Icons.flash_on_rounded,
                color: Colors.cyanAccent,
                disabled: isConnected || isConnecting,
              ),
              _buildTorModeOption(
                modeKey: "snowflake",
                title: _t("tor_mode_snowflake_title"),
                desc: _t("tor_mode_snowflake_desc"),
                icon: Icons.ac_unit_rounded,
                color: Colors.amberAccent,
                disabled: isConnected || isConnecting,
              ),
              _buildTorModeOption(
                modeKey: "direct",
                title: _t("tor_mode_direct_title"),
                desc: _t("tor_mode_direct_desc"),
                icon: Icons.public_rounded,
                color: Colors.blueAccent,
                disabled: isConnected || isConnecting,
              ),
              _buildTorModeOption(
                modeKey: "custom",
                title: _t("tor_mode_custom_title"),
                desc: _t("tor_mode_custom_desc"),
                icon: Icons.edit_note_rounded,
                color: Colors.pinkAccent,
                disabled: isConnected || isConnecting,
              ),

              if (_selectedTorMode == "custom")
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, bottom: 12.0),
                  child: TextField(
                    controller: _customBridgeController,
                    maxLines: 3,
                    enabled: !isConnected && !isConnecting,
                    decoration: InputDecoration(
                      hintText: _t("tor_custom_bridge_hint"),
                      hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF9333EA)),
                      ),
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
                    _formatBytes(isConnected ? value.downloadSpeed : 0, isSpeed: true),
                    Icons.arrow_downward,
                    const Color(0xFFC084FC),
                  ),
                  _buildStatCard(
                    _t("up_speed"),
                    _formatBytes(isConnected ? value.uploadSpeed : 0, isSpeed: true),
                    Icons.arrow_upward,
                    const Color(0xFF3B82F6),
                  ),
                  _buildStatCard(
                    _t("total_down"),
                    _formatBytes(isConnected ? value.download : 0),
                    Icons.cloud_download,
                    Colors.blueGrey,
                  ),
                  _buildStatCard(
                    _t("total_up"),
                    _formatBytes(isConnected ? value.upload : 0),
                    Icons.cloud_upload,
                    Colors.blueGrey,
                  ),
                ],
              ),
              const SizedBox(height: 15),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStepRow({
    required int stepNumber,
    required String title,
    required bool isDone,
    required bool isActive,
  }) {
    return Row(
      children: [
        if (isDone)
          const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18)
        else if (isActive)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B)),
          )
        else
          CircleAvatar(
            radius: 8,
            backgroundColor: Colors.white24,
            child: Text("$stepNumber", style: const TextStyle(fontSize: 10, color: Colors.white70)),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: (isDone || isActive) ? FontWeight.bold : FontWeight.normal,
              color: isDone
                  ? const Color(0xFF10B981)
                  : isActive
                      ? const Color(0xFFF59E0B)
                      : Colors.white60,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTorModeOption({
    required String modeKey,
    required String title,
    required String desc,
    required IconData icon,
    required Color color,
    required bool disabled,
  }) {
    final bool isSelected = _selectedTorMode == modeKey;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: isSelected
            ? color.withOpacity(0.12)
            : Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isSelected ? color : Colors.grey.withOpacity(0.15),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          enabled: !disabled,
          onTap: () {
            setState(() {
              _selectedTorMode = modeKey;
            });
          },
          leading: CircleAvatar(
            backgroundColor: color.withOpacity(0.15),
            child: Icon(icon, color: color, size: 22),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? color : null,
            ),
          ),
          subtitle: Text(
            desc,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          trailing: Radio<String>(
            value: modeKey,
            groupValue: _selectedTorMode,
            activeColor: color,
            onChanged: disabled
                ? null
                : (val) {
                    if (val != null) {
                      setState(() {
                        _selectedTorMode = val;
                      });
                    }
                  },
          ),
        ),
      ),
    );
  }

  Widget _buildAetherModeOption({
    required String modeKey,
    required String title,
    required String desc,
    required IconData icon,
    required Color color,
    required bool disabled,
  }) {
    final bool isSelected = _selectedAetherMode == modeKey;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: isSelected
            ? color.withOpacity(0.12)
            : Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isSelected ? color : Colors.grey.withOpacity(0.15),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          enabled: !disabled,
          onTap: () {
            setState(() {
              _selectedAetherMode = modeKey;
            });
          },
          leading: CircleAvatar(
            backgroundColor: color.withOpacity(0.15),
            child: Icon(icon, color: color, size: 22),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? color : null,
            ),
          ),
          subtitle: Text(
            desc,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          trailing: Radio<String>(
            value: modeKey,
            groupValue: _selectedAetherMode,
            activeColor: color,
            onChanged: disabled
                ? null
                : (val) {
                    if (val != null) {
                      setState(() {
                        _selectedAetherMode = val;
                      });
                    }
                  },
          ),
        ),
      ),
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
                textAlign: TextAlign.start,
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
                _buildActionGridCard(
                  _t("contact_telegram"),
                  Icons.send_rounded,
                  const Color(0xFF229ED9),
                  () => _launchURL(telegramChannelUrl),
                ),
                _buildActionGridCard(
                  _t("contact_donate"),
                  Icons.favorite_rounded,
                  Colors.amberAccent,
                  _openDonationDialog,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionGridCard(String title, IconData icon, Color color, VoidCallback onTap) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: color.withOpacity(0.3), width: 1.2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: color.withOpacity(0.15),
                child: Icon(icon, color: color, size: 30),
              ),
              const SizedBox(height: 14),
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