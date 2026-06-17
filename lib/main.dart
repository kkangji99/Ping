import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'providers/favorite_provider.dart';
import 'providers/discount_provider.dart';
import 'providers/notification_provider.dart';
import 'config.dart';
import 'services/supabase_service.dart';
import 'services/notification_service.dart';
import 'views/home_screen.dart';
import 'views/calendar_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // table_calendar ko_KR 로케일 초기화 (반드시 runApp 전에 호출)
  await initializeDateFormatting('ko_KR', null);

  await Supabase.initialize(
    url: supabaseUrl
  , anonKey: supabaseAnonKey
  );

  // 알림 서비스 초기화 + 권한 요청
  await NotificationService.instance.init();
  await NotificationService.instance.requestPermission();

  runApp(const PingApp());
}

class PingApp extends StatelessWidget {
  const PingApp({super.key});

  // ── 테마 ──────────────────────────────────────────────────────────────────────

  static final ThemeData _theme = _buildTheme();

  static ThemeData _buildTheme() {
    // Noto Sans KR: 한국어에 최적화된 깔끔한 산세리프
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4F46E5)   // Indigo 600 — 세련된 블루-퍼플
      , brightness: Brightness.light
      )
    , useMaterial3: true
    );

    final notoSansKr = GoogleFonts.notoSansKrTextTheme(base.textTheme).copyWith(
      // 앱 전반 폰트 크기 / 굵기 조정
      displayLarge:  GoogleFonts.notoSansKr(fontSize: 32, fontWeight: FontWeight.w700)
    , titleLarge:    GoogleFonts.notoSansKr(fontSize: 18, fontWeight: FontWeight.w700)
    , titleMedium:   GoogleFonts.notoSansKr(fontSize: 15, fontWeight: FontWeight.w600)
    , bodyLarge:     GoogleFonts.notoSansKr(fontSize: 14, fontWeight: FontWeight.w400)
    , bodyMedium:    GoogleFonts.notoSansKr(fontSize: 13, fontWeight: FontWeight.w400)
    , labelMedium:   GoogleFonts.notoSansKr(fontSize: 11, fontWeight: FontWeight.w500)
    );

    return base.copyWith(
      textTheme: notoSansKr
    , appBarTheme: AppBarTheme(
        elevation: 0
      , centerTitle: true
      , titleTextStyle: GoogleFonts.notoSansKr(
          fontSize: 17
        , fontWeight: FontWeight.w700
        , color: Colors.white
        )
      )
    , navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => GoogleFonts.notoSansKr(
            fontSize: 11
          , fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w400
          )
        )
      )
    , chipTheme: ChipThemeData(
        labelStyle: GoogleFonts.notoSansKr(fontSize: 11)
      )
    , inputDecorationTheme: InputDecorationTheme(
        hintStyle: GoogleFonts.notoSansKr(fontSize: 14, color: Colors.grey)
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // SupabaseService: 앱 생명주기 동안 단 1개 인스턴스
        Provider<SupabaseService>(
          create: (_) => SupabaseService()
        )
        // NotificationProvider: SharedPreferences 로드 + NotificationService에 연결
      , ChangeNotifierProvider(
          create: (_) {
            final p = NotificationProvider();
            p.load();
            NotificationService.instance.setProvider(p);
            return p;
          }
        )
        // FavoriteProvider: NotificationProvider에 의존
      , ChangeNotifierProxyProvider<NotificationProvider, FavoriteProvider>(
          create: (ctx) => FavoriteProvider(
            notificationProvider: ctx.read<NotificationProvider>()
          )
        , update: (_, notifProvider, prev) =>
              prev ?? FavoriteProvider(notificationProvider: notifProvider)
        )
        // DiscountProvider: FavoriteProvider + SupabaseService + NotificationProvider에 의존
      , ChangeNotifierProxyProvider3<FavoriteProvider, SupabaseService, NotificationProvider, DiscountProvider>(
          create: (ctx) => DiscountProvider(
            service:              ctx.read<SupabaseService>()
          , notificationProvider: ctx.read<NotificationProvider>()
          )
        , update: (_, favProvider, svcProvider, notifProvider, prev) =>
              (prev ?? DiscountProvider(
                service:              svcProvider
              , notificationProvider: notifProvider
              ))
              ..onFavoritesChanged(favProvider.favoriteIds)
        )
      ]
    , child: MaterialApp(
        title: 'Ping'
      , debugShowCheckedModeBanner: false
      , theme: _theme
      , localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate
        , GlobalWidgetsLocalizations.delegate
        , GlobalCupertinoLocalizations.delegate
        ]
      , supportedLocales: const [
          Locale('ko', 'KR')
        , Locale('en', 'US')
        ]
      , home: const MainShell()
      )
    );
  }
}

// ── MainShell ─────────────────────────────────────────────────────────────────

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  static const List<Widget> _screens = [
    HomeScreen()
  , CalendarScreen()
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex
      , children: _screens
      )
    , bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex
      , onDestinationSelected: (index) =>
            setState(() => _currentIndex = index)
      , destinations: const [
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined)
          , selectedIcon: Icon(Icons.storefront)
          , label: '홈'
          )
        , NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined)
          , selectedIcon: Icon(Icons.calendar_month)
          , label: '캘린더'
          )
        ]
      )
    );
  }
}
