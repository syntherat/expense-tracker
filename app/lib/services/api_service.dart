import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../models/models.dart';
import 'dio_session_setup_stub.dart'
    if (dart.library.io) 'dio_session_setup_io.dart';

class ApiService {
  ApiService()
      : _dio = Dio(
          BaseOptions(
            baseUrl: _apiBaseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 20),
            headers: {'Content-Type': 'application/json'},
            extra: {
              // Needed on web so browser includes session cookies.
              'withCredentials': true,
            },
          ),
        ) {
    _sessionTransportReady = configureSessionTransport(_dio);

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          await _sessionTransportReady;
          handler.next(options);
        },
      ),
    );

    // Start session refresh heartbeat every 24 hours to keep session alive
    _startSessionRefreshHeartbeat();
  }

  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://expense-tracker-7aie.onrender.com/api',
  );
  static const String _inviteShareBaseUrl = String.fromEnvironment(
    'INVITE_SHARE_BASE_URL',
    defaultValue: 'https://expense-tracker-7aie.onrender.com/invite',
  );
  final Dio _dio;
  late final Future<void> _sessionTransportReady;
  Timer? _sessionRefreshTimer;

  /// Start periodic session refresh to keep the session alive (every 24 hours)
  void _startSessionRefreshHeartbeat() {
    // Call me() once immediately to verify session, then refresh every 24 hours
    _sessionRefreshTimer = Timer.periodic(const Duration(hours: 24), (_) {
      _refreshSessionSilently();
    });
  }

  /// Silently refresh the session by calling me() without throwing errors
  Future<void> _refreshSessionSilently() async {
    try {
      await me();
    } catch (_) {
      // Silent fail - session may have expired which is ok
      // User will be prompted to login when they next make a request
    }
  }

  void dispose() {
    _sessionRefreshTimer?.cancel();
  }

  static String readErrorMessage(
    Object error, {
    String fallback = 'Something went wrong. Please try again.',
  }) {
    if (error is DioException) {
      final responseData = error.response?.data;
      final fromPayload = _extractMessageFromPayload(responseData);
      if (fromPayload != null && fromPayload.isNotEmpty) {
        return fromPayload;
      }

      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Request timed out. Please check your internet and try again.';
        case DioExceptionType.connectionError:
          return 'Could not connect to server. Please check your connection.';
        case DioExceptionType.cancel:
          return 'Request was cancelled.';
        default:
          return fallback;
      }
    }

    return fallback;
  }

  static String? _extractMessageFromPayload(dynamic payload) {
    if (payload == null) return null;

    if (payload is String && payload.trim().isNotEmpty) {
      return payload.trim();
    }

    if (payload is Map<String, dynamic>) {
      final raw = payload['message'];
      if (raw is String && raw.trim().isNotEmpty) {
        return raw.trim();
      }

      if (raw is Map<String, dynamic>) {
        final fieldErrors = raw['fieldErrors'];
        if (fieldErrors is Map<String, dynamic>) {
          for (final value in fieldErrors.values) {
            if (value is List && value.isNotEmpty) {
              final first = value.first;
              if (first is String && first.trim().isNotEmpty) {
                return first.trim();
              }
            }
          }
        }

        final formErrors = raw['formErrors'];
        if (formErrors is List && formErrors.isNotEmpty) {
          final first = formErrors.first;
          if (first is String && first.trim().isNotEmpty) {
            return first.trim();
          }
        }
      }
    }

    return null;
  }

  Future<AppUser> login({required String name, required String phone}) async {
    final res = await _dio.post('/auth/login', data: {
      'name': name,
      'phone': phone,
    });

    return AppUser.fromJson(res.data['user'] as Map<String, dynamic>);
  }

  Future<AppUser?> me() async {
    const maxAttempts = 3;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final res = await _dio.get('/auth/me');
        return AppUser.fromJson(res.data['user'] as Map<String, dynamic>);
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status == 401 || status == 403) {
          return null;
        }

        final retryable = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError;

        if (!retryable || attempt == maxAttempts - 1) {
          rethrow;
        }

        await Future<void>.delayed(
          Duration(milliseconds: 400 * (attempt + 1)),
        );
      }
    }

    return null;
  }

  Future<void> logout() async {
    await _dio.post('/auth/logout');
  }

  Future<List<Group>> listGroups() async {
    final res = await _dio.get('/groups');
    final rows = (res.data['groups'] as List<dynamic>);
    return rows
        .map((item) => Group.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<(Group, String)> createGroup(String name, String currency) async {
    final res = await _dio.post('/groups', data: {
      'name': name,
      'currency': currency,
    });

    final group = Group.fromJson(res.data['group'] as Map<String, dynamic>);
    final invite = res.data['invite'] as Map<String, dynamic>;
    final inviteLink = (invite['inviteLink'] ?? invite['token']) as String;
    return (group, inviteLink);
  }

  Future<String> joinGroupByInvite(String token) async {
    final inviteToken = _normalizeInviteToken(token);
    final res =
        await _dio.post('/groups/join', data: {'inviteToken': inviteToken});
    return res.data['groupId'] as String;
  }

  Future<InvitePreview> getInvitePreview(String token) async {
    final inviteToken = _normalizeInviteToken(token);
    final res = await _dio.get('/invites/$inviteToken');
    return InvitePreview.fromJson(res.data['invite'] as Map<String, dynamic>);
  }

  Future<({List<GroupMember> members, List<GroupBalance> balances})>
      getGroupDetails(
    String groupId,
  ) async {
    final res = await _dio.get('/groups/$groupId');
    final members = (res.data['members'] as List<dynamic>)
        .map((item) => GroupMember.fromJson(item as Map<String, dynamic>))
        .toList();
    final balances = (res.data['balances'] as List<dynamic>)
        .map((item) => GroupBalance.fromJson(item as Map<String, dynamic>))
        .toList();

    return (members: members, balances: balances);
  }

  Future<List<ExpenseItem>> listExpenses(String groupId) async {
    final res = await _dio.get('/groups/$groupId/expenses');
    final rows = (res.data['expenses'] as List<dynamic>);
    return rows
        .map((item) => ExpenseItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ExpenseDetail> getExpenseDetails(String expenseId) async {
    final res = await _dio.get('/expenses/$expenseId');
    final expense =
        ExpenseItem.fromJson(res.data['expense'] as Map<String, dynamic>);
    final payers = (res.data['payers'] as List<dynamic>)
        .map((item) => ExpenseLineItem.fromJson(item as Map<String, dynamic>))
        .toList();
    final splits = (res.data['splits'] as List<dynamic>)
        .map((item) => ExpenseLineItem.fromJson(item as Map<String, dynamic>))
        .toList();
    final pendingPayments =
        (res.data['pendingPayments'] as List<dynamic>? ?? [])
            .map((item) =>
                ExpensePendingPayment.fromJson(item as Map<String, dynamic>))
            .toList();

    return ExpenseDetail(
      expense: expense,
      payers: payers,
      splits: splits,
      pendingPayments: pendingPayments,
    );
  }

  Future<int> sendExpenseReminder(
    String expenseId, {
    List<String>? userIds,
  }) async {
    final res = await _dio.post('/expenses/$expenseId/reminders', data: {
      if (userIds != null) 'userIds': userIds,
    });
    return (res.data['notifiedCount'] as num?)?.toInt() ?? 0;
  }

  Future<void> markExpensePayment(
    String expenseId,
    String userId, {
    required bool isPaid,
  }) async {
    await _dio.post('/expenses/$expenseId/payments/$userId', data: {
      'isPaid': isPaid,
    });
  }

  Future<void> deleteExpense(String expenseId) async {
    await _dio.delete('/expenses/$expenseId');
  }

  Future<String> refreshInvite(String groupId) async {
    final res = await _dio.post('/groups/$groupId/invites');
    final invite = res.data['invite'] as Map<String, dynamic>;
    return (invite['inviteLink'] ?? invite['token']) as String;
  }

  Future<void> addExpense({
    required String groupId,
    required String description,
    required int amountCents,
    required List<Map<String, dynamic>> payers,
    required List<Map<String, dynamic>> splits,
    XFile? attachment,
  }) async {
    final expenseRes = await _dio.post('/groups/$groupId/expenses', data: {
      'description': description,
      'amountCents': amountCents,
      'currency': 'INR',
      'payers': payers,
      'splits': splits,
    });

    if (attachment == null) return;

    final fileName = attachment.name;
    final mimeType = _mimeType(fileName);
    final bytes = await attachment.readAsBytes();

    // Upload through our server to avoid browser CORS restrictions on direct S3 PUTs.
    final uploadRes = await _dio.post(
      '/uploads/upload',
      data: {
        'groupId': groupId,
        'fileName': fileName,
        'mimeType': mimeType,
        'data': base64Encode(bytes),
      },
      options: Options(
        sendTimeout: const Duration(minutes: 2),
        receiveTimeout: const Duration(minutes: 2),
      ),
    );

    final fileKey = uploadRes.data['key'] as String;
    final fileUrl = uploadRes.data['fileUrl'] as String;

    final expenseId =
        (expenseRes.data['expense'] as Map<String, dynamic>)['id'] as String;

    await _dio.post('/expenses/$expenseId/attachments', data: {
      'fileName': fileName,
      'fileKey': fileKey,
      'fileUrl': fileUrl,
      'mimeType': mimeType,
      'sizeBytes': bytes.length,
    });
  }

  String buildShareableInviteUrl(String tokenOrLink) {
    final raw = tokenOrLink.trim();
    if (raw.isEmpty) return raw;

    try {
      final uri = Uri.parse(raw);
      if ((uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.pathSegments.contains('invite')) {
        return raw;
      }
    } catch (_) {
      // Fall through and normalize token below.
    }

    final token = _normalizeInviteToken(raw);
    if (token.isEmpty) return raw;

    final base = _inviteShareBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base/$token';
  }

  String _mimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  String _normalizeInviteToken(String value) {
    final text = value.trim();
    if (text.isEmpty) return text;

    try {
      final uri = Uri.parse(text);
      final queryToken = uri.queryParameters['token'];
      if (queryToken != null && queryToken.isNotEmpty) {
        return queryToken;
      }

      if (uri.scheme == 'expensetracker' && uri.host == 'invite') {
        if (uri.pathSegments.isNotEmpty) {
          return uri.pathSegments.first;
        }
      }

      final inviteIndex = uri.pathSegments.indexOf('invite');
      if (inviteIndex >= 0 && inviteIndex + 1 < uri.pathSegments.length) {
        return uri.pathSegments[inviteIndex + 1];
      }
    } catch (_) {
      return text;
    }

    return text;
  }
}
