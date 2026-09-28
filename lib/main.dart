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

const String workerApiUrl = "https://round-sea-8418.redcloudir.workers.dev";
const String githubRawUrl = "https://raw.githubusercontent.com/Devtahas/Devtahas-redcloud-config/main/accounts.json";
const String telegramChannelUrl = "https://t.me/DevTaha_project";
const String usdtBnbAddress = "0xDeda28Aa73Ec089A77B3fC616E0011a8fce12900";
const String appPackageName = "com.redcloud.vpn.redcloud_android";

enum ActiveEngine { none, dashboard, aether, tor, psiphon }

class LogEntry {
  final DateTime time;
  final String tag;
  final String message;
  final bool isError;

  LogEntry({
    required this.time,
    required this.tag,
    required this.message,
    this.isError = false,
  });

  String format() {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    final ms = time.millisecond.toString().padLeft(3, '0');
    return "[$h:$m:$s.$ms] [$tag] $message";
  }
}

class AppLogger {
  static final List<LogEntry> _logs = [];
  static final ValueNotifier<int> logCountNotifier = ValueNotifier<int>(0);
  static const int maxLogs = 500;

  static void log(String tag, String message, {bool isError = false}) {
    final entry = LogEntry(
      time: DateTime.now(),
      tag: tag,
      message: message,
      isError: isError,
    );

    if (kDebugMode) {
      print(entry.format());
    }

    if (_logs.length >= maxLogs) {
      _logs.removeAt(0);
    }
    _logs.add(entry);
    logCountNotifier.value = _logs.length;
  }

  static void addNativeLog(String rawLine) {
    final isErr = rawLine.toLowerCase().contains("error") || 
                  rawLine.toLowerCase().contains("fail") || 
                  rawLine.toLowerCase().contains("crash") ||
                  rawLine.toLowerCase().contains("aborted");
    final entry = LogEntry(
      time: DateTime.now(),
      tag: "NATIVE",
      message: rawLine,
      isError: isErr,
    );
    if (_logs.length >= maxLogs) {
      _logs.removeAt(0);
    }
    _logs.add(entry);
    logCountNotifier.value = _logs.length;
  }

  static List<LogEntry> get currentLogs => List.unmodifiable(_logs);

  static void clear() {
    _logs.clear();
    logCountNotifier.value = 0;
  }

  static String getAllLogsFormatted() {
    return _logs.map((e) => e.format()).join("\n");
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final String initialLang = prefs.getString('saved_app_language') ?? 'fa';
  final bool initialDarkMode = prefs.getBool('saved_dark_mode') ?? true;
  final bool isFirstRun = prefs.getBool('first_launch_lang_selected') != true;

  AppLogger.log("SYSTEM", "RedCloud VPN Initialized.");
  runApp(MyApp(
    initialLang: initialLang,
    initialDarkMode: initialDarkMode,
    isFirstRun: isFirstRun,
  ));
}

class MyApp extends StatefulWidget {
  final String initialLang;
  final bool initialDarkMode;
  final bool isFirstRun;

  const MyApp({
    super.key,
    required this.initialLang,
    required this.initialDarkMode,
    required this.isFirstRun,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late bool _isDarkMode;
  late String _currentLang;

  @override
  void initState() {
    super.initState();
    _isDarkMode = widget.initialDarkMode;
    _currentLang = widget.initialLang;
  }

  void _toggleTheme() async {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool('saved_dark_mode', _isDarkMode);
    } catch (_) {}
  }

  void _changeLang(String lang) async {
    setState(() {
      _currentLang = lang;
    });
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_app_language', lang);
      await prefs.setBool('first_launch_lang_selected', true);
    } catch (_) {}
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
        isFirstRun: widget.isFirstRun,
        toggleTheme: _toggleTheme,
        changeLang: _changeLang,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final bool isDarkMode;
  final String currentLang;
  final bool isFirstRun;
  final VoidCallback toggleTheme;
  final Function(String) changeLang;

  const HomePage({
    super.key,
    required this.isDarkMode,
    required this.currentLang,
    required this.isFirstRun,
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
  
  ActiveEngine _activeEngine = ActiveEngine.none;
  bool _isTransitioning = false;
  bool _bypassIran = true;
  bool _isHybridMode = false;
  String _hybridStatusText = "";

  Timer? _logTimer;
  Timer? _reportTimer;
  Timer? _torProgressTimer;
  Timer? _bannerTimer;
  Timer? _heartbeatTimer;
  int _currentTabIndex = 0;

  String? _publicIp;
  String? _ipCountry;
  String? _ipCountryCode;
  String? _ipFlagEmoji;
  int? _realPingMs;
  bool _isTestingIp = false;
  
  late final V2ray flutterV2ray = V2ray(
    onStatusChanged: (status) {
      v2rayStatus.value = status;
      if (status.state == "CONNECTED" && _activeEngine != ActiveEngine.none) {
        if (_publicIp == null && !_isTestingIp) {
          Timer(const Duration(milliseconds: 1500), () {
            if (mounted && _activeEngine != ActiveEngine.none && !_isTestingIp) {
              _fetchPublicIpAndPing();
            }
          });
        }
      }

      if (_activeEngine == ActiveEngine.dashboard && status.state == "CONNECTED" && _selectedAccountIndex >= 0) {
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

  String? _bannerMessage;
  Color _bannerColor = const Color(0xFF3B82F6);
  IconData _bannerIcon = Icons.info_outline_rounded;

  String _selectedAetherMode = "auto";
  String _selectedTorMode = "aether_masque";
  int _torBootstrapProgress = 0;

  String _atcAccountName = "";
  int _atcRemainingDays = 30;

  Future<void> _fetchAtcInfo() async {
    try {
      final dynamic info = await _aetherChannel.invokeMethod('getAtcAccountInfo');
      if (info is Map && mounted) {
        setState(() {
          _atcAccountName = info['account']?.toString() ?? "";
          _atcRemainingDays = (info['remainingDays'] as num?)?.toInt() ?? 30;
        });
      }
    } catch (_) {}
  }
  String _torStepStatus = "آماده اتصال";
  int _torCurrentStep = 0;

  bool _isPsiphonHybrid = true;
  String _selectedPsiphonCountry = "CA";
  final List<Map<String, String>> _psiphonCountries = [
    {"code": "CA", "name": "Canada 🇨🇦 (کانادا)"},
    {"code": "DE", "name": "Germany 🇩🇪 (آلمان)"},
    {"code": "US", "name": "United States 🇺🇸 (آمریکا)"},
    {"code": "GB", "name": "United Kingdom 🇬🇧 (انگلیس)"},
    {"code": "NL", "name": "Netherlands 🇳🇱 (هلند)"},
    {"code": "FR", "name": "France 🇫🇷 (فرانسه)"},
    {"code": "AUTO", "name": "Best Available (خودکار)"},
  ];

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
      
      "hybrid_mode_label": "هیبریدی (اتر + کانفیگ)",
      "hybrid_starting": "در حال آزمایش و اتصال هوشمند موتور اَتر...",
      "hybrid_failed": "خطا در اتصال اَتر هوشمند؛ پروتکل‌ها پاسخگو نبودند.",
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
      "aether_launching": "در حال راه‌اندازی و آزمایش خودکار پروتکل‌های ضدسانسور...",
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
      "tor_custom_bridge_hint": "Enter bridge lines here...",
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

      "logs_title": "گزارشات و لاگ‌های سیستم",
      "logs_subtitle": "رویدادهای زنده، وضعیت هسته‌ها و عیب‌یابی خطاها",
      "logs_view_btn": "مشاهده و مدیریت لاگ‌ها",
      "logs_empty": "هنوز هیچ لاگی در سیستم ثبت نشده است.",
      "logs_copied": "تمام لاگ‌های سیستم در کلیپ‌بورد کپی شد!",
      "logs_cleared": "تمامی لاگ‌ها با موفقیت پاک‌سازی شدند.",
      "logs_copy_all": "کپی تمام لاگ‌ها",
      "logs_clear_all": "پاک‌سازی لاگ‌ها",
      "logs_search_hint": "جستجو در میان لاگ‌ها...",

      "battery_opt_title": "بهینه‌سازی باتری و پایداری در پس‌زمینه",
      "battery_opt_desc": "جهت جلوگیری از قطع شدن اتصال پس از چند دقیقه در پس‌زمینه، بهینه‌سازی باتری را برای برنامه خاموش کنید.",
      "battery_opt_btn": "تنظیم عدم محدودیت باتری (Unrestricted)",

      "bypass_iran_title": "بایپس سایت‌های ایرانی (Bypass Iran)",
      "bypass_iran_desc": "عبور مستقیم سایت‌های داخلی (.ir)، بانکی و دولتی بدون فیلترشکن",

      "testing_ip_info": "در حال دریافت مشخصات سرور خروجی...",
      "live_ping_label": "پینگ زنده",
      "public_ip_label": "آی‌پی سرور",
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

      "logs_title": "System Logs & Diagnostics",
      "logs_subtitle": "Live events, debug traces & error logs",
      "logs_view_btn": "View System Logs",
      "logs_empty": "No logs recorded yet.",
      "logs_copied": "All logs copied to clipboard!",
      "logs_cleared": "Logs cleared successfully.",
      "logs_copy_all": "Copy All Logs",
      "logs_clear_all": "Clear Logs",
      "logs_search_hint": "Search inside logs...",

      "battery_opt_title": "Battery Optimization & Background Stability",
      "battery_opt_desc": "Disable battery optimization for this app to prevent Android from closing the connection after 10 minutes in the background.",
      "battery_opt_btn": "Set Battery to Unrestricted",

      "bypass_iran_title": "Bypass Domestic Sites (Bypass Iran)",
      "bypass_iran_desc": "Direct routing for .ir domains and domestic banking traffic without VPN",

      "testing_ip_info": "Discovering exit server info...",
      "live_ping_label": "Live Ping",
      "public_ip_label": "Server IP",
    }
  };

  String _t(String key) {
    return _localizedValues[widget.currentLang]?[key] ?? _localizedValues["en"]?[key] ?? key;
  }

  String _countryCodeToEmoji(String countryCode) {
    if (countryCode.length != 2) return "🌐";
    final int firstLetter = countryCode.toUpperCase().codeUnitAt(0) - 0x41 + 0x1F1E6;
    final int secondLetter = countryCode.toUpperCase().codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCode(firstLetter) + String.fromCharCode(secondLetter);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (timer) async {
      if (_activeEngine == ActiveEngine.none) {
        timer.cancel();
        return;
      }
      try {
        int targetPort = 10808;
        if (_activeEngine == ActiveEngine.aether) targetPort = 1819;
        if (_activeEngine == ActiveEngine.tor) targetPort = 9050;
        if (_activeEngine == ActiveEngine.psiphon) targetPort = 9081;

        final socket = await Socket.connect('127.0.0.1', targetPort, timeout: const Duration(seconds: 2));
        socket.destroy();
      } catch (_) {}
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<Map<String, dynamic>?> _querySocks5Json(int socksPort, String targetHost, String path, {int timeoutMs = 4500}) async {
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect('127.0.0.1', socksPort, timeout: Duration(milliseconds: timeoutMs));

      socket.add([0x05, 0x01, 0x00]);
      await socket.flush();

      final completer = Completer<Map<String, dynamic>?>();
      final List<int> buffer = [];
      int stage = 0;

      socket.listen((data) {
        buffer.addAll(data);

        if (stage == 0) {
          if (buffer.length >= 2) {
            if (buffer[0] == 0x05 && buffer[1] == 0x00) {
              buffer.clear();
              stage = 1;
              final hostBytes = utf8.encode(targetHost);
              final connectReq = [
                0x05, 0x01, 0x00, 0x03, hostBytes.length, ...hostBytes, 0x00, 0x50
              ];
              socket?.add(connectReq);
              socket?.flush();
            } else {
              if (!completer.isCompleted) completer.complete(null);
            }
          }
        } else if (stage == 1) {
          if (buffer.length >= 10) {
            if (buffer[0] == 0x05 && buffer[1] == 0x00) {
              buffer.clear();
              stage = 2;
              final httpRequest = "GET $path HTTP/1.1\r\n"
                  "Host: $targetHost\r\n"
                  "User-Agent: Mozilla/5.0 (Android; Linux)\r\n"
                  "Connection: close\r\n\r\n";
              socket?.add(utf8.encode(httpRequest));
              socket?.flush();
            } else {
              if (!completer.isCompleted) completer.complete(null);
            }
          }
        } else if (stage == 2) {
          final responseText = utf8.decode(buffer, allowMalformed: true);
          if (responseText.contains("\r\n\r\n")) {
            final parts = responseText.split("\r\n\r\n");
            if (parts.length > 1) {
              final jsonPart = parts.sublist(1).join("\r\n\r\n").trim();
              try {
                final Map<String, dynamic> parsed = jsonDecode(jsonPart);
                stopwatch.stop();
                parsed['pingMs'] = stopwatch.elapsedMilliseconds;
                if (!completer.isCompleted) completer.complete(parsed);
                return;
              } catch (_) {}
            }
          }
        }
      }, onError: (_) {
        if (!completer.isCompleted) completer.complete(null);
      }, onDone: () {
        if (!completer.isCompleted) completer.complete(null);
      });

      Timer(Duration(milliseconds: timeoutMs), () {
        if (!completer.isCompleted) completer.complete(null);
      });

      return await completer.future;
    } catch (_) {
      return null;
    } finally {
      try { socket?.destroy(); } catch (_) {}
    }
  }

  Future<void> _fetchPublicIpAndPing() async {
    if (_activeEngine == ActiveEngine.none) return;

    if (mounted) {
      setState(() {
        _isTestingIp = true;
        _publicIp = null;
        _ipCountry = null;
        _ipCountryCode = null;
        _ipFlagEmoji = null;
        _realPingMs = null;
      });
    }

    int targetSocksPort = 10808;
    if (_activeEngine == ActiveEngine.aether) targetSocksPort = 1819;
    if (_activeEngine == ActiveEngine.tor) targetSocksPort = 9050;
    if (_activeEngine == ActiveEngine.psiphon) targetSocksPort = 9081;

    try {
      Map<String, dynamic>? data = await _querySocks5Json(targetSocksPort, "ip-api.com", "/json/", timeoutMs: 3500);
      
      if (data == null || data['status'] != 'success') {
        await Future.delayed(const Duration(milliseconds: 300));
        final fallbackData = await _querySocks5Json(targetSocksPort, "ipwho.is", "/", timeoutMs: 4000);
        if (fallbackData != null && (fallbackData['success'] == true || fallbackData['ip'] != null)) {
          data = {
            'status': 'success',
            'query': fallbackData['ip'],
            'country': fallbackData['country'],
            'countryCode': fallbackData['country_code'],
            'pingMs': fallbackData['pingMs'] ?? 0,
          };
        }
      }

      if (data != null && data['status'] == 'success' && mounted) {
        final ip = data['query']?.toString() ?? '';
        final country = data['country']?.toString() ?? '';
        final countryCode = data['countryCode']?.toString() ?? '';
        final ping = data['pingMs'] as int? ?? 0;

        if (ip.isNotEmpty) {
          setState(() {
            _publicIp = ip;
            _ipCountry = country.isNotEmpty ? country : "Connected Server";
            _ipCountryCode = countryCode;
            _ipFlagEmoji = _countryCodeToEmoji(countryCode);
            _realPingMs = ping;
            _isTestingIp = false;
          });
          AppLogger.log("TELEMETRY", "Exit Server IP: $_publicIp ($_ipCountry $_ipFlagEmoji) | Latency: ${ping}ms");
          return;
        }
      }
    } catch (e) {
      AppLogger.log("TELEMETRY", "استعلام تلمتری: $e");
    } finally {
      if (mounted && _isTestingIp) {
        setState(() {
          _isTestingIp = false;
        });
      }
    }
  }

  void _showFirstLaunchLanguageModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
            ),
            title: const Row(
              children: [
                Icon(Icons.language_rounded, color: Color(0xFF3B82F6), size: 28),
                SizedBox(width: 10),
                Text(
                  "زبان / Language",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "لطفاً زبان پیش‌فرض برنامه را انتخاب کنید:\nPlease select your preferred app language:",
                  style: TextStyle(fontSize: 13, color: Colors.white70, height: 1.5),
                ),
                const SizedBox(height: 20),
                ListTile(
                  tileColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Colors.white12),
                  ),
                  leading: const Text("🇮🇷", style: TextStyle(fontSize: 24)),
                  title: const Text("فارسی (Persian)", style: TextStyle(fontWeight: FontWeight.bold)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  onTap: () {
                    widget.changeLang("fa");
                    Navigator.pop(dialogContext);
                  },
                ),
                const SizedBox(height: 10),
                ListTile(
                  tileColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Colors.white12),
                  ),
                  leading: const Text("🇬🇧", style: TextStyle(fontSize: 24)),
                  title: const Text("English (انگلیسی)", style: TextStyle(fontWeight: FontWeight.bold)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  onTap: () {
                    widget.changeLang("en");
                    Navigator.pop(dialogContext);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
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
    AppLogger.log("CORE", "Initializing Flutter V2Ray plugin...");
    flutterV2ray.initialize(
      notificationIconResourceType: "mipmap",
      notificationIconResourceName: "ic_launcher",
    );
    _initApp();

    if (widget.isFirstRun) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showFirstLaunchLanguageModal();
      });
    }
  }

  Future<void> _saveEngineState(ActiveEngine engine) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_engine_state', engine.name);
    } catch (_) {}
  }

  Future<void> _loadBypassIranSetting() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool? savedBypass = prefs.getBool('bypass_iran_traffic');
      final bool? savedHybrid = prefs.getBool('hybrid_mode_traffic');
      if (mounted) {
        setState(() {
          if (savedBypass != null) _bypassIran = savedBypass;
          if (savedHybrid != null) _isHybridMode = savedHybrid;
        });
      }
    } catch (_) {}
  }

  Future<void> _setHybridModeSetting(bool value) async {
    setState(() {
      _isHybridMode = value;
    });
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hybrid_mode_traffic', value);
      AppLogger.log("HYBRID", "وضعیت حالت هیبریدی: $value");
    } catch (_) {}

    if (_selectedAccountIndex >= 0 && _selectedAccountIndex < _fetchedAccounts.length) {
      _updateSelectedConfig();
    }
  }

  Future<void> _setBypassIranSetting(bool value) async {
    setState(() {
      _bypassIran = value;
    });
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool('bypass_iran_traffic', value);
      AppLogger.log("ROUTING", "وضعیت بایپس ایران: $value");
    } catch (_) {}

    if (_selectedAccountIndex >= 0 && _selectedAccountIndex < _fetchedAccounts.length) {
      _updateSelectedConfig();
    }
  }

  Future<void> _restoreSavedState() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? savedState = prefs.getString('active_engine_state');
      if (savedState != null) {
        final ActiveEngine engine = ActiveEngine.values.firstWhere(
          (e) => e.name == savedState,
          orElse: () => ActiveEngine.none,
        );

        if (engine != ActiveEngine.none) {
          bool aetherAlive = false;
          bool torAlive = false;
          try { 
            aetherAlive = await _aetherChannel.invokeMethod('isAetherRunning') ?? false; 
          } catch (_) {}
          try { 
            torAlive = await _torChannel.invokeMethod('isTorRunning') ?? false; 
          } catch (_) {}

          if (engine == ActiveEngine.aether && aetherAlive) {
            if (mounted) setState(() => _activeEngine = ActiveEngine.aether);
            _startHeartbeat();
            AppLogger.log("STATE", "وضعیت اتصال اَتر از پس‌زمینه بازیابی شد.");
          } else if (engine == ActiveEngine.tor && torAlive) {
            if (mounted) setState(() => _activeEngine = ActiveEngine.tor);
            _startHeartbeat();
            AppLogger.log("STATE", "وضعیت اتصال تور از پس‌زمینه بازیابی شد.");
          } else if (engine == ActiveEngine.dashboard) {
            if (mounted) setState(() => _activeEngine = ActiveEngine.dashboard);
            _startHeartbeat();
            AppLogger.log("STATE", "وضعیت اتصال داشبورد از پس‌زمینه بازیابی شد.");
          }
        }
      }
    } catch (e) {
      AppLogger.log("STATE", "خطا در بازیابی وضعیت پس‌زمینه: $e");
    }
  }

  Future<void> _initApp() async {
    await _loadBypassIranSetting();
    await _loadExhaustedWorkers();
    await _fetchAndLoadAccounts();
    await _restoreSavedState();
    _fetchAtcInfo();

    _logTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final List<String> v2Logs = await flutterV2ray.getLogs();
        if (v2Logs.isNotEmpty) {
          for (var log in v2Logs) {
            AppLogger.log("V2RAY-CORE", log);
          }
          await flutterV2ray.clearLogs();
        }
      } catch (_) {}

      try {
        final dynamic rawNativeLogs = await _torChannel.invokeMethod('getNativeLogs');
        if (rawNativeLogs is List && rawNativeLogs.isNotEmpty) {
          for (var nLog in rawNativeLogs) {
            AppLogger.addNativeLog(nLog.toString());
          }
          await _torChannel.invokeMethod('clearNativeLogs');
        }
      } catch (_) {}
    });

    _reportTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      if (_activeEngine == ActiveEngine.dashboard) {
        _reportDeltaUsage();
      }
    });
  }

  @override
  void dispose() {
    _stopHeartbeat();
    _logTimer?.cancel();
    _reportTimer?.cancel();
    _torProgressTimer?.cancel();
    _bannerTimer?.cancel();
    _configController.dispose();
    _customBridgeController.dispose();
    v2rayStatus.dispose();
    super.dispose();
  }

  Future<void> _resetAllEngines() async {
    _stopHeartbeat();
    _torProgressTimer?.cancel();
    try {
      await flutterV2ray.stopV2Ray();
    } catch (_) {}
    try { await _torChannel.invokeMethod('killAllCores'); } catch (_) {}
    try { await _aetherChannel.invokeMethod('stopAether'); } catch (_) {}
    await _saveEngineState(ActiveEngine.none);
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<Map<String, dynamic>?> _verifyDnsIp(String ip, {int timeoutMs = 1500}) async {
    RawDatagramSocket? socket;
    try {
      final InternetAddress targetAddress = InternetAddress(ip.trim());
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      
      final List<int> dnsQuery = [
        0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x06, 0x67, 0x6f, 0x6f,
        0x67, 0x6c, 0x65, 0x03, 0x63, 0x6f, 0x6d, 0x00,
        0x00, 0x01, 0x00, 0x01
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

              final bool isPoisoned = (o1 == 10 && o2 == 10 && o3 == 34) ||
                                     (o1 == 10) || (o1 == 127) || (o1 == 0) || 
                                     (o1 == 192 && o2 == 168) || 
                                     (o1 == 172 && o2 >= 16 && o2 <= 31) ||
                                     (o1 == 0 && o2 == 0 && o3 == 0 && o4 == 0);

              if (!isPoisoned && !completer.isCompleted) {
                AppLogger.log("DNS-PROBE", "Clean DNS: $ip (${stopwatch.elapsedMilliseconds} ms)");
                completer.complete({
                  'ip': ip,
                  'latency': stopwatch.elapsedMilliseconds,
                });
                return;
              }
            }
          }
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        }
      }, onError: (_) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      }, onDone: () {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      });

      Timer(Duration(milliseconds: timeoutMs), () {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      });

      return await completer.future;
    } catch (e) {
      return null;
    } finally {
      try { socket?.close(); } catch (_) {}
    }
  }

  Future<List<String>> _runDnsRescueScan() async {
    AppLogger.log("DNS-RESCUE", "Starting DNS rescue probe...");
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
      if (verified.length >= 4) {
        break;
      }
    }

    verified.sort((a, b) => (a['latency'] as int).compareTo(b['latency'] as int));
    if (verified.isNotEmpty) {
      final finalDns = verified.map((e) => e['ip'] as String).toList();
      AppLogger.log("DNS-RESCUE", "Rescue successful. Active DNS: $finalDns");
      return finalDns;
    }
    return ["8.8.8.8", "9.9.9.9", "1.1.1.1"];
  }

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
          if (!completer.isCompleted) {
            completer.complete(stopwatch.elapsedMilliseconds);
          }
        } else {
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        }
      }, onError: (_) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      }, onDone: () {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      });

      Timer(Duration(milliseconds: timeoutMs), () {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      });

      return await completer.future;
    } catch (_) {
      return null;
    } finally {
      try { secureSocket?.destroy(); } catch (_) {}
      try { rawSocket?.destroy(); } catch (_) {}
    }
  }

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

  Future<String> _findFastestIP(String host, String path) async {
    String bestIP = "";
    int bestLatency = 9999;
    
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
        setState(() => _bestPing = bestLatency);
      }
      return bestIP;
    }

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
    return bestIP.isNotEmpty ? bestIP : "104.20.5.5";
  }

  String _generateBridgeV2RayConfig(int socksPort, String outboundTag) {
    final List<Map<String, dynamic>> rules = [
      // ۱. مسدودسازی پروتکل QUIC جهت اجبار یوتیوب به سوئیچ به TCP
      {
        "type": "field",
        "port": "443",
        "network": "udp",
        "outboundTag": "block"
      },
      // ۲. مسدودسازی Private DNS شیائومی
      {
        "type": "field",
        "port": "853",
        "network": "tcp,udp",
        "outboundTag": "block"
      },
      // ۳. مسدودسازی IPv6
      {
        "type": "field",
        "ip": ["::/0"],
        "outboundTag": "block"
      },
      // ۴. هدایت کل ترافیک DNS به پروکسی
      {
        "type": "field",
        "port": "53",
        "network": "tcp,udp",
        "outboundTag": outboundTag
      }
    ];

    if (_bypassIran) {
      rules.addAll([
        {
          "type": "field",
          "domain": [
            "domain:ir",
            "domain:shaparak.ir",
            "domain:divar.ir",
            "domain:digikala.com",
            "domain:aparat.com",
            "domain:snapp.ir",
            "domain:tci.ir",
            "domain:mci.ir",
            "domain:irancell.ir",
            "domain:telewebion.com",
            "domain:rubika.ir",
            "domain:bale.ai",
            "domain:eitaa.com",
            "domain:splus.ir",
            "domain:igap.net"
          ],
          "outboundTag": "direct"
        },
        {
          "type": "field",
          "ip": [
            "10.0.0.0/8",
            "172.16.0.0/12",
            "192.168.0.0/16",
            "100.64.0.0/10"
          ],
          "outboundTag": "direct"
        }
      ]);
    }

    rules.add({
      "type": "field",
      "network": "tcp,udp",
      "outboundTag": outboundTag
    });

    final Map<String, dynamic> bridgeConfig = {
      "log": {"loglevel": "none"},
      "dns": {
        "servers": ["1.1.1.1", "8.8.8.8", "localhost"],
        "queryStrategy": "UseIP"
      },
      "inbounds": [
        {
          "tag": "socks-in",
          "port": 10808,
          "listen": "127.0.0.1",
          "protocol": "socks",
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls"]
          },
          "settings": {"auth": "noauth", "udp": true}
        }
      ],
      "outbounds": [
        {
          "tag": outboundTag,
          "protocol": "socks",
          "settings": {
            "servers": [
              {
                "address": "127.0.0.1",
                "port": socksPort
              }
            ]
          },
          "streamSettings": {
            "sockopt": {
              "tcpKeepAliveInterval": 15
            }
          }
        },
        {
          "tag": "direct",
          "protocol": "freedom",
          "settings": {
            "domainStrategy": "AsIs"
          }
        },
        {
          "tag": "block",
          "protocol": "blackhole"
        }
      ],
      "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": rules
      }
    };
    return jsonEncode(bridgeConfig);
  }

  Future<void> _connectPsiphon() async {
    if (_isTransitioning) return;

    setState(() {
      _isTransitioning = true;
      _publicIp = null;
      _ipCountry = null;
      _ipFlagEmoji = null;
      _realPingMs = null;
    });

    _showSnackBar("در حال اتصال به شبکه سایفون ($_selectedPsiphonCountry)...");
    await _resetAllEngines();

    try {
      if (_isPsiphonHybrid) {
        _showSnackBar("راه‌اندازی پل اَتر مسک برای سایفون...");
        final dynamic aetherRes = await _aetherChannel.invokeMethod('startSmartAether', {'port': 1819});
        if (aetherRes == null) {
          throw Exception("پل اَتر پاسخگو نبود.");
        }
      }

      final bool started = await _torChannel.invokeMethod('startPsiphon', {
        'port': 9081,
        'isHybrid': _isPsiphonHybrid,
        'region': _selectedPsiphonCountry,
      }) ?? false;

      if (!started) {
        throw Exception("عدم امکان استارت پروسس سایفون");
      }

      bool socksReady = false;
      for (int i = 1; i <= 90; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        socksReady = await _torChannel.invokeMethod('checkPsiphonReady', {
          'port': 9081,
          'timeoutMs': 800,
        }) ?? false;
        if (socksReady) break;
      }

      if (!socksReady) {
        throw Exception("تایم‌اوت ساکس سایفون (پورت ۹۰۸۱)");
      }

      if (await flutterV2ray.requestPermission()) {
        final String psiphonConfig = _generateBridgeV2RayConfig(9081, "psiphon-proxy");
        
        flutterV2ray.startV2Ray(
          remark: "Psiphon (${_selectedPsiphonCountry.toUpperCase()})",
          config: psiphonConfig,
          blockedApps: [appPackageName],
          proxyOnly: false,
          notificationDisconnectButtonName: "DISCONNECT",
        );

        await _saveEngineState(ActiveEngine.psiphon);
        _startHeartbeat();

        if (mounted) {
          setState(() {
            _activeEngine = ActiveEngine.psiphon;
            _isTransitioning = false;
          });
        }
        _showSnackBar("شبکه سایفون فعال شد (تونل کل دستگاه)");
      } else {
        await _resetAllEngines();
        if (mounted) setState(() => _activeEngine = ActiveEngine.none);
        _showSnackBar(_t("os_perm_err"));
      }
    } catch (e) {
      await _resetAllEngines();
      if (mounted) setState(() => _activeEngine = ActiveEngine.none);
      _showSnackBar("خطا در سایفون: ${e.toString().replaceAll("Exception: ", "")}");
    } finally {
      if (mounted) setState(() => _isTransitioning = false);
    }
  }

  Future<void> _connectTor() async {
    if (_isTransitioning) return;

    setState(() {
      _isTransitioning = true;
      _torBootstrapProgress = 0;
      _torCurrentStep = 0;
      _torStepStatus = _t("tor_step_cleanup");
      _publicIp = null;
      _ipCountry = null;
      _ipFlagEmoji = null;
      _realPingMs = null;
    });

    await _resetAllEngines();

    try {
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
        for (int i = 0; i < 70; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          aetherReady = await _aetherChannel.invokeMethod('checkSocksReady', {
            'port': 1819,
            'timeoutMs': 700,
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
          await Future.delayed(const Duration(milliseconds: 500));
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

      _torProgressTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) async {
        try {
          final dynamic status = await _torChannel.invokeMethod('getTorStatus');
          if (status is Map) {
            final int percent = status['percent'] ?? 0;
            if (mounted) {
              if (percent > _torBootstrapProgress) {
                setState(() {
                  _torBootstrapProgress = percent;
                  if (percent > 0) {
                    _torStepStatus = "${_t("tor_building_circuits")} $percent%";
                  }
                });
              }
              if (percent >= 100) {
                torReached100 = true;
              }
            }
          }
        } catch (_) {}
      });

      for (int i = 0; i < 180; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final bool socksReady = await _torChannel.invokeMethod('checkTorReady', {
          'socksPort': 9050,
          'timeoutMs': 800,
        }) ?? false;

        if (socksReady && (torReached100 || _torBootstrapProgress >= 100)) {
          if (mounted) {
            setState(() => _torBootstrapProgress = 100);
          }
          break;
        }
      }

      _torProgressTimer?.cancel();
      await Future.delayed(const Duration(milliseconds: 400));

      if (mounted) {
        setState(() {
          _torCurrentStep = 3;
          _torStepStatus = _t("tor_step_vpn_start");
        });
      }

      if (await flutterV2ray.requestPermission()) {
        final String torConfig = _generateBridgeV2RayConfig(9050, "tor-proxy");
        
        flutterV2ray.startV2Ray(
          remark: "Tor (${_selectedTorMode.toUpperCase()})",
          config: torConfig,
          blockedApps: [appPackageName],
          proxyOnly: false,
          notificationDisconnectButtonName: "DISCONNECT",
        );

        await _saveEngineState(ActiveEngine.tor);
        _startHeartbeat();

        if (mounted) {
          setState(() {
            _activeEngine = ActiveEngine.tor;
            _isTransitioning = false;
            _torStepStatus = _t("tor_connected_banner");
          });
        }
        _showSnackBar(_t("tor_connected_banner"));
      } else {
        await _resetAllEngines();
        if (mounted) {
          setState(() => _activeEngine = ActiveEngine.none);
        }
        _showSnackBar(_t("os_perm_err"));
      }
    } catch (e) {
      await _resetAllEngines();
      if (mounted) {
        setState(() => _activeEngine = ActiveEngine.none);
      }
      _showSnackBar(e.toString().replaceAll("Exception: ", ""));
    } finally {
      _torProgressTimer?.cancel();
      if (mounted) {
        setState(() => _isTransitioning = false);
      }
    }
  }

  Future<void> _connectAether() async {
    if (_isTransitioning) return;

    setState(() {
      _isTransitioning = true;
      _publicIp = null;
      _ipCountry = null;
      _ipFlagEmoji = null;
      _realPingMs = null;
    });

    _showSnackBar(_t("aether_launching"));
    await _resetAllEngines();

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
      for (int i = 0; i < 70; i++) {
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
        final String aetherConfig = _generateBridgeV2RayConfig(1819, "aether-proxy");
        
        flutterV2ray.startV2Ray(
          remark: "Aether (${_selectedAetherMode.toUpperCase()})",
          config: aetherConfig,
          blockedApps: [appPackageName],
          proxyOnly: false,
          notificationDisconnectButtonName: "DISCONNECT",
        );

        await _saveEngineState(ActiveEngine.aether);
        _startHeartbeat();

        if (mounted) {
          setState(() {
            _activeEngine = ActiveEngine.aether;
            _isTransitioning = false;
          });
        }
        _showSnackBar(_t("aether_connected_banner"));
      } else {
        await _resetAllEngines();
        if (mounted) {
          setState(() => _activeEngine = ActiveEngine.none);
        }
        _showSnackBar(_t("os_perm_err"));
      }
    } catch (e) {
      await _resetAllEngines();
      if (mounted) {
        setState(() => _activeEngine = ActiveEngine.none);
      }
      _showSnackBar(_t("aether_start_err"));
    } finally {
      if (mounted) {
        setState(() => _isTransitioning = false);
      }
    }
  }

  void _connectDashboard() async {
    if (_isTransitioning) return;

    setState(() {
      _isTransitioning = true;
      _isScanningIPs = true;
      _publicIp = null;
      _ipCountry = null;
      _ipFlagEmoji = null;
      _realPingMs = null;
    });

    await _resetAllEngines();

    if (_fetchedAccounts.isEmpty && !_serversUpdatingMode) {
      await _fetchAndLoadAccounts();
    }
    
    if (_serversUpdatingMode || _fetchedAccounts.isEmpty) {
      setState(() {
        _isTransitioning = false;
        _isScanningIPs = false;
      });
      _showSnackBar(_t("acc_sync_err"));
      return;
    }

    _showSnackBar(_t("connecting_msg"));

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

    // در حالت هیبریدی نیازی به اسکن آی‌پی در ایران و خواندن فایل بزرگ نیست؛ مستقیماً اَتر متصل می‌شود
    final String fastest;
    if (_isHybridMode) {
      fastest = "104.18.0.14";
      if (mounted) setState(() => _isScanningIPs = false);
    } else {
      fastest = await _findFastestIP(activeWorker, activePath);
      if (mounted) {
        setState(() {
          _fastestIP = fastest;
          _isScanningIPs = false;
        });
      }
    }

    // در صورت فعال بودن تیک هیبریدی، ابتدا اَتر به شکل هوشمند روی بهترین پروتکل راه‌اندازی می‌شود
    if (_isHybridMode) {
      _showSnackBar(_t("hybrid_starting"));
      AppLogger.log("HYBRID", "شروع پویش هوشمند اَتر برای اتصال هیبریدی...");
      try {
        final dynamic result = await _aetherChannel.invokeMethod('startSmartAether', {
          'port': 1819,
        });
        if (result is Map) {
          final mode = result['mode']?.toString() ?? 'unknown';
          final noize = result['noize']?.toString() ?? 'default';
          _hybridStatusText = "$mode ($noize)";
          AppLogger.log("HYBRID", "موتور اَتر با موفقیت روی $mode و نویز $noize فعال شد.");
        }
      } catch (e) {
        AppLogger.log("HYBRID-ERR", "خطا در استارت هوشمند اَتر: $e");
        await _resetAllEngines();
        setState(() {
          _isTransitioning = false;
          _isScanningIPs = false;
        });
        _showSnackBar(_t("hybrid_failed"));
        return;
      }
    }

    if (_selectedAccountIndex >= 0 && _selectedAccountIndex < _fetchedAccounts.length) {
      final account = _fetchedAccounts[_selectedAccountIndex];
      final String worker = account['worker'] ?? '';
      final String uuid = account['uuid'] ?? '';
      final String path = account['path'] ?? '';
      
      final String targetHost = _isHybridMode ? worker : fastest;
      final String finalLink = "vless://$uuid@$targetHost:443?encryption=none&security=tls&sni=$worker&fp=chrome&alpn=http%2F1.1&type=ws&host=$worker&path=${Uri.encodeComponent(path)}#RedCloud_Fastest";
      _parseAndSaveConfig(finalLink, updateUI: false);
    }

    if (_fullConfigJson.isEmpty) {
      AppLogger.log("V2RAY", "کانفیگ برای استارت معتبر نیست.", isError: true);
      _showSnackBar(_t("config_err"));
      setState(() {
        _isTransitioning = false;
      });
      return;
    }

    if (await flutterV2ray.requestPermission()) {
      _showSnackBar("Connecting to: $fastest");
      _lastSentDownload = 0;
      _lastSentUpload = 0;

      flutterV2ray.startV2Ray(
        remark: _remark,
        config: _fullConfigJson,
        blockedApps: [appPackageName],
        proxyOnly: false,
        notificationDisconnectButtonName: "DISCONNECT",
      );

      await _saveEngineState(ActiveEngine.dashboard);
      _startHeartbeat();

      if (mounted) {
        setState(() {
          _activeEngine = ActiveEngine.dashboard;
          _isTransitioning = false;
        });
      }
    } else {
      await _resetAllEngines();
      setState(() {
        _activeEngine = ActiveEngine.none;
        _isTransitioning = false;
      });
      _showSnackBar(_t("os_perm_err"));
    }
  }

  void _disconnectCurrent() async {
    setState(() {
      _isTransitioning = true;
    });

    _stopHeartbeat();
    final int currentDownload = v2rayStatus.value.download;
    final int currentUpload = v2rayStatus.value.upload;

    await _resetAllEngines();

    if (_activeEngine == ActiveEngine.dashboard) {
      await _reportDeltaUsage(forceDownload: currentDownload, forceUpload: currentUpload);
    }

    if (mounted) {
      setState(() {
        _activeEngine = ActiveEngine.none;
        _isTransitioning = false;
        _torBootstrapProgress = 0;
        _torStepStatus = _t("disconnected");
        _publicIp = null;
        _ipCountry = null;
        _ipFlagEmoji = null;
        _realPingMs = null;
        _isTestingIp = false;
      });
    }
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
        configText = v2rayURL.getFullConfiguration();
        _remark = v2rayURL.remark;
        if (updateUI && mounted) {
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
      
      // پورت لوکال ساکس ۵ با UDP فعال
      configMap['inbounds'] = [
        {
          "tag": "socks-in",
          "port": 10808,
          "listen": "127.0.0.1",
          "protocol": "socks",
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls", "quic"]
          },
          "settings": {
            "auth": "noauth",
            "udp": true
          }
        }
      ];

      configMap['dns'] = {
        "servers": [
          "1.1.1.1",
          "8.8.8.8"
        ],
        "queryStrategy": "UseIPv4"
      };

      final List<Map<String, dynamic>> routingRules = [
        // ۱. ممانعت قطعی از لوپ شدن باینری اَتر
        {
          "type": "field",
          "ip": ["127.0.0.1/32", "188.114.96.0/20", "162.159.0.0/16"],
          "outboundTag": "direct"
        },
        // ۲. مسدودسازی هوشمند پروتکل QUIC (UDP 443) تا یوتیوب فوراً به TCP سوئیچ کند و ویدیوها لود شوند
        {
          "type": "field",
          "port": "443",
          "network": "udp",
          "outboundTag": "block"
        },
        // ۳. بستن Private DNS شیائومی (پورت 853)
        {
          "type": "field",
          "port": "853",
          "network": "tcp,udp",
          "outboundTag": "block"
        },
        // ۴. مسدودسازی نشت IPv6 که در ایران فیلتر است
        {
          "type": "field",
          "ip": ["::/0"],
          "outboundTag": "block"
        },
        // ۵. هدایت تمام درخواست‌های DNS (پورت 53) به داخل بستر اَتر در آلمان
        {
          "type": "field",
          "port": "53",
          "network": "tcp,udp",
          "outboundTag": _isHybridMode ? "aether-underlay" : "proxy"
        }
      ];

      if (_bypassIran) {
        routingRules.add({
          "type": "field",
          "domain": [
            "domain:ir",
            "domain:shaparak.ir",
            "domain:divar.ir",
            "domain:digikala.com",
            "domain:aparat.com",
            "domain:snapp.ir",
            "domain:tci.ir",
            "domain:mci.ir",
            "domain:irancell.ir",
            "domain:telewebion.com",
            "domain:rubika.ir",
            "domain:bale.ai",
            "domain:eitaa.com",
            "domain:splus.ir",
            "domain:igap.net"
          ],
          "outboundTag": "direct"
        });
        routingRules.add({
          "type": "field",
          "ip": [
            "10.0.0.0/8",
            "172.16.0.0/12",
            "192.168.0.0/16",
            "100.64.0.0/10"
          ],
          "outboundTag": "direct"
        });
      }

      // ۶. قانون نهایی (Catch-All): هدایت تضمینی تمام ترافیک‌های بازمانده وب به پروکسی
      routingRules.add({
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "proxy"
      });

      configMap['routing'] = {
        "domainStrategy": "IPIfNonMatch",
        "rules": routingRules
      };

      final List<dynamic> outbounds = (configMap['outbounds'] as List?) ?? [];

      for (var outbound in outbounds) {
        if (outbound is Map) {
          final stream = Map<String, dynamic>.from((outbound['streamSettings'] as Map?) ?? {});
          final sock = Map<String, dynamic>.from((stream['sockopt'] as Map?) ?? {});
          sock['tcpKeepAliveInterval'] = 15;

          if (_isHybridMode) {
            final tag = outbound['tag']?.toString().toLowerCase() ?? '';
            final proto = outbound['protocol']?.toString().toLowerCase() ?? '';
            if (tag == 'proxy' || proto == 'vless' || proto == 'vmess' || proto == 'trojan') {
              sock['dialerProxy'] = 'aether-underlay';
            }
          }

          stream['sockopt'] = sock;
          outbound['streamSettings'] = stream;
        }
      }

      // اطمینان از وجود اوت‌باندهای direct و block
      bool hasDirect = outbounds.any((o) => o is Map && o['tag'] == 'direct');
      bool hasBlock = outbounds.any((o) => o is Map && o['tag'] == 'block');
      bool hasDnsOut = outbounds.any((o) => o is Map && o['tag'] == 'dns-out');
      if (!hasDirect) outbounds.add({"tag": "direct", "protocol": "freedom"});
      if (!hasBlock) outbounds.add({"tag": "block", "protocol": "blackhole"});
      if (!hasDnsOut) outbounds.add({"tag": "dns-out", "protocol": "dns"});

      if (_isHybridMode) {
        outbounds.add({
          "tag": "aether-underlay",
          "protocol": "socks",
          "settings": {
            "servers": [
              {
                "address": "127.0.0.1",
                "port": 1819
              }
            ]
          },
          "streamSettings": {
            "sockopt": {
              "tcpKeepAliveInterval": 15
            }
          }
        });
      }

      configMap['outbounds'] = outbounds;
      _fullConfigJson = jsonEncode(configMap);
      AppLogger.log("CONFIG", "کانفیگ V2Ray با موفقیت ساخته شد (${_fullConfigJson.length} کاراکتر)");
    } catch (e) {
      AppLogger.log("CONFIG-ERR", "خطا در پردازش کانفیگ: $e", isError: true);
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

  Future<void> _fetchAndLoadAccounts({bool showMessage = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoadingAccounts = true;
      _serversUpdatingMode = false;
    });

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
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

        if (mounted) {
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
        }
        if (showMessage) _showSnackBar(_t("acc_sync_ok"));
      } else {
        if (showMessage) _showSnackBar(_t("acc_sync_err"));
      }
    } catch (_) {
      if (showMessage) _showSnackBar(_t("acc_sync_err"));
    } finally {
      client.close();
      if (mounted) setState(() => _isLoadingAccounts = false);
    }
  }

  void _updateSelectedConfig() {
    if (_selectedAccountIndex < 0 || _selectedAccountIndex >= _fetchedAccounts.length) return;
    final account = _fetchedAccounts[_selectedAccountIndex];
    final String worker = account['worker'] ?? '';
    final String uuid = account['uuid'] ?? '';
    final String path = account['path'] ?? '';
    
    final String targetHost = _isHybridMode ? worker : _fastestIP;
    final String vlessLink = "vless://$uuid@$targetHost:443?encryption=none&security=tls&sni=$worker&fp=chrome&alpn=http%2F1.1&type=ws&host=$worker&path=${Uri.encodeComponent(path)}#$_serverName";
    _parseAndSaveConfig(vlessLink, updateUI: false);
    
    if (mounted) {
      setState(() {
        _serverName = "${_t("tab_dashboard")} ${_selectedAccountIndex + 1}";
        _protocolType = "VLESS";
      });
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

    final activeAccount = _fetchedAccounts[_selectedAccountIndex];
    final String activeWorker = activeAccount['worker'] ?? '';
    if (activeWorker.isEmpty) return;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(Uri.parse('$workerApiUrl/api/report'));
      request.headers.set('content-type', 'application/json');
      request.add(utf8.encode(jsonEncode({"worker": activeWorker, "bytes_used": totalDeltaBytes})));
      final response = await request.close();
      if (response.statusCode == 200) {
        _lastSentDownload = currentDownload;
        _lastSentUpload = currentUpload;
      }
    } catch (_) {}
    finally {
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
      _disconnectCurrent();
      await _fetchAndLoadAccounts();
      if (_fetchedAccounts.isNotEmpty && !_serversUpdatingMode) {
        if (!mounted) return;
        setState(() {
          _selectedAccountIndex = 0;
          _updateSelectedConfig();
        });
        _connectDashboard();
      }
    }
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
    } catch (_) {}
  }

  Future<void> _saveExhaustedWorkers() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String todayDate = DateTime.now().toIso8601String().substring(0, 10);
      await prefs.setString('exhausted_workers_data', jsonEncode({
        'date': todayDate,
        'workers': _locallyExhaustedWorkers.toList(),
      }));
    } catch (_) {}
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
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            side: BorderSide(color: Color(0xFF3B82F6), width: 1.2),
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

  Widget _buildConnectionTelemetryCard(bool isConnected) {
    if (!isConnected) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF101726),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00F2FE).withOpacity(0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00F2FE).withOpacity(0.08),
            blurRadius: 15,
            spreadRadius: 2,
          )
        ],
      ),
      child: _isTestingIp
          ? const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00F2FE)),
                ),
                SizedBox(width: 12),
                Text(
                  "در حال شناسایی مشخصات سرور خروجی...",
                  style: TextStyle(fontSize: 12, color: Color(0xFF00F2FE), fontWeight: FontWeight.bold),
                ),
              ],
            )
          : Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF182338),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _ipFlagEmoji ?? "🌐",
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: SelectableText(
                                _publicIp ?? "...",
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () {
                              if (_publicIp != null) {
                                Clipboard.setData(ClipboardData(text: _publicIp!));
                                _showSnackBar(_t("copied_msg"));
                              }
                            },
                            child: const Icon(Icons.copy_rounded, size: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _ipCountry ?? "Connected via RedCloud",
                        style: const TextStyle(fontSize: 11, color: Colors.white60),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (_realPingMs != null)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFF10B981)),
                        const SizedBox(width: 2),
                        Text(
                          "$_realPingMs ms",
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                        ),
                      ],
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 18, color: Color(0xFF00F2FE)),
                  tooltip: "Re-test",
                  onPressed: _fetchPublicIpAndPing,
                ),
              ],
            ),
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
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 14.0),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F2FE).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF00F2FE).withOpacity(0.45),
                      width: 1.1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00F2FE).withOpacity(0.15),
                        blurRadius: 10,
                      )
                    ],
                  ),
                  child: const Text(
                    "v1.2.4",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00F2FE),
                      fontFamily: 'monospace',
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_bannerMessage != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _bannerColor.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _bannerColor, width: 1.2),
                ),
                child: Row(
                  children: [
                    Icon(_bannerIcon, color: _bannerColor, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _bannerMessage!,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _bannerColor),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(child: _buildCurrentTabContent()),
          ],
        ),
        bottomNavigationBar: _buildModernFloatingNavBar(),
      ),
    );
  }

  Widget _buildModernFloatingNavBar() {
    final List<Map<String, dynamic>> tabs = [
      {
        "index": 0,
        "title": widget.currentLang == "fa" ? "داشبورد" : "Dashboard",
        "icon": Icons.dashboard_rounded,
        "color": const Color(0xFF00F2FE),
      },
      {
        "index": 1,
        "title": widget.currentLang == "fa" ? "اَتر" : "Aether",
        "icon": Icons.bolt_rounded,
        "color": const Color(0xFF06B6D4),
      },
      {
        "index": 2,
        "title": widget.currentLang == "fa" ? "تور" : "Tor",
        "icon": Icons.security_rounded,
        "color": const Color(0xFFC084FC),
      },
      {
        "index": 3,
        "title": widget.currentLang == "fa" ? "سایفون" : "Psiphon",
        "icon": Icons.hub_rounded,
        "color": const Color(0xFF10B981),
      },
      {
        "index": 4,
        "title": widget.currentLang == "fa" ? "تنظیمات" : "Settings",
        "icon": Icons.tune_rounded,
        "color": const Color(0xFF38BDF8),
      },
    ];

    final activeTab = tabs.firstWhere(
      (t) => t['index'] == _currentTabIndex,
      orElse: () => tabs[0],
    );
    final Color activeColor = activeTab['color'] as Color;

    return SafeArea(
      top: false,
      bottom: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: widget.isDarkMode ? const Color(0xFF0C1322) : const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: activeColor.withOpacity(0.38),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: activeColor.withOpacity(0.15),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: tabs.map((tab) {
            final int index = tab['index'] as int;
            final bool isSelected = _currentTabIndex == index;
            final Color itemColor = tab['color'] as Color;

            return Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _currentTabIndex = index);
                },
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(
                    vertical: isSelected ? 8 : 10,
                    horizontal: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? itemColor.withOpacity(0.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? itemColor.withOpacity(0.45) : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tab['icon'] as IconData,
                        size: isSelected ? 22 : 20,
                        color: isSelected ? itemColor : Colors.grey.shade500,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        tab['title'] as String,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? itemColor : Colors.grey.shade500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCurrentTabContent() {
    switch (_currentTabIndex) {
      case 0: return _buildDashboardTab();
      case 1: return _buildAetherTab();
      case 2: return _buildTorTab();
      case 3: return _buildPsiphonTab();
      case 4: return _buildSettingsTab();
      case 5: return _buildPrivacyTab();
      case 6: return _buildContactTab();
      default: return _buildDashboardTab();
    }
  }

  Widget _buildDashboardTab() {
    return ValueListenableBuilder<V2RayStatus>(
      valueListenable: v2rayStatus,
      builder: (context, value, child) {
        final isConnected = _activeEngine == ActiveEngine.dashboard && value.state == "CONNECTED";
        final isConnecting = (_activeEngine == ActiveEngine.dashboard && value.state == "CONNECTING") || 
                             _isScanningIPs || 
                             (_isTransitioning && _activeEngine == ActiveEngine.dashboard);

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // نوار بالایی: کلیدهای کپسولی کامپکت و ریسپانسیو
              Row(
                children: [
                  // کلید هیبریدی (نئون فیروزه‌ای)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _isHybridMode ? const Color(0xFF00F2FE).withOpacity(0.12) : const Color(0xFF101726),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: _isHybridMode ? const Color(0xFF00F2FE) : Colors.white12,
                          width: 1.2,
                        ),
                        boxShadow: [
                          if (_isHybridMode)
                            BoxShadow(
                              color: const Color(0xFF00F2FE).withOpacity(0.2),
                              blurRadius: 10,
                              spreadRadius: 1,
                            )
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.hub_rounded,
                                size: 15,
                                color: _isHybridMode ? const Color(0xFF00F2FE) : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "Hybrid",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _isHybridMode ? const Color(0xFF00F2FE) : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          Transform.scale(
                            scale: 0.72,
                            child: Switch(
                              value: _isHybridMode,
                              activeColor: const Color(0xFF00F2FE),
                              activeTrackColor: const Color(0xFF00F2FE).withOpacity(0.3),
                              inactiveThumbColor: Colors.grey,
                              inactiveTrackColor: Colors.white10,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              onChanged: (isConnected || isConnecting)
                                  ? null
                                  : (val) => _setHybridModeSetting(val),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // کلید دور زدن ایران (سبز زمردی)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _bypassIran ? const Color(0xFF10B981).withOpacity(0.12) : const Color(0xFF101726),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: _bypassIran ? const Color(0xFF10B981) : Colors.white12,
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.shield_rounded,
                                size: 15,
                                color: _bypassIran ? const Color(0xFF10B981) : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "Bypass IR",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _bypassIran ? const Color(0xFF10B981) : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          Transform.scale(
                            scale: 0.72,
                            child: Switch(
                              value: _bypassIran,
                              activeColor: const Color(0xFF10B981),
                              activeTrackColor: const Color(0xFF10B981).withOpacity(0.3),
                              inactiveThumbColor: Colors.grey,
                              inactiveTrackColor: Colors.white10,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              onChanged: (isConnected || isConnecting)
                                  ? null
                                  : (val) => _setBypassIranSetting(val),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // انتخاب‌گر اکانت‌های هوشمند
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF101726),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.dns_rounded, size: 16, color: Color(0xFF00F2FE)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _isLoadingAccounts
                          ? const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00F2FE)),
                              ),
                            )
                          : SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: List.generate(_fetchedAccounts.length, (index) {
                                  final isSelected = _selectedAccountIndex == index;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6.0),
                                    child: ChoiceChip(
                                      label: Text("Server ${index + 1}"),
                                      labelStyle: TextStyle(
                                        fontSize: 11,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        color: isSelected ? Colors.black : Colors.white70,
                                      ),
                                      selected: isSelected,
                                      selectedColor: const Color(0xFF00F2FE),
                                      backgroundColor: const Color(0xFF182338),
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
                      icon: const Icon(Icons.add_link_rounded, color: Color(0xFF00F2FE), size: 18),
                      tooltip: "ورود دستی کانفیگ",
                      onPressed: _openConfigBottomSheet,
                    ),
                    IconButton(
                      icon: const Icon(Icons.sync_rounded, color: Color(0xFF00F2FE), size: 18),
                      tooltip: "Sync Accounts",
                      onPressed: () => _fetchAndLoadAccounts(showMessage: true),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 26),

              // دکمه بزرگ مرکزی با رینگ‌های نئونی تابان (مشابه دکمه مرکزی دسکتاپ)
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: isConnected ? _disconnectCurrent : _connectDashboard,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        width: 175,
                        height: 175,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF0E1422),
                          border: Border.all(
                            color: isConnected
                                ? const Color(0xFF00F2FE)
                                : isConnecting
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFF1E293B),
                            width: 4.5,
                          ),
                          boxShadow: [
                            if (isConnected) ...[
                              BoxShadow(
                                color: const Color(0xFF00F2FE).withOpacity(0.4),
                                blurRadius: 35,
                                spreadRadius: 6,
                              ),
                              BoxShadow(
                                color: const Color(0xFF00F2FE).withOpacity(0.15),
                                blurRadius: 60,
                                spreadRadius: 15,
                              ),
                            ],
                            if (isConnecting)
                              BoxShadow(
                                color: const Color(0xFFF59E0B).withOpacity(0.4),
                                blurRadius: 30,
                                spreadRadius: 5,
                              ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isConnecting)
                              const SizedBox(
                                width: 50,
                                height: 50,
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                                  strokeWidth: 4,
                                ),
                              )
                            else
                              Icon(
                                Icons.power_settings_new_rounded,
                                size: 68,
                                color: isConnected
                                    ? const Color(0xFF00F2FE)
                                    : const Color(0xFF475569),
                              ),
                            const SizedBox(height: 8),
                            Text(
                              isConnected
                                  ? _t("connected")
                                  : isConnecting
                                      ? _t("connecting")
                                      : _t("disconnected"),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                                color: isConnected
                                    ? const Color(0xFF00F2FE)
                                    : isConnecting
                                        ? const Color(0xFFF59E0B)
                                        : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isHybridMode ? "Tap to connect (Hybrid)" : "Tap to connect (Direct)",
                      style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // کارت تلمتری آی‌پی
              _buildConnectionTelemetryCard(isConnected),

              const SizedBox(height: 4),

              // باکس‌های سرعت دانلود و آپلود (مشابه تصویر)
              _buildStatsGrid(isConnected, value),

              const SizedBox(height: 14),

              // نوار تحتانی Live Defense و نشانگر لایه اَتر
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF101726),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.radar_rounded, size: 16, color: Color(0xFF00F2FE)),
                        const SizedBox(width: 8),
                        Text(
                          _isHybridMode ? "Live Defense & Chained Radar" : "Standard V2Ray Protection",
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white70),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                      ),
                      child: Text(
                        _isHybridMode && _hybridStatusText.isNotEmpty ? "Aether: $_hybridStatusText" : (_isHybridMode ? "Aether: Active" : "Direct: Active"),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
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
        final isConnected = _activeEngine == ActiveEngine.aether && value.state == "CONNECTED";
        final isConnecting = (_activeEngine == ActiveEngine.aether && value.state == "CONNECTING") ||
                             (_isTransitioning && _activeEngine == ActiveEngine.none);

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // کارت فوق‌پیشرفته استخر کلیدهای ضدسانسور ATC
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF101726),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF06B6D4).withOpacity(0.35),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF06B6D4).withOpacity(0.08),
                      blurRadius: 15,
                    )
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF06B6D4).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.vpn_key_rounded, size: 20, color: Color(0xFF06B6D4)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                "استخر کلید (ATC): ",
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF06B6D4).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF06B6D4).withOpacity(0.4)),
                                ),
                                child: Text(
                                  _atcAccountName.isNotEmpty && _atcAccountName != "نامشخص" ? _atcAccountName : "آماده بارگذاری",
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF06B6D4)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            "انقضا و چرخش خودکار: $_atcRemainingDays روز باقی‌مانده",
                            style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.autorenew_rounded, size: 20, color: Color(0xFF06B6D4)),
                      tooltip: "تعویض تصادفی اکانت",
                      onPressed: (isConnected || isConnecting)
                          ? null
                          : () async {
                              await _aetherChannel.invokeMethod('resetIdentity');
                              await _fetchAtcInfo();
                              _showSnackBar("اکانت هویت بازنشانی شد؛ در اتصال بعدی کلید تصادفی جدیدی انتخاب می‌شود.");
                            },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // دکمه بزرگ مرکزی با رینگ‌های نئونی آبی اَتر (مشابه داشبورد)
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: isConnecting
                          ? null
                          : isConnected
                              ? _disconnectCurrent
                              : _connectAether,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        width: 175,
                        height: 175,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF0E1422),
                          border: Border.all(
                            color: isConnected
                                ? const Color(0xFF06B6D4)
                                : isConnecting
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFF1E293B),
                            width: 4.5,
                          ),
                          boxShadow: [
                            if (isConnected) ...[
                              BoxShadow(
                                color: const Color(0xFF06B6D4).withOpacity(0.45),
                                blurRadius: 35,
                                spreadRadius: 6,
                              ),
                              BoxShadow(
                                color: const Color(0xFF06B6D4).withOpacity(0.18),
                                blurRadius: 60,
                                spreadRadius: 15,
                              ),
                            ],
                            if (isConnecting)
                              BoxShadow(
                                color: const Color(0xFFF59E0B).withOpacity(0.4),
                                blurRadius: 30,
                                spreadRadius: 5,
                              ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isConnecting)
                              const SizedBox(
                                width: 50,
                                height: 50,
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                                  strokeWidth: 4,
                                ),
                              )
                            else
                              Icon(
                                Icons.bolt_rounded,
                                size: 68,
                                color: isConnected
                                    ? const Color(0xFF06B6D4)
                                    : const Color(0xFF475569),
                              ),
                            const SizedBox(height: 8),
                            Text(
                              isConnected
                                  ? _t("connected")
                                  : isConnecting
                                      ? _t("connecting")
                                      : _t("disconnected"),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                                color: isConnected
                                    ? const Color(0xFF06B6D4)
                                    : isConnecting
                                        ? const Color(0xFFF59E0B)
                                        : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isConnected ? "Connected to Aether WARP Tunnel" : "Tap to connect (Aether Engine)",
                      style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // کارت مشخصات آی‌پی سرور
              _buildConnectionTelemetryCard(isConnected),

              const SizedBox(height: 4),

              // کارت‌های سرعت دانلود و آپلود
              _buildStatsGrid(isConnected, value),

              const SizedBox(height: 20),

              // عنوان انتخاب پروتکل‌ها
              Row(
                children: [
                  const Icon(Icons.tune_rounded, size: 16, color: Color(0xFF06B6D4)),
                  const SizedBox(width: 8),
                  Text(
                    _t("aether_mode_select"),
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              _buildAetherModeOption(
                modeKey: "auto",
                title: _t("mode_auto_title"),
                desc: _t("mode_auto_desc"),
                badge: "SMART",
                icon: Icons.auto_awesome_rounded,
                color: const Color(0xFF00F2FE),
                disabled: isConnected || isConnecting,
              ),
              _buildAetherModeOption(
                modeKey: "masque_h2",
                title: _t("mode_masque_h2_title"),
                desc: _t("mode_masque_h2_desc"),
                badge: "FRAGMENT",
                icon: Icons.shield_rounded,
                color: const Color(0xFF06B6D4),
                disabled: isConnected || isConnecting,
              ),
              _buildAetherModeOption(
                modeKey: "masque",
                title: _t("mode_masque_title"),
                desc: _t("mode_masque_desc"),
                badge: "HTTP/3",
                icon: Icons.flash_on_rounded,
                color: const Color(0xFFF59E0B),
                disabled: isConnected || isConnecting,
              ),
              _buildAetherModeOption(
                modeKey: "gool",
                title: _t("mode_gool_title"),
                desc: _t("mode_gool_desc"),
                badge: "DUAL WARP",
                icon: Icons.layers_rounded,
                color: const Color(0xFFA855F7),
                disabled: isConnected || isConnecting,
              ),
              _buildAetherModeOption(
                modeKey: "wireguard",
                title: _t("mode_wireguard_title"),
                desc: _t("mode_wireguard_desc"),
                badge: "NATIVE",
                icon: Icons.vpn_lock_rounded,
                color: const Color(0xFF10B981),
                disabled: isConnected || isConnecting,
              ),

              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPsiphonTab() {
    return ValueListenableBuilder<V2RayStatus>(
      valueListenable: v2rayStatus,
      builder: (context, value, child) {
        final isConnected = _activeEngine == ActiveEngine.psiphon && value.state == "CONNECTED";
        final isConnecting = (_activeEngine == ActiveEngine.psiphon && value.state == "CONNECTING") ||
                             (_isTransitioning && _activeEngine == ActiveEngine.none);

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // کلید بالای صفحه: Psiphon over MASQUE Bridge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _isPsiphonHybrid ? const Color(0xFF10B981).withOpacity(0.12) : const Color(0xFF101726),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: _isPsiphonHybrid ? const Color(0xFF10B981) : Colors.white12,
                    width: 1.3,
                  ),
                  boxShadow: [
                    if (_isPsiphonHybrid)
                      BoxShadow(
                        color: const Color(0xFF10B981).withOpacity(0.2),
                        blurRadius: 10,
                        spreadRadius: 1,
                      )
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.hub_rounded,
                          size: 16,
                          color: _isPsiphonHybrid ? const Color(0xFF10B981) : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Psiphon over MASQUE Bridge",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _isPsiphonHybrid ? const Color(0xFF10B981) : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    Transform.scale(
                      scale: 0.75,
                      child: Switch(
                        value: _isPsiphonHybrid,
                        activeColor: const Color(0xFF10B981),
                        activeTrackColor: const Color(0xFF10B981).withOpacity(0.3),
                        inactiveThumbColor: Colors.grey,
                        inactiveTrackColor: Colors.white10,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (isConnected || isConnecting)
                            ? null
                            : (val) => setState(() => _isPsiphonHybrid = val),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // باکس انتخاب کشور خروجی (Exit Node Country)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF101726),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.public_rounded, size: 20, color: Color(0xFF10B981)),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        "Exit Node Country:",
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                    ),
                    DropdownButton<String>(
                      value: _selectedPsiphonCountry,
                      dropdownColor: const Color(0xFF101726),
                      underline: const SizedBox.shrink(),
                      icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF10B981)),
                      style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13),
                      onChanged: (isConnected || isConnecting)
                          ? null
                          : (val) {
                              if (val != null) setState(() => _selectedPsiphonCountry = val);
                            },
                      items: _psiphonCountries.map((c) {
                        return DropdownMenuItem<String>(
                          value: c['code'],
                          child: Text(c['name']!),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // دکمه بزرگ مرکزی با رینگ سبز زمردی درخشان
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: isConnecting
                          ? null
                          : isConnected
                              ? _disconnectCurrent
                              : _connectPsiphon,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        width: 175,
                        height: 175,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF0E1422),
                          border: Border.all(
                            color: isConnected
                                ? const Color(0xFF10B981)
                                : isConnecting
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFF1E293B),
                            width: 4.5,
                          ),
                          boxShadow: [
                            if (isConnected) ...[
                              BoxShadow(
                                color: const Color(0xFF10B981).withOpacity(0.4),
                                blurRadius: 35,
                                spreadRadius: 6,
                              ),
                              BoxShadow(
                                color: const Color(0xFF10B981).withOpacity(0.15),
                                blurRadius: 60,
                                spreadRadius: 15,
                              ),
                            ],
                            if (isConnecting)
                              BoxShadow(
                                color: const Color(0xFFF59E0B).withOpacity(0.4),
                                blurRadius: 30,
                                spreadRadius: 5,
                              ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isConnecting)
                              const SizedBox(
                                width: 50,
                                height: 50,
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                                  strokeWidth: 4,
                                ),
                              )
                            else
                              Icon(
                                Icons.hub_rounded,
                                size: 68,
                                color: isConnected
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFF475569),
                              ),
                            const SizedBox(height: 8),
                            Text(
                              isConnected
                                  ? "Connected"
                                  : isConnecting
                                      ? "Connecting..."
                                      : "Disconnected",
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                                color: isConnected
                                    ? const Color(0xFF10B981)
                                    : isConnecting
                                        ? const Color(0xFFF59E0B)
                                        : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isConnected
                          ? "Connected to Psiphon over MASQUE"
                          : "Tap to connect (Psiphon)",
                      style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // کارت تلمتری آی‌پی خروجی
              _buildConnectionTelemetryCard(isConnected),

              const SizedBox(height: 4),

              // کارت‌های سرعت دانلود و آپلود
              _buildStatsGrid(isConnected, value),

              const SizedBox(height: 14),

              // نوار وضعیت تحتانی
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF101726),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.shield_rounded, size: 16, color: Color(0xFF10B981)),
                        SizedBox(width: 8),
                        Text(
                          "Psiphon Protocol Protection",
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white70),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                      ),
                      child: Text(
                        "Region: $_selectedPsiphonCountry",
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
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
        final isConnected = _activeEngine == ActiveEngine.tor && value.state == "CONNECTED";
        final isConnecting = _isTransitioning && _activeEngine != ActiveEngine.tor;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // کارت سایبرپانک ساخت لایه‌های پیازی تور
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF101726),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isConnected 
                        ? const Color(0xFFC084FC) 
                        : isConnecting 
                            ? const Color(0xFFF59E0B) 
                            : Colors.white12,
                    width: 1.2,
                  ),
                  boxShadow: [
                    if (isConnected || isConnecting)
                      BoxShadow(
                        color: (isConnected ? const Color(0xFFC084FC) : const Color(0xFFF59E0B)).withOpacity(0.12),
                        blurRadius: 16,
                      )
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.hub_rounded, 
                              size: 16, 
                              color: isConnected ? const Color(0xFFC084FC) : const Color(0xFFF59E0B),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              "Tor Circuit Pipeline",
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ],
                        ),
                        if (_torBootstrapProgress > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFC084FC).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFC084FC).withOpacity(0.35)),
                            ),
                            child: Text(
                              "$_torBootstrapProgress%",
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFC084FC)),
                            ),
                          ),
                      ],
                    ),
                    if (isConnecting && _torBootstrapProgress > 0) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: _torBootstrapProgress / 100,
                          backgroundColor: Colors.white10,
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFC084FC)),
                          minHeight: 4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _buildStepRow(
                      stepNumber: 1,
                      title: _t("tor_layer_aether"),
                      isDone: isConnected || (isConnecting && _torCurrentStep > 1),
                      isActive: isConnecting && _torCurrentStep == 1,
                    ),
                    const Divider(height: 14, color: Colors.white10),
                    _buildStepRow(
                      stepNumber: 2,
                      title: _t("tor_layer_tor"),
                      isDone: isConnected || (isConnecting && _torCurrentStep > 2),
                      isActive: isConnecting && _torCurrentStep == 2,
                    ),
                    const Divider(height: 14, color: Colors.white10),
                    _buildStepRow(
                      stepNumber: 3,
                      title: _t("tor_layer_vpn"),
                      isDone: isConnected,
                      isActive: isConnecting && _torCurrentStep == 3,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // دکمه مرکزی تور با حلقه‌های بنفش نئونی تابان
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: isConnecting
                          ? null
                          : isConnected
                              ? _disconnectCurrent
                              : _connectTor,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        width: 175,
                        height: 175,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF0E1422),
                          border: Border.all(
                            color: isConnected
                                ? const Color(0xFFC084FC)
                                : isConnecting
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFF1E293B),
                            width: 4.5,
                          ),
                          boxShadow: [
                            if (isConnected) ...[
                              BoxShadow(
                                color: const Color(0xFFC084FC).withOpacity(0.45),
                                blurRadius: 35,
                                spreadRadius: 6,
                              ),
                              BoxShadow(
                                color: const Color(0xFFC084FC).withOpacity(0.18),
                                blurRadius: 60,
                                spreadRadius: 15,
                              ),
                            ],
                            if (isConnecting)
                              BoxShadow(
                                color: const Color(0xFFF59E0B).withOpacity(0.4),
                                blurRadius: 30,
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
                                    width: 50,
                                    height: 50,
                                    child: CircularProgressIndicator(
                                      value: _torBootstrapProgress > 0 ? _torBootstrapProgress / 100 : null,
                                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                                      strokeWidth: 4,
                                    ),
                                  ),
                                  if (_torBootstrapProgress > 0)
                                    Text(
                                      "$_torBootstrapProgress%",
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                                    )
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _t("connecting"),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)),
                              ),
                            ] else ...[
                              Icon(
                                Icons.security_rounded,
                                size: 68,
                                color: isConnected
                                    ? const Color(0xFFC084FC)
                                    : const Color(0xFF475569),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                isConnected
                                    ? _t("connected")
                                    : _t("disconnected"),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                  color: isConnected
                                      ? const Color(0xFFC084FC)
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isConnected ? "Connected to Onion Circuits" : "Tap to connect (Tor Onion Network)",
                      style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // وضعیت استپ در کپسول نئونی
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101726),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isConnected ? const Color(0xFFC084FC).withOpacity(0.4) : Colors.white10,
                    ),
                  ),
                  child: Text(
                    _torStepStatus,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isConnected ? const Color(0xFFC084FC) : Colors.amberAccent,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

              // کارت آی‌پی خروجی
              _buildConnectionTelemetryCard(isConnected),

              const SizedBox(height: 4),

              // کارت‌های دانلود و آپلود
              _buildStatsGrid(isConnected, value),

              const SizedBox(height: 20),

              // عنوان انتخاب مسیر تور
              Row(
                children: [
                  const Icon(Icons.route_rounded, size: 16, color: Color(0xFFC084FC)),
                  const SizedBox(width: 8),
                  Text(
                    _t("tor_mode_select"),
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              _buildTorModeOption(
                modeKey: "aether_masque",
                title: _t("tor_mode_aether_masque_title"),
                desc: _t("tor_mode_aether_masque_desc"),
                badge: "RECOMMENDED",
                icon: Icons.shield_rounded,
                color: const Color(0xFFA855F7),
                disabled: isConnected || isConnecting,
              ),
              _buildTorModeOption(
                modeKey: "aether_quic",
                title: _t("tor_mode_aether_quic_title"),
                desc: _t("tor_mode_aether_quic_desc"),
                badge: "QUIC SPEED",
                icon: Icons.flash_on_rounded,
                color: const Color(0xFF00F2FE),
                disabled: isConnected || isConnecting,
              ),
              _buildTorModeOption(
                modeKey: "snowflake",
                title: _t("tor_mode_snowflake_title"),
                desc: _t("tor_mode_snowflake_desc"),
                badge: "WEBRTC",
                icon: Icons.ac_unit_rounded,
                color: const Color(0xFFF59E0B),
                disabled: isConnected || isConnecting,
              ),
              _buildTorModeOption(
                modeKey: "direct",
                title: _t("tor_mode_direct_title"),
                desc: _t("tor_mode_direct_desc"),
                badge: "DIRECT",
                icon: Icons.public_rounded,
                color: const Color(0xFF38BDF8),
                disabled: isConnected || isConnecting,
              ),
              _buildTorModeOption(
                modeKey: "custom",
                title: _t("tor_mode_custom_title"),
                desc: _t("tor_mode_custom_desc"),
                badge: "CUSTOM",
                icon: Icons.edit_note_rounded,
                color: const Color(0xFFEC4899),
                disabled: isConnected || isConnecting,
              ),

              if (_selectedTorMode == "custom")
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, bottom: 12.0),
                  child: TextField(
                    controller: _customBridgeController,
                    maxLines: 3,
                    enabled: !isConnected && !isConnecting,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    decoration: InputDecoration(
                      hintText: _t("tor_custom_bridge_hint"),
                      hintStyle: const TextStyle(fontSize: 11, color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF101726),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFC084FC)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: const Color(0xFFC084FC).withOpacity(0.4)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFC084FC), width: 1.5),
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 20),
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
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
            child: const Icon(Icons.check, color: Colors.black, size: 12),
          )
        else if (isActive)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFFF59E0B)),
          )
        else
          CircleAvatar(
            radius: 9,
            backgroundColor: Colors.white12,
            child: Text("$stepNumber", style: const TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold)),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: (isDone || isActive) ? FontWeight.bold : FontWeight.w500,
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
    required String badge,
    required IconData icon,
    required Color color,
    required bool disabled,
  }) {
    final bool isSelected = _selectedTorMode == modeKey;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: isSelected ? const Color(0xFF101726) : const Color(0xFF0E1422),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSelected ? color : Colors.white10,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: disabled ? null : () => setState(() => _selectedTorMode = modeKey),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: isSelected ? color.withOpacity(0.16) : Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isSelected ? color.withOpacity(0.4) : Colors.white10),
                  ),
                  child: Icon(icon, color: isSelected ? color : Colors.grey, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? Colors.white : Colors.white70,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        desc,
                        style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Radio<String>(
                  value: modeKey,
                  groupValue: _selectedTorMode,
                  activeColor: color,
                  onChanged: disabled ? null : (val) {
                    if (val != null) setState(() => _selectedTorMode = val);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAetherModeOption({
    required String modeKey,
    required String title,
    required String desc,
    required String badge,
    required IconData icon,
    required Color color,
    required bool disabled,
  }) {
    final bool isSelected = _selectedAetherMode == modeKey;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: isSelected ? const Color(0xFF101726) : const Color(0xFF0E1422),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSelected ? color : Colors.white10,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: disabled ? null : () => setState(() => _selectedAetherMode = modeKey),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: isSelected ? color.withOpacity(0.16) : Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isSelected ? color.withOpacity(0.4) : Colors.white10),
                  ),
                  child: Icon(icon, color: isSelected ? color : Colors.grey, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? Colors.white : Colors.white70,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        desc,
                        style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Radio<String>(
                  value: modeKey,
                  groupValue: _selectedAetherMode,
                  activeColor: color,
                  onChanged: disabled ? null : (val) {
                    if (val != null) setState(() => _selectedAetherMode = val);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsGrid(bool isConnected, V2RayStatus value) {
    return Row(
      children: [
        // کارت دانلود
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF101726),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F2FE).withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF00F2FE).withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.arrow_downward_rounded, color: Color(0xFF00F2FE), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Download",
                        style: TextStyle(fontSize: 10.5, color: Colors.grey, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _formatBytes(isConnected ? value.downloadSpeed : 0, isSpeed: true),
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // کارت آپلود
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF101726),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.arrow_upward_rounded, color: Color(0xFFF59E0B), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Upload",
                        style: TextStyle(fontSize: 10.5, color: Colors.grey, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _formatBytes(isConnected ? value.uploadSpeed : 0, isSpeed: true),
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: _bypassIran ? const Color(0xFF10B981) : Colors.grey.withOpacity(0.2),
                width: 1.2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _bypassIran 
                        ? const Color(0xFF10B981).withOpacity(0.15) 
                        : Colors.grey.withOpacity(0.15),
                    child: Icon(
                      Icons.alt_route_rounded, 
                      color: _bypassIran ? const Color(0xFF10B981) : Colors.grey, 
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t("bypass_iran_title"),
                          style: TextStyle(
                            fontSize: 14, 
                            fontWeight: FontWeight.bold,
                            color: _bypassIran ? const Color(0xFF10B981) : null,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _t("bypass_iran_desc"),
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _bypassIran,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (val) {
                      _setBypassIranSetting(val);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),

          Card(
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF3B82F6), width: 1.2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Color(0xFF3B82F6),
                        child: Icon(Icons.terminal_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t("logs_title"),
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _t("logs_subtitle"),
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LogsScreen(
                              currentLang: widget.currentLang,
                              torChannel: _torChannel,
                              aetherChannel: _aetherChannel,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.receipt_long_rounded, size: 18),
                      label: Text(
                        _t("logs_view_btn"),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),

          Card(
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Colors.amber,
                        child: Icon(Icons.battery_charging_full_rounded, color: Colors.black, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t("battery_opt_title"),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _t("battery_opt_desc"),
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          await _aetherChannel.invokeMethod('requestIgnoreBatteryOptimizations');
                        } catch (_) {}
                      },
                      icon: const Icon(Icons.flash_auto_rounded, size: 16),
                      label: Text(_t("battery_opt_btn"), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),

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
          const SizedBox(height: 15),

          // بخش ارتباط، کانال تلگرام و حمایت مالی
          Card(
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t("contact_title"),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _launchURL(telegramChannelUrl),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF229ED9)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.send_rounded, size: 16, color: Color(0xFF229ED9)),
                          label: Text(_t("contact_telegram"), style: const TextStyle(fontSize: 11, color: Color(0xFF229ED9))),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _openDonationDialog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber.shade700,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.favorite_rounded, size: 16),
                          label: Text(_t("contact_donate"), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),

          // بخش بیانیه حریم خصوصی
          Card(
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.shield_outlined, color: Theme.of(context).colorScheme.secondary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _t("privacy_title"),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _t("privacy_text"),
                    style: const TextStyle(fontSize: 12, height: 1.5, color: Colors.white60),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
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

  
}

class LogsScreen extends StatefulWidget {
  final String currentLang;
  final MethodChannel torChannel;
  final MethodChannel aetherChannel;

  const LogsScreen({
    super.key,
    required this.currentLang,
    required this.torChannel,
    required this.aetherChannel,
  });

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _clearLogs() async {
    AppLogger.clear();
    try {
      await widget.torChannel.invokeMethod('clearNativeLogs');
      await widget.aetherChannel.invokeMethod('clearNativeLogs');
    } catch (_) {}
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.currentLang == "fa" ? "گزارشات پاک‌سازی شدند." : "Logs cleared."),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Color _getTagColor(String tag) {
    switch (tag.toUpperCase()) {
      case "ERROR":
      case "TORERROR":
      case "AETHERERROR":
        return Colors.redAccent;
      case "TOR":
      case "TORCORE":
      case "TORCONFIG":
      case "TORPROCESS":
        return const Color(0xFFC084FC);
      case "AETHER":
      case "AETHERCORE":
      case "AETHERCOMMAND":
      case "AETHERPROCESS":
        return const Color(0xFF06B6D4);
      case "V2RAY":
      case "V2RAY-CORE":
        return const Color(0xFF10B981);
      case "L7-SCAN":
        return const Color(0xFFF59E0B);
      case "DNS-PROBE":
      case "DNS-RESCUE":
        return const Color(0xFF38BDF8);
      case "TELEMETRY":
        return Colors.pinkAccent;
      case "NATIVE":
      case "NATIVELOADER":
        return Colors.tealAccent;
      default:
        return Colors.blueAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFa = widget.currentLang == "fa";
    return Directionality(
      textDirection: isFa ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            isFa ? "گزارشات و لاگ‌های سیستم" : "System Logs & Diagnostics",
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.copy_all_rounded),
              tooltip: isFa ? "کپی همه" : "Copy All",
              onPressed: () {
                final text = AppLogger.getAllLogsFormatted();
                if (text.isNotEmpty) {
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isFa ? "تمامی لاگ‌ها کپی شدند!" : "All logs copied to clipboard!"),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: isFa ? "پاک‌سازی" : "Clear All",
              onPressed: _clearLogs,
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: TextField(
                controller: _searchController,
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val.toLowerCase().trim();
                  });
                },
                decoration: InputDecoration(
                  hintText: isFa ? "جستجو در متن لاگ‌ها..." : "Filter logs...",
                  hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = "";
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: AppLogger.logCountNotifier,
                builder: (context, count, child) {
                  final logs = AppLogger.currentLogs;
                  final filteredLogs = _searchQuery.isEmpty
                      ? logs
                      : logs.where((e) => e.format().toLowerCase().contains(_searchQuery)).toList();

                  if (filteredLogs.isEmpty) {
                    return Center(
                      child: Text(
                        isFa ? "هنوز هیچ لاگی ثبت نشده است." : "No logs available.",
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    );
                  }

                  return Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF090D16),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: ListView.builder(
                      controller: _scrollController,
                      itemCount: filteredLogs.length,
                      itemBuilder: (context, index) {
                        final entry = filteredLogs[index];
                        final tagColor = _getTagColor(entry.tag);

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3.0),
                          child: SelectableText.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: "[${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}:${entry.time.second.toString().padLeft(2, '0')}.${entry.time.millisecond.toString().padLeft(3, '0')}] ",
                                  style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
                                ),
                                TextSpan(
                                  text: "[${entry.tag}] ",
                                  style: TextStyle(
                                    color: tagColor,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                TextSpan(
                                  text: entry.message,
                                  style: TextStyle(
                                    color: entry.isError ? Colors.redAccent : Colors.white70,
                                    fontSize: 11.5,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.small(
          backgroundColor: const Color(0xFF3B82F6),
          onPressed: _scrollToBottom,
          tooltip: isFa ? "اسکرول به انتها" : "Scroll to bottom",
          child: const Icon(Icons.arrow_downward, color: Colors.white),
        ),
      ),
    );
  }
}
