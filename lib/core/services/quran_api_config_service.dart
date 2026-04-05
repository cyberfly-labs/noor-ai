import 'package:shared_preferences/shared_preferences.dart';

enum QuranApiProvider {
  alQuranCloud,
  quranFoundation,
}

class QuranApiConfig {
  const QuranApiConfig({
    required this.provider,
    required this.quranFoundationClientId,
    required this.quranFoundationAuthToken,
    required this.quranFoundationBackendBaseUrl,
    required this.usePrelive,
    required this.translationId,
    required this.recitationId,
  });

  final QuranApiProvider provider;
  final String quranFoundationClientId;
  final String quranFoundationAuthToken;
  final String quranFoundationBackendBaseUrl;
  final bool usePrelive;
  final int translationId;
  final int recitationId;

  static const _defaultTranslationId = 131;
  static const _defaultRecitationId = 7;
  static const defaultBackendBaseUrl = 'https://noor-ai-5zjn.onrender.com';

  static QuranApiConfig fromEnvironment() {
    final providerValue = const String.fromEnvironment(
      'QURAN_API_PROVIDER',
      defaultValue: 'alquran',
    ).toLowerCase();

    return QuranApiConfig(
      provider: providerValue == 'qf' || providerValue == 'quranfoundation'
          ? QuranApiProvider.quranFoundation
          : QuranApiProvider.alQuranCloud,
      quranFoundationClientId: const String.fromEnvironment(
        'QF_CLIENT_ID',
        defaultValue: '',
      ),
      quranFoundationAuthToken: const String.fromEnvironment(
        'QF_AUTH_TOKEN',
        defaultValue: '',
      ),
      quranFoundationBackendBaseUrl: const String.fromEnvironment(
        'QF_BACKEND_BASE_URL',
        defaultValue: defaultBackendBaseUrl,
      ),
      usePrelive: const String.fromEnvironment(
            'QF_USE_PRELIVE',
            defaultValue: 'false',
          ) ==
          'true',
      translationId: int.tryParse(const String.fromEnvironment(
            'QF_TRANSLATION_ID',
            defaultValue: '$_defaultTranslationId',
          )) ??
          _defaultTranslationId,
      recitationId: int.tryParse(const String.fromEnvironment(
            'QF_RECITATION_ID',
            defaultValue: '$_defaultRecitationId',
          )) ??
          _defaultRecitationId,
    );
  }

  bool get hasQuranFoundationCredentials =>
      quranFoundationClientId.trim().isNotEmpty &&
      quranFoundationAuthToken.trim().isNotEmpty;

  bool get hasQuranFoundationBackend =>
      quranFoundationBackendBaseUrl.trim().isNotEmpty;

  bool get usesQuranFoundation =>
      provider == QuranApiProvider.quranFoundation &&
      (hasQuranFoundationBackend || hasQuranFoundationCredentials);

  bool get usesQuranFoundationBackend =>
      provider == QuranApiProvider.quranFoundation && hasQuranFoundationBackend;

  String get _normalizedBackendBaseUrl {
    final trimmed = quranFoundationBackendBaseUrl.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }

  String _backendApiBase(String suffix) {
    final base = _normalizedBackendBaseUrl;
    if (base.isEmpty) {
      return '';
    }
    return base.endsWith(suffix) ? base : '$base$suffix';
  }

  String get quranFoundationBaseUrl => usesQuranFoundationBackend
      ? _backendApiBase('/api/qf')
      : usePrelive
          ? 'https://apis-prelive.quran.foundation/content/api/v4'
          : 'https://apis.quran.foundation/content/api/v4';

  String get quranFoundationSearchBaseUrl => usesQuranFoundationBackend
      ? _backendApiBase('/api/qf')
      : usePrelive
          ? 'https://apis-prelive.quran.foundation/search'
          : 'https://apis.quran.foundation/search';

  String get providerLabel {
    if (provider == QuranApiProvider.quranFoundation) {
      return usePrelive
          ? 'Local Quran DB + Quran Foundation Audio (Prelive)'
          : 'Local Quran DB + Quran Foundation Audio';
    }
    return 'Local Quran DB + Audio API';
  }

  QuranApiConfig copyWith({
    QuranApiProvider? provider,
    String? quranFoundationClientId,
    String? quranFoundationAuthToken,
    String? quranFoundationBackendBaseUrl,
    bool? usePrelive,
    int? translationId,
    int? recitationId,
  }) {
    return QuranApiConfig(
      provider: provider ?? this.provider,
      quranFoundationClientId:
          quranFoundationClientId ?? this.quranFoundationClientId,
      quranFoundationAuthToken:
          quranFoundationAuthToken ?? this.quranFoundationAuthToken,
      quranFoundationBackendBaseUrl:
          quranFoundationBackendBaseUrl ?? this.quranFoundationBackendBaseUrl,
      usePrelive: usePrelive ?? this.usePrelive,
      translationId: translationId ?? this.translationId,
      recitationId: recitationId ?? this.recitationId,
    );
  }
}

class QuranApiConfigService {
  QuranApiConfigService._();
  static final QuranApiConfigService instance = QuranApiConfigService._();

  static const _providerKey = 'quran_api_provider';
  static const _clientIdKey = 'qf_client_id';
  static const _authTokenKey = 'qf_auth_token';
  static const _backendBaseUrlKey = 'qf_backend_base_url';
  static const _usePreliveKey = 'qf_use_prelive';
  static const _translationIdKey = 'qf_translation_id';
  static const _recitationIdKey = 'qf_recitation_id';

  SharedPreferences? _prefs;
  QuranApiConfig _config = QuranApiConfig.fromEnvironment();

  QuranApiConfig get config => _config;

  Future<void> initialize() async {
    if (_prefs != null) {
      return;
    }

    _prefs = await SharedPreferences.getInstance();
    final prefs = _prefs!;
    final envConfig = QuranApiConfig.fromEnvironment();

    _config = envConfig.copyWith(
      provider: _providerFromString(prefs.getString(_providerKey)) ??
          envConfig.provider,
      quranFoundationClientId:
          prefs.getString(_clientIdKey) ?? envConfig.quranFoundationClientId,
      quranFoundationAuthToken:
          prefs.getString(_authTokenKey) ?? envConfig.quranFoundationAuthToken,
      quranFoundationBackendBaseUrl:
        _emptyToNull(prefs.getString(_backendBaseUrlKey)) ??
          envConfig.quranFoundationBackendBaseUrl,
      usePrelive: prefs.getBool(_usePreliveKey) ?? envConfig.usePrelive,
      translationId:
          prefs.getInt(_translationIdKey) ?? envConfig.translationId,
      recitationId:
          prefs.getInt(_recitationIdKey) ?? envConfig.recitationId,
    );
  }

  Future<void> saveConfig(QuranApiConfig config) async {
    await initialize();
    final prefs = _prefs!;
    _config = config;

    await prefs.setString(_providerKey, _providerToString(config.provider));
    await prefs.setString(_clientIdKey, config.quranFoundationClientId);
    await prefs.setString(_authTokenKey, config.quranFoundationAuthToken);
    await prefs.setString(
      _backendBaseUrlKey,
      config.quranFoundationBackendBaseUrl,
    );
    await prefs.setBool(_usePreliveKey, config.usePrelive);
    await prefs.setInt(_translationIdKey, config.translationId);
    await prefs.setInt(_recitationIdKey, config.recitationId);
  }

  Future<void> saveQuranFoundationConfig({
    required String clientId,
    required String authToken,
    String? backendBaseUrl,
    required bool usePrelive,
    required int translationId,
    required int recitationId,
    QuranApiProvider provider = QuranApiProvider.quranFoundation,
  }) async {
    await saveConfig(_config.copyWith(
      provider: provider,
      quranFoundationClientId: clientId.trim(),
      quranFoundationAuthToken: authToken.trim(),
      quranFoundationBackendBaseUrl:
          _emptyToNull(backendBaseUrl)?.trim() ??
          _config.quranFoundationBackendBaseUrl,
      usePrelive: usePrelive,
      translationId: translationId,
      recitationId: recitationId,
    ));
  }

  Future<void> setProvider(QuranApiProvider provider) async {
    await saveConfig(_config.copyWith(provider: provider));
  }

  Future<void> clearQuranFoundationCredentials() async {
    await initialize();
    final envConfig = QuranApiConfig.fromEnvironment();

    await saveConfig(_config.copyWith(
      provider: envConfig.provider,
      quranFoundationClientId: envConfig.quranFoundationClientId,
      quranFoundationAuthToken: envConfig.quranFoundationAuthToken,
      quranFoundationBackendBaseUrl: envConfig.quranFoundationBackendBaseUrl,
      usePrelive: envConfig.usePrelive,
      translationId: envConfig.translationId,
      recitationId: envConfig.recitationId,
    ));
  }

  QuranApiProvider? _providerFromString(String? value) {
    switch (value) {
      case 'quran_foundation':
        return QuranApiProvider.quranFoundation;
      case 'alquran_cloud':
        return QuranApiProvider.alQuranCloud;
      default:
        return null;
    }
  }

  String _providerToString(QuranApiProvider provider) {
    switch (provider) {
      case QuranApiProvider.quranFoundation:
        return 'quran_foundation';
      case QuranApiProvider.alQuranCloud:
        return 'alquran_cloud';
    }
  }

  String? _emptyToNull(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }
}