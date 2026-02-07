import 'dart:async'; // TimeoutException is in dart:async

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:pasada_passenger_app/authentication/authGate.dart';
import 'package:pasada_passenger_app/authentication/createAccount.dart';
import 'package:pasada_passenger_app/authentication/createAccountCred.dart';
import 'package:pasada_passenger_app/authentication/loginAccount.dart';
import 'package:pasada_passenger_app/providers/weather_provider.dart';
import 'package:pasada_passenger_app/screens/introductionScreen.dart';
import 'package:pasada_passenger_app/services/background_ride_service.dart';
import 'package:pasada_passenger_app/services/lazy_initialization_service.dart';
import 'package:pasada_passenger_app/services/notificationService.dart';
import 'package:pasada_passenger_app/services/performance_monitoring_service.dart';
import 'package:pasada_passenger_app/services/slow_internet_warning_service.dart';
import 'package:pasada_passenger_app/theme/theme_controller.dart';
import 'package:pasada_passenger_app/utils/adaptive_memory_manager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Define a top-level handler for background messages
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await NotificationService.initializeWithoutPrompt();
  await NotificationService.showNotification(
    title: message.notification?.title ?? 'Pasada',
    body: message.notification?.body ?? 'You have a new notification',
  );
}

/// Bootstraps only critical services for faster initial startup
/// Uses timeouts to prevent hanging on slow networks/low-end devices
Future<void> _bootstrapCriticalServices() async {
  final performanceMonitor = PerformanceMonitoringService();
  final memoryManager = AdaptiveMemoryManager();
  final slowInternetService = SlowInternetWarningService();

  try {
    // Initialize performance monitoring (synchronous, no timeout needed)
    performanceMonitor.initialize();
    performanceMonitor
        .recordStartupMilestone('performance_monitoring_initialized');

    // Initialize adaptive memory manager with timeout
    await memoryManager.initialize().timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        debugPrint('Warning: Memory manager initialization timed out');
      },
    );
    performanceMonitor.recordStartupMilestone('memory_manager_initialized');

    // Initialize slow internet warning service with timeout (non-critical)
    try {
      await slowInternetService.initialize().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('Warning: Slow internet service initialization timed out');
        },
      );
      performanceMonitor
          .recordStartupMilestone('slow_internet_service_initialized');
    } catch (e) {
      debugPrint('Slow internet service init failed (non-critical): $e');
      // Continue even if this fails
    }

    // Initialize background ride service with timeout
    try {
      await BackgroundRideService.initialize().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint(
              'Warning: Background ride service initialization timed out');
        },
      );
      performanceMonitor
          .recordStartupMilestone('background_ride_service_initialized');

      // Check if there's an active ride that needs background service (with timeout)
      await BackgroundRideService.restoreServiceIfNeeded().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('Warning: Background service restoration timed out');
        },
      );
      performanceMonitor
          .recordStartupMilestone('background_service_restoration_checked');
    } catch (e) {
      debugPrint('Background service init failed (non-critical): $e');
      // Continue even if this fails
    }

    // Start only absolutely essential services in parallel with overall timeout
    await Future.wait([
      Firebase.initializeApp().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException(
              'Firebase initialization timed out', const Duration(seconds: 15));
        },
      ),
      dotenv.load(fileName: '.env').timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('Environment config loading timed out',
              const Duration(seconds: 5));
        },
      ).then((_) {
        // Cache only essential config
        memoryManager.addToCache('SUPABASE_URL', dotenv.env['SUPABASE_URL']);
        memoryManager.addToCache(
            'SUPABASE_ANON_KEY', dotenv.env['SUPABASE_ANON_KEY']);
      }),
    ]).timeout(
      const Duration(seconds: 20), // Overall timeout for both
      onTimeout: () {
        throw TimeoutException('Critical services initialization timed out',
            const Duration(seconds: 20));
      },
    );

    performanceMonitor.recordStartupMilestone('firebase_and_config_loaded');

    // Initialize Supabase if config is present (with timeout)
    final url = memoryManager.getFromCache('SUPABASE_URL');
    final key = memoryManager.getFromCache('SUPABASE_ANON_KEY');
    if (url != null && key != null) {
      await Supabase.initialize(
        url: url,
        anonKey: key,
        authOptions:
            const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
        realtimeClientOptions:
            const RealtimeClientOptions(logLevel: RealtimeLogLevel.info),
        storageOptions: const StorageClientOptions(retryAttempts: 3),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException(
              'Supabase initialization timed out', const Duration(seconds: 10));
        },
      );
      performanceMonitor.recordStartupMilestone('supabase_initialized');
    }
  } on TimeoutException catch (e) {
    debugPrint('Critical initialization timeout: $e');
    // Don't rethrow - allow app to continue with degraded functionality
    // The app should still be usable even if some services fail to initialize
  } catch (e) {
    debugPrint('Critical initialization error: $e');
    // Don't rethrow - allow app to continue
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Attach background handler before Firebase init
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Enhanced: Use priority-based initialization for faster startup
  // Start only critical services, let rest load progressively
  final initFuture = _bootstrapCriticalServices();

  // Show enhanced app initializer with priority loading
  runApp(EnhancedAppInitializer(initFuture));
}

/// Enhanced app initializer with priority-based loading
class EnhancedAppInitializer extends StatefulWidget {
  final Future<void> criticalInitFuture;
  const EnhancedAppInitializer(this.criticalInitFuture, {super.key});

  @override
  State<EnhancedAppInitializer> createState() => _EnhancedAppInitializerState();
}

class _EnhancedAppInitializerState extends State<EnhancedAppInitializer> {
  bool _criticalComplete = false;
  String _statusMessage = 'Starting core services...';
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeWithProgress();
  }

  Future<void> _initializeWithProgress() async {
    try {
      // Wait for critical services with a maximum timeout
      // This prevents infinite waiting on slow networks/devices
      await widget.criticalInitFuture.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('Warning: Initialization exceeded maximum timeout');
          // App can still work with degraded functionality
        },
      );

      if (mounted) {
        setState(() {
          _criticalComplete = true;
          _statusMessage = 'Ready to launch!';
          _progress = 1.0;
        });
        // Small delay to show completion message
        await Future.delayed(const Duration(milliseconds: 300));
      }
    } catch (e) {
      debugPrint('Critical initialization error: $e');
      if (mounted) {
        // Even if initialization fails, try to show the app
        // Some services may have initialized successfully
        setState(() {
          _criticalComplete = true;
          _statusMessage = 'Launching...';
          _progress = 1.0;
        });
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_criticalComplete) {
      return MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF121212),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // App logo
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/png/pasada_app_icon_store.png',
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // App name
                const Text(
                  'Pasada',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFF5F5F5),
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 48),

                // Progress indicator
                SizedBox(
                  width: 200,
                  child: LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    backgroundColor: const Color(0xFF333333),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFF00CC58)),
                  ),
                ),
                const SizedBox(height: 16),

                // Status message
                Text(
                  _statusMessage,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFFCCCCCC),
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const PasadaPassenger();
  }
}

/// Legacy app initializer (kept for compatibility)
class AppInitializer extends StatelessWidget {
  final Future<void> initFuture;
  const AppInitializer(this.initFuture, {super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: initFuture,
      builder: (ctx, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            home: Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        return const PasadaPassenger();
      },
    );
  }
}

final supabase = Supabase.instance.client;

class PasadaPassenger extends StatefulWidget {
  const PasadaPassenger({super.key});

  @override
  State<PasadaPassenger> createState() => _PasadaPassengerState();
}

class _PasadaPassengerState extends State<PasadaPassenger> {
  final ThemeController _themeController = ThemeController();
  final AdaptiveMemoryManager _memoryManager = AdaptiveMemoryManager();
  final LazyInitializationService _lazyInitService =
      LazyInitializationService();
  final PerformanceMonitoringService _performanceMonitor =
      PerformanceMonitoringService();

  @override
  void initState() {
    super.initState();
    _themeController.initialize();

    // Start lazy initialization after a short delay to let UI render
    Future.delayed(const Duration(milliseconds: 500), () {
      _lazyInitService.startLazyInitialization();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _memoryManager.addToCache('isDarkMode', _themeController.isDarkMode);
    _performanceMonitor.recordStartupMilestone('ui_initialized');
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => WeatherProvider()),
        ],
        child: ListenableBuilder(
          listenable: _themeController,
          builder: (context, child) {
            return MaterialApp(
              navigatorKey: navigatorKey,
              title: 'Pasada',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                scaffoldBackgroundColor: _themeController.isDarkMode
                    ? const Color(0xFF121212)
                    : const Color(0xFFF5F5F5),
                fontFamily: 'Inter',
                useMaterial3: true,
                brightness: _themeController.isDarkMode
                    ? Brightness.dark
                    : Brightness.light,
                textTheme: TextTheme(
                  bodyLarge: TextStyle(
                      color: _themeController.isDarkMode
                          ? const Color(0xFFF5F5F5)
                          : const Color(0xFF121212)),
                  bodyMedium: TextStyle(
                      color: _themeController.isDarkMode
                          ? const Color(0xFFF5F5F5)
                          : const Color(0xFF121212)),
                  bodySmall: TextStyle(
                      color: _themeController.isDarkMode
                          ? const Color(0xFFF5F5F5)
                          : const Color(0xFF121212)),
                  // Ensure TextField text uses proper color in light mode
                  titleMedium: TextStyle(
                      color: _themeController.isDarkMode
                          ? const Color(0xFFF5F5F5)
                          : const Color(0xFF121212)),
                ),
                inputDecorationTheme: InputDecorationTheme(
                  filled: true,
                  fillColor: _themeController.isDarkMode
                      ? const Color(0xFF1E1E1E)
                      : const Color(0xFFF5F5F5),
                ),
              ),
              // screens: const PasadaHomePage(title: 'Pasada'),
              home: const AuthGate(),
              routes: <String, WidgetBuilder>{
                'introduction': (BuildContext context) =>
                    const IntroductionScreen(),
                'createAccount': (BuildContext context) =>
                    const CreateAccountPage(),
                'cred': (context) {
                  final args = ModalRoute.of(context)!.settings.arguments
                      as Map<String, dynamic>;
                  return CreateAccountCredPage(
                    title: 'Create Account',
                    email: args['email'],
                  );
                },
                'loginAccount': (BuildContext context) =>
                    const LoginAccountPage(),
              },
            );
          },
        ));
  }
}

// make the app run
class PasadaHomePage extends StatefulWidget {
  const PasadaHomePage({super.key});

  @override
  State<PasadaHomePage> createState() => PasadaHomePageState();
}

// application content
class PasadaHomePageState extends State<PasadaHomePage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _totalPages = 3;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args?['accountCreated'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account created successfully!')),
        );
        ModalRoute.of(context)?.settings.arguments != null;
      }
    });
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Container(
        decoration: BoxDecoration(
          gradient: _getTimeBasedGradient(),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (int page) {
                    setState(() {
                      _currentPage = page;
                    });
                  },
                  children: [
                    _buildPage(
                      title: _getTimeBasedGreeting(),
                      subtitle: 'Welcome sa Pasada!',
                      content: 'Salamat sa pagdownload, Ma\'am/Sir!',
                      icon: _getTimeBasedIcon(),
                    ),
                    _buildPage(
                      title: 'Easy Booking',
                      subtitle: 'Book your ride in seconds',
                      content:
                          'Select your route, set your preferences, and you\'re ready to go!',
                      icon: Icons.book,
                    ),
                    _buildPage(
                      title: 'Get Started',
                      subtitle: 'Create an account or log in',
                      content:
                          'Join our community of passengers for a better commuting experience',
                      icon: Icons.person,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 30),
                child: Column(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder:
                          (Widget child, Animation<double> animation) {
                        final offsetAnimation = Tween<Offset>(
                          begin: const Offset(0, 0.3),
                          end: Offset.zero,
                        ).animate(animation);
                        return SlideTransition(
                          position: offsetAnimation,
                          child:
                              FadeTransition(opacity: animation, child: child),
                        );
                      },
                      child: _currentPage == 0
                          ? Material(
                              key: const ValueKey('swipe_text'),
                              color: Colors.transparent,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                                side: BorderSide(
                                  color: Color(0xFFF5F5F5),
                                  width: 1,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Text(
                                      'Swipe to learn more about the app',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'Inter',
                                        color: Color(0xFFF5F5F5),
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(
                                      Icons.arrow_forward_ios,
                                      size: 14,
                                      color: Color(0xFFF5F5F5),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 35),
                    // Dot indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _totalPages,
                        (index) => _buildDotIndicator(index),
                      ),
                    ),
                    const SizedBox(height: 30),
                    // Navigation buttons
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Back button (hidden on first page)
                          _currentPage > 0
                              ? IconButton(
                                  icon: const Icon(Icons.arrow_back_ios,
                                      color: Colors.white),
                                  onPressed: () {
                                    _pageController.previousPage(
                                      duration:
                                          const Duration(milliseconds: 300),
                                      curve: Curves.easeInOut,
                                    );
                                  },
                                )
                              : const SizedBox(width: 48),

                          // Next button or Get Started button with fade animation
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder:
                                (Widget child, Animation<double> animation) {
                              return FadeTransition(
                                  opacity: animation, child: child);
                            },
                            child: _currentPage < _totalPages - 1
                                ? IconButton(
                                    key: const ValueKey('next_button'),
                                    icon: const Icon(Icons.arrow_forward_ios,
                                        color: Color(0xFFF5F5F5)),
                                    onPressed: () {
                                      _pageController.nextPage(
                                        duration:
                                            const Duration(milliseconds: 300),
                                        curve: Curves.easeInOut,
                                      );
                                    },
                                  )
                                : ElevatedButton(
                                    key: const ValueKey('get_started_button'),
                                    onPressed: () async {
                                      // Save that user has seen onboarding
                                      final prefs =
                                          await SharedPreferences.getInstance();
                                      await prefs.setBool(
                                          'hasSeenOnboarding', true);

                                      if (mounted) {
                                        Navigator.pushNamed(
                                            context, 'introduction');
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Color(0xFFF5F5F5),
                                      foregroundColor: const Color(0xFF00CC58),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24, vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                      elevation: 3,
                                    ),
                                    child: const Text(
                                      'Get Started',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();

    // Set status bar to white icons
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light, // White icons
      statusBarBrightness: Brightness.dark, // Dark background (for iOS)
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pageController.dispose();
    AdaptiveMemoryManager().disposeAdaptive();
    super.dispose();
  }

  String _getTimeBasedGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return 'Magandang Umaga!';
    } else if (hour >= 12 && hour < 18) {
      return 'Magandang Hapon!';
    } else if (hour >= 18 && hour < 22) {
      return 'Magandang Gabi!';
    } else {
      return 'Magandang Gabi!';
    }
  }

  LinearGradient _getTimeBasedGradient() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      // Morning
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF236078), Color(0xFF439464)],
        transform: GradientRotation(21 * 3.14159 / 180),
      );
    } else if (hour >= 12 && hour < 18) {
      // Afternoon
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFCFA425), Color(0xFF26AB37)],
        transform: GradientRotation(21 * 3.14159 / 180),
      );
    } else if (hour >= 18 && hour < 22) {
      // Evening
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFB45F4F), Color(0xFF705776)],
        transform: GradientRotation(21 * 3.14159 / 180),
      );
    } else {
      // Night
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2E3B4E), Color(0xFF1C1F2E)],
        transform: GradientRotation(21 * 3.14159 / 180),
      );
    }
  }

  IconData _getTimeBasedIcon() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return Icons.wb_sunny_rounded; // Morning sun
    } else if (hour >= 12 && hour < 18) {
      return Icons.wb_twilight_rounded; // Afternoon
    } else {
      return Icons.nightlight_round; // Evening and night
    }
  }

  Widget _buildDotIndicator(int index) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 5),
      height: 8,
      width: _currentPage == index ? 24 : 8,
      decoration: BoxDecoration(
        color: _currentPage == index ? Color(0xFFF5F5F5) : Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildPage({
    required String title,
    required String subtitle,
    required String content,
    IconData? icon,
  }) {
    return Center(
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 80,
                    color: const Color(0xFFF5F5F5),
                  ),
                  const SizedBox(height: 24),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF5F5F5),
                    fontFamily: 'Inter',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 18,
                    color: Color(0xFFF5F5F5),
                    fontFamily: 'Inter',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFFF5F5F5),
                    fontWeight: FontWeight.w400,
                    fontFamily: 'Inter',
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
