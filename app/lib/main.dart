import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'models/models.dart';
import 'screens/group_detail_screen.dart';
import 'screens/group_list_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'widgets/app_chrome.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    OneSignal.initialize('30b2c15a-8684-4021-a121-171548e19e29');
    OneSignal.Notifications.requestPermission(true);
  }

  runApp(const ExpenseApp());
}

class ExpenseApp extends StatefulWidget {
  const ExpenseApp({super.key});

  @override
  State<ExpenseApp> createState() => _ExpenseAppState();
}

class _ExpenseAppState extends State<ExpenseApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final _apiService = ApiService();
  AppLinks? _appLinks;

  StreamSubscription<Uri>? _linkSub;
  AppUser? _user;
  bool _booting = true;
  String? _pendingInviteToken;
  Map<String, dynamic>? _pendingNotificationData;
  bool _invitePromptOpen = false;

  @override
  void initState() {
    super.initState();
    _initNotificationHandlers();
    _initDeepLinks();
    _restoreSession();
  }

  void _initNotificationHandlers() {
    if (kIsWeb) {
      return;
    }

    OneSignal.Notifications.addClickListener((event) {
      final rawData = event.notification.additionalData;
      if (rawData != null) {
        _pendingNotificationData = rawData.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        _tryHandlePendingNotificationNavigation();
      }
    });
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _apiService.dispose();
    super.dispose();
  }

  Future<void> _initDeepLinks() async {
    // Web can read deep-link query/path directly from browser URL.
    _handleIncomingUri(Uri.base);

    if (kIsWeb) {
      return;
    }

    _appLinks ??= AppLinks();

    try {
      final initialUri = await _appLinks!.getInitialLink();
      if (initialUri != null) {
        _handleIncomingUri(initialUri);
      }

      _linkSub = _appLinks!.uriLinkStream.listen((uri) {
        _handleIncomingUri(uri);
      });
    } on MissingPluginException {
      // If plugin binding is unavailable, we still support link handling via Uri.base.
    }
  }

  void _handleIncomingUri(Uri uri) {
    final token = _extractInviteToken(uri);
    if (token == null || token.isEmpty) return;

    _pendingInviteToken = token;
    _tryShowInvitePrompt();
  }

  String? _extractInviteToken(Uri uri) {
    final tokenFromQuery = uri.queryParameters['token'];
    if (tokenFromQuery != null && tokenFromQuery.isNotEmpty) {
      return tokenFromQuery;
    }

    if (uri.scheme == 'expensetracker' && uri.host == 'invite') {
      if (uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.first;
      }
      return null;
    }

    final inviteIndex = uri.pathSegments.indexOf('invite');
    if (inviteIndex >= 0 && inviteIndex + 1 < uri.pathSegments.length) {
      return uri.pathSegments[inviteIndex + 1];
    }

    return null;
  }

  Future<void> _restoreSession() async {
    final me = await _apiService.me();
    if (!mounted) return;
    if (me != null && !kIsWeb) {
      OneSignal.login(me.id);
    }
    setState(() {
      _user = me;
      _booting = false;
    });

    _tryShowInvitePrompt();
    _tryHandlePendingNotificationNavigation();
  }

  Future<void> _tryHandlePendingNotificationNavigation() async {
    if (!mounted || _booting || _user == null || _pendingNotificationData == null) {
      return;
    }

    final payload = _pendingNotificationData!;
    final groupIdRaw = payload['groupId'];
    final expenseIdRaw = payload['expenseId'];
    final groupId = groupIdRaw is String ? groupIdRaw : '';
    final expenseId = expenseIdRaw is String ? expenseIdRaw : '';

    if (groupId.isEmpty) {
      _pendingNotificationData = null;
      return;
    }

    try {
      final groups = await _apiService.listGroups();

      Group? targetGroup;
      for (final group in groups) {
        if (group.id == groupId) {
          targetGroup = group;
          break;
        }
      }

      if (targetGroup == null) {
        _pendingNotificationData = null;
        return;
      }

      _pendingNotificationData = null;
      if (!mounted) {
        return;
      }

      _navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => GroupDetailScreen(
            apiService: _apiService,
            group: targetGroup!,
            user: _user!,
            initialExpenseId: expenseId.isEmpty ? null : expenseId,
          ),
        ),
      );
    } catch (_) {
      // Keep app usable even if navigation prefetch fails.
      _pendingNotificationData = null;
    }
  }

  Future<void> _tryShowInvitePrompt() async {
    if (!mounted ||
        _booting ||
        _invitePromptOpen ||
        _pendingInviteToken == null) {
      return;
    }

    if (_user == null) {
      return;
    }

    _invitePromptOpen = true;
    final token = _pendingInviteToken!;

    try {
      final preview = await _apiService.getInvitePreview(token);
      if (!mounted) return;

      final accept = await showDialog<bool>(
        context: _navigatorKey.currentContext!,
        builder: (context) => AlertDialog(
          title: const Text('Group invitation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('You are invited to join ${preview.groupName}.'),
              const SizedBox(height: 10),
              Text('Members: ${preview.memberCount}'),
              Text('Currency: ${preview.currency}'),
              if (!preview.isActive || preview.isExpired) ...[
                const SizedBox(height: 10),
                const Text('This invite is not active anymore.'),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Reject'),
            ),
            FilledButton(
              onPressed: (!preview.isActive || preview.isExpired)
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Accept'),
            ),
          ],
        ),
      );

      if (accept == true) {
        final groupId = await _apiService.joinGroupByInvite(token);
        final groups = await _apiService.listGroups();
        Group? joinedGroup;
        for (final group in groups) {
          if (group.id == groupId) {
            joinedGroup = group;
            break;
          }
        }

        if (joinedGroup != null && mounted) {
          final targetGroup = joinedGroup;
          _navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (context) => GroupDetailScreen(
                apiService: _apiService,
                group: targetGroup,
                user: _user!,
              ),
            ),
          );
        }
      }

      _pendingInviteToken = null;
    } catch (e) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            ApiService.readErrorMessage(
              e,
              fallback: 'Unable to process invite link.',
            ),
          ),
        ),
      );
    } finally {
      _invitePromptOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    const colorScheme = ColorScheme.dark(
      primary: Color(0xFF26D3B4),
      secondary: Color(0xFFFF8E5F),
      surface: Color(0xFF162129),
      surfaceContainerHighest: Color(0xFF1D2A33),
      error: Color(0xFFFF6E74),
      onPrimary: Color(0xFF051018),
      onSecondary: Colors.white,
      onSurface: Color(0xFFF4F7F8),
    );

    final baseTextTheme = GoogleFonts.manropeTextTheme(
      ThemeData.dark().textTheme,
    );

    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      title: 'Expense Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A1319),
        colorScheme: colorScheme,
        textTheme: baseTextTheme.copyWith(
          headlineLarge: baseTextTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2,
          ),
          headlineMedium: baseTextTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
          titleLarge: baseTextTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          bodyMedium: baseTextTheme.bodyMedium?.copyWith(
            color: const Color(0xFF9BB0BC),
            height: 1.45,
          ),
          bodySmall: baseTextTheme.bodySmall?.copyWith(
            color: const Color(0xFF8296A2),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF162129),
          hintStyle: const TextStyle(color: Color(0xFF6F8593)),
          labelStyle: const TextStyle(color: Color(0xFF8FA2AE)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFF293741)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFF26D3B4), width: 1.3),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF26D3B4),
            foregroundColor: const Color(0xFF071219),
            minimumSize: const Size(0, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF26D3B4),
            foregroundColor: const Color(0xFF071219),
            minimumSize: const Size(0, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF2E414E)),
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFFFF8E5F),
          foregroundColor: Colors.white,
          shape: StadiumBorder(),
        ),
      ),
      home: Builder(
        builder: (navContext) {
          if (_booting) {
            return Scaffold(
              body: AppChrome(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0x1A26D3B4),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0x3326D3B4)),
                        ),
                        child: Image.asset('assets/icon.png'),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Split Up',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 10),
                      const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          if (_user == null) {
            return LoginScreen(
              apiService: _apiService,
              onLogin: (user) {
                if (!kIsWeb) OneSignal.login(user.id);
                setState(() => _user = user);
                _tryShowInvitePrompt();
                _tryHandlePendingNotificationNavigation();
              },
            );
          }

          return GroupListScreen(
            apiService: _apiService,
            user: _user!,
            onLogout: () async {
              if (!kIsWeb) OneSignal.logout();
              if (!mounted) return;
              setState(() => _user = null);
            },
            onOpenGroup: (group) {
              Navigator.of(navContext).push(
                MaterialPageRoute(
                  builder: (_) => GroupDetailScreen(
                    apiService: _apiService,
                    group: group,
                    user: _user!,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
