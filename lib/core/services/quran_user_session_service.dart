import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'quran_api_config_service.dart';

enum QuranUserEnvironment { prelive, production }

class QuranUserAuthConfig {
  const QuranUserAuthConfig({
    required this.environment,
    required this.redirectUri,
    required this.scope,
    this.preliveClientId,
    this.productionClientId,
  });

  static const String defaultPreliveClientId =
      'd433d10b-96f4-4fca-8944-8a06fbabefaf';
  static const String defaultProductionClientId =
      '33ec2ec8-0c37-4af5-9f86-fd589bc09e22';
  static const String defaultRedirectUri = 'noorai://oauth/callback';
  static const String defaultScope =
      'offline_access bookmark reading_session activity_day streak note note.publish';

  final QuranUserEnvironment environment;
  final String redirectUri;
  final String scope;
  final String? preliveClientId;
  final String? productionClientId;

  factory QuranUserAuthConfig.defaults() {
    return const QuranUserAuthConfig(
      environment: QuranUserEnvironment.production,
      redirectUri: defaultRedirectUri,
      scope: defaultScope,
    );
  }

  QuranUserAuthConfig copyWith({
    QuranUserEnvironment? environment,
    String? redirectUri,
    String? scope,
    String? preliveClientId,
    String? productionClientId,
  }) {
    return QuranUserAuthConfig(
      environment: environment ?? this.environment,
      redirectUri: redirectUri ?? this.redirectUri,
      scope: scope ?? this.scope,
      preliveClientId: preliveClientId ?? this.preliveClientId,
      productionClientId: productionClientId ?? this.productionClientId,
    );
  }

  String get clientId {
    return environment == QuranUserEnvironment.prelive
        ? (preliveClientId?.trim().isNotEmpty == true
              ? preliveClientId!.trim()
              : defaultPreliveClientId)
        : (productionClientId?.trim().isNotEmpty == true
              ? productionClientId!.trim()
              : defaultProductionClientId);
  }

  String get normalizedScope => normalizeScope(scope);

  static String normalizeScope(String? scope) {
    const allowedScopes = <String>{
      'offline_access',
      'bookmark',
      'reading_session',
      'activity_day',
      'streak',
      'note',
      'note.publish',
    };
    final tokens = (scope ?? '').split(RegExp(r'\s+'));
    final normalized = <String>[];

    for (final token in tokens) {
      final trimmed = token.trim();
      if (trimmed.isEmpty || !allowedScopes.contains(trimmed)) {
        continue;
      }
      if (!normalized.contains(trimmed)) {
        normalized.add(trimmed);
      }
    }

    if (normalized.isEmpty) {
      return defaultScope;
    }

    return normalized.join(' ');
  }

  String get oauthBaseUrl {
    return 'https://oauth2.quran.foundation';
  }

  String get userApiBaseUrl {
    return 'https://apis.quran.foundation/auth/v1';
  }

  String get environmentLabel {
    return environment == QuranUserEnvironment.prelive
        ? 'Pre-Production'
        : 'Production';
  }

  bool get prefersHackathonSync => environment == QuranUserEnvironment.prelive;
}

class QuranUserSession {
  const QuranUserSession({
    required this.accessToken,
    this.refreshToken,
    this.idToken,
    this.scope,
    this.tokenType,
    this.expiresAt,
    this.userId,
  });

  final String accessToken;
  final String? refreshToken;
  final String? idToken;
  final String? scope;
  final String? tokenType;
  final DateTime? expiresAt;
  final String? userId;

  bool get isExpired {
    final expiry = expiresAt;
    if (expiry == null) {
      return false;
    }
    return DateTime.now().isAfter(expiry.subtract(const Duration(minutes: 1)));
  }

  bool get hasOfflineAccess =>
      scope?.split(' ').contains('offline_access') ?? false;
}

class QuranUserSessionService extends ChangeNotifier {
  QuranUserSessionService._();

  static final QuranUserSessionService instance = QuranUserSessionService._();

  static const _storage = FlutterSecureStorage();
  static const _configEnvironmentKey = 'qf_user_environment';
  static const _configRedirectUriKey = 'qf_user_redirect_uri';
  static const _configScopeKey = 'qf_user_scope';
  static const _configPreliveClientIdKey = 'qf_user_prelive_client_id';
  static const _configProductionClientIdKey = 'qf_user_production_client_id';
  static const _tokenAccessKey = 'qf_user_access_token';
  static const _tokenRefreshKey = 'qf_user_refresh_token';
  static const _tokenIdKey = 'qf_user_id_token';
  static const _tokenScopeKey = 'qf_user_scope_value';
  static const _tokenTypeKey = 'qf_user_token_type';
  static const _tokenExpiresAtKey = 'qf_user_expires_at';
  static const _tokenUserIdKey = 'qf_user_id';
  static const _pendingStateKey = 'qf_user_pending_state';
  static const _pendingVerifierKey = 'qf_user_pending_verifier';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      contentType: Headers.formUrlEncodedContentType,
      headers: <String, String>{'Accept': 'application/json'},
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  SharedPreferences? _prefs;
  AppLinks? _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  QuranUserAuthConfig _config = QuranUserAuthConfig.defaults();
  QuranUserSession? _session;
  bool _initialized = false;
  bool _isBusy = false;
  String? _lastAuthError;

  QuranUserAuthConfig get config => _config;
  QuranUserSession? get session => _session;
  bool get isSignedIn => _session?.accessToken.isNotEmpty ?? false;
  bool get isBusy => _isBusy;
  String? get lastAuthError => _lastAuthError;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _prefs = await SharedPreferences.getInstance();
    _config = _loadConfig();
    await _migrateLegacyOAuthEnvironment();
    _session = await _loadSession();
    _appLinks = AppLinks();

    // Mark the service ready before processing deep links so callback handling
    // does not recurse back into initialize() on cold-start OAuth launches.
    _initialized = true;

    final initialLink = await _appLinks!.getInitialLink();
    if (initialLink != null) {
      await _handleIncomingUri(initialLink);
    }

    _linkSubscription = _appLinks!.uriLinkStream.listen(
      (uri) async {
        await _handleIncomingUri(uri);
      },
      onError: (Object error) {
        _lastAuthError = 'Could not read OAuth callback: $error';
        notifyListeners();
      },
    );

    notifyListeners();
  }

  Future<void> disposeService() async {
    await _linkSubscription?.cancel();
    _linkSubscription = null;
    _initialized = false;
  }

  Future<void> updateConfig(QuranUserAuthConfig config) async {
    await initialize();
    _config = config.copyWith(
      scope: QuranUserAuthConfig.normalizeScope(config.scope),
    );
    final prefs = _prefs!;

    await prefs.setString(
      _configEnvironmentKey,
      _config.environment == QuranUserEnvironment.prelive
          ? 'prelive'
          : 'production',
    );
    await prefs.setString(_configRedirectUriKey, _config.redirectUri.trim());
    await prefs.setString(_configScopeKey, _config.normalizedScope);
    await prefs.setString(
      _configPreliveClientIdKey,
      _config.preliveClientId?.trim() ?? '',
    );
    await prefs.setString(
      _configProductionClientIdKey,
      _config.productionClientId?.trim() ?? '',
    );

    notifyListeners();
  }

  Future<bool> startSignIn() async {
    await initialize();
    _setBusy(true);
    _lastAuthError = null;

    try {
      final backendBaseUrl = await _backendBaseUrl();
      if (backendBaseUrl == null) {
        _lastAuthError =
            'Quran Foundation backend URL is required for secure sign-in.';
        return false;
      }

      final verifier = _randomUrlSafeString(64);
      final state = _randomUrlSafeString(32);
      final challenge = _pkceChallenge(verifier);

      await _storage.write(key: _pendingVerifierKey, value: verifier);
      await _storage.write(key: _pendingStateKey, value: state);

      final uri = Uri.parse('${_config.oauthBaseUrl}/oauth2/auth').replace(
        queryParameters: <String, String>{
          'response_type': 'code',
          'client_id': _config.clientId,
          'redirect_uri': _config.redirectUri.trim(),
          'scope': _config.normalizedScope,
          'state': state,
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
        },
      );

      var launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (!launched) {
        launched = await launchUrl(uri);
      }

      if (!launched) {
        _lastAuthError = 'Could not open the Quran Foundation sign-in page.';
      }

      return launched;
    } catch (error) {
      _lastAuthError = 'Failed to start sign-in: $error';
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> saveManualSession({
    required String accessToken,
    String? refreshToken,
    String? idToken,
    String? scope,
    int? expiresInSeconds,
  }) async {
    await initialize();

    final expiry = expiresInSeconds == null
        ? null
        : DateTime.now().add(Duration(seconds: expiresInSeconds));

    await _saveSession(
      QuranUserSession(
        accessToken: accessToken.trim(),
        refreshToken: refreshToken?.trim().isEmpty == true
            ? null
            : refreshToken?.trim(),
        idToken: idToken?.trim().isEmpty == true ? null : idToken?.trim(),
        scope: scope?.trim().isEmpty == true ? null : scope?.trim(),
        tokenType: 'Bearer',
        expiresAt: expiry,
        userId: _extractUserId(idToken?.trim(), accessToken.trim()),
      ),
    );
  }

  Future<QuranUserSession?> getValidSession() async {
    await initialize();
    final current = _session;
    if (current == null) {
      return null;
    }

    if (!current.isExpired) {
      return current;
    }

    if ((current.refreshToken ?? '').isEmpty) {
      return current;
    }

    return refreshSession();
  }

  Future<QuranUserSession?> refreshSession() async {
    await initialize();
    final current = _session;
    final refreshToken = current?.refreshToken;

    if (current == null || refreshToken == null || refreshToken.isEmpty) {
      return current;
    }

    _setBusy(true);
    _lastAuthError = null;

    try {
      final backendBaseUrl = await _backendBaseUrl();
      if (backendBaseUrl == null) {
        _lastAuthError =
            'Quran Foundation backend URL is required for secure sign-in.';
        return current;
      }

      final response = await _dio.post<Map<String, dynamic>>(
        '$backendBaseUrl/api/qf/auth/refresh',
        data: <String, String>{'refreshToken': refreshToken},
        options: Options(contentType: Headers.jsonContentType),
      );

      if (response.statusCode != 200 || response.data == null) {
        final message =
            response.data?['error_description'] as String? ??
            response.data?['message'] as String? ??
            'Refresh failed';
        _lastAuthError = message;
        return current;
      }

      final nextSession = _sessionFromTokenResponse(
        response.data!,
        fallbackRefreshToken: refreshToken,
      );
      await _saveSession(nextSession);
      return nextSession;
    } catch (error) {
      _lastAuthError = 'Failed to refresh session: $error';
      return current;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> signOut() async {
    await initialize();
    await Future.wait(<Future<void>>[
      _storage.delete(key: _tokenAccessKey),
      _storage.delete(key: _tokenRefreshKey),
      _storage.delete(key: _tokenIdKey),
      _storage.delete(key: _tokenScopeKey),
      _storage.delete(key: _tokenTypeKey),
      _storage.delete(key: _tokenExpiresAtKey),
      _storage.delete(key: _tokenUserIdKey),
      _storage.delete(key: _pendingStateKey),
      _storage.delete(key: _pendingVerifierKey),
    ]);
    _session = null;
    _lastAuthError = null;
    notifyListeners();
  }

  QuranUserAuthConfig _loadConfig() {
    final prefs = _prefs!;

    return QuranUserAuthConfig.defaults().copyWith(
      environment: QuranUserEnvironment.production,
      redirectUri:
          prefs.getString(_configRedirectUriKey) ??
          QuranUserAuthConfig.defaultRedirectUri,
      scope: QuranUserAuthConfig.normalizeScope(
        prefs.getString(_configScopeKey),
      ),
      preliveClientId: _emptyToNull(prefs.getString(_configPreliveClientIdKey)),
      productionClientId: _emptyToNull(
        prefs.getString(_configProductionClientIdKey),
      ),
    );
  }

  Future<void> _migrateLegacyOAuthEnvironment() async {
    final prefs = _prefs!;
    final savedEnvironment = prefs.getString(_configEnvironmentKey);
    if (savedEnvironment == 'production') {
      final normalizedScope = QuranUserAuthConfig.normalizeScope(
        prefs.getString(_configScopeKey),
      );
      if (prefs.getString(_configScopeKey) != normalizedScope) {
        _config = _config.copyWith(scope: normalizedScope);
        await prefs.setString(_configScopeKey, normalizedScope);
      }
      return;
    }

    _config = _config.copyWith(environment: QuranUserEnvironment.production);
    await prefs.setString(_configEnvironmentKey, 'production');
    await prefs.setString(_configScopeKey, _config.normalizedScope);
  }

  Future<QuranUserSession?> _loadSession() async {
    final accessToken = await _storage.read(key: _tokenAccessKey);
    if (accessToken == null || accessToken.trim().isEmpty) {
      return null;
    }

    final refreshToken = await _storage.read(key: _tokenRefreshKey);
    final idToken = await _storage.read(key: _tokenIdKey);
    final scope = await _storage.read(key: _tokenScopeKey);
    final tokenType = await _storage.read(key: _tokenTypeKey);
    final expiresAtValue = await _storage.read(key: _tokenExpiresAtKey);
    final userId = await _storage.read(key: _tokenUserIdKey);

    return QuranUserSession(
      accessToken: accessToken,
      refreshToken: _emptyToNull(refreshToken),
      idToken: _emptyToNull(idToken),
      scope: _emptyToNull(scope),
      tokenType: _emptyToNull(tokenType),
      expiresAt: expiresAtValue == null
          ? null
          : DateTime.tryParse(expiresAtValue),
      userId: _emptyToNull(userId),
    );
  }

  Future<void> _saveSession(QuranUserSession session) async {
    _session = session;
    await Future.wait(<Future<void>>[
      _storage.write(key: _tokenAccessKey, value: session.accessToken),
      _storage.write(key: _tokenRefreshKey, value: session.refreshToken),
      _storage.write(key: _tokenIdKey, value: session.idToken),
      _storage.write(key: _tokenScopeKey, value: session.scope),
      _storage.write(key: _tokenTypeKey, value: session.tokenType),
      _storage.write(
        key: _tokenExpiresAtKey,
        value: session.expiresAt?.toIso8601String(),
      ),
      _storage.write(key: _tokenUserIdKey, value: session.userId),
      _storage.delete(key: _pendingStateKey),
      _storage.delete(key: _pendingVerifierKey),
    ]);
    notifyListeners();
  }

  Future<void> _handleIncomingUri(Uri uri) async {
    final redirectUri = Uri.tryParse(_config.redirectUri.trim());
    if (redirectUri == null || !_matchesRedirectUri(uri, redirectUri)) {
      return;
    }

    final error = uri.queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      _lastAuthError = uri.queryParameters['error_description'] ?? error;
      notifyListeners();
      return;
    }

    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    if (code == null || state == null) {
      return;
    }

    final expectedState = await _storage.read(key: _pendingStateKey);
    final verifier = await _storage.read(key: _pendingVerifierKey);
    if (expectedState == null || verifier == null || expectedState != state) {
      _lastAuthError = 'OAuth callback state mismatch.';
      notifyListeners();
      return;
    }

    _setBusy(true);
    _lastAuthError = null;

    try {
      final backendBaseUrl = await _backendBaseUrl();
      if (backendBaseUrl == null) {
        _lastAuthError =
            'Quran Foundation backend URL is required for secure sign-in.';
        notifyListeners();
        return;
      }

      final response = await _dio.post<Map<String, dynamic>>(
        '$backendBaseUrl/api/qf/auth/exchange',
        data: <String, String>{
          'code': code,
          'redirectUri': _config.redirectUri.trim(),
          'codeVerifier': verifier,
          'scope': _config.normalizedScope,
        },
        options: Options(contentType: Headers.jsonContentType),
      );

      if (response.statusCode != 200 || response.data == null) {
        final message =
            response.data?['error_description'] as String? ??
            response.data?['message'] as String? ??
            'Token exchange failed';
        _lastAuthError = message;
        notifyListeners();
        return;
      }

      final nextSession = _sessionFromTokenResponse(response.data!);
      await _saveSession(nextSession);
    } catch (error) {
      _lastAuthError = 'Failed to complete sign-in: $error';
      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  QuranUserSession _sessionFromTokenResponse(
    Map<String, dynamic> data, {
    String? fallbackRefreshToken,
  }) {
    final accessToken = data['access_token'] as String? ?? '';
    final refreshToken =
        data['refresh_token'] as String? ?? fallbackRefreshToken;
    final idToken = data['id_token'] as String?;
    final scope = data['scope'] as String?;
    final tokenType = data['token_type'] as String?;
    final expiresIn = data['expires_in'];
    final expiresAt = expiresIn is num
        ? DateTime.now().add(Duration(seconds: expiresIn.toInt()))
        : null;

    return QuranUserSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      idToken: idToken,
      scope: scope,
      tokenType: tokenType,
      expiresAt: expiresAt,
      userId: _extractUserId(idToken, accessToken),
    );
  }

  String? _extractUserId(String? idToken, String? accessToken) {
    final idPayload = _decodeJwtPayload(idToken);
    final accessPayload = _decodeJwtPayload(accessToken);
    final candidate = idPayload?['sub'] ?? accessPayload?['sub'];
    return candidate is String && candidate.isNotEmpty ? candidate : null;
  }

  Map<String, dynamic>? _decodeJwtPayload(String? token) {
    if (token == null || token.isEmpty) {
      return null;
    }
    final parts = token.split('.');
    if (parts.length < 2) {
      return null;
    }

    try {
      final normalized = base64Url.normalize(parts[1]);
      final payload = utf8.decode(base64Url.decode(normalized));
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic>
          ? decoded
          : (decoded as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  bool _matchesRedirectUri(Uri incoming, Uri expected) {
    return incoming.scheme == expected.scheme &&
        incoming.host == expected.host &&
        incoming.path == expected.path;
  }

  Future<String?> _backendBaseUrl() async {
    await QuranApiConfigService.instance.initialize();
    final baseUrl = QuranApiConfigService
        .instance
        .config
        .quranFoundationBackendBaseUrl
        .trim();
    if (baseUrl.isEmpty) {
      return null;
    }
    return baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
  }

  String _pkceChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  String _randomUrlSafeString(int length) {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var index = 0; index < length; index++) {
      buffer.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  String? _emptyToNull(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  void _setBusy(bool value) {
    _isBusy = value;
    notifyListeners();
  }
}
