import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:komet/core/config/countries.dart';
import 'package:komet/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'code_confirmation_screen.dart';
import 'login_terms_sheet.dart';
import 'token_login_screen.dart';
import 'select_country_screen.dart';
import 'call_out_confirmation_screen.dart';
import 'phone_input_formatter.dart';
import 'proxy_settings_sheet.dart';
import 'server_settings_sheet.dart';
import '../profile/spoof_screen.dart';
import '../profile/debug_menu_screen.dart';
import '../digital_id/digital_id_web_screen.dart';
import '../../widgets/custom_notification.dart';
import '../../widgets/adaptive_shell.dart';
import '../../widgets/sheet_helpers.dart';
import '../../widgets/small_spinner.dart';
import '../../../backend/api.dart';
import '../../../backend/modules/account.dart';
import '../../../core/utils/logger.dart';
import '../../../core/protocol/packet.dart';
import '../../../main.dart';
import '../../../core/config/app_frost.dart';
import '../../../core/config/build_profile.dart';
import '../../../core/config/review_access.dart';
import '../../../core/config/app_shape.dart';

class LoginScreen extends StatefulWidget {
  final int? returnToAccountId;

  const LoginScreen({super.key, this.returnToAccountId});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  late CountryName _selectedCountry;
  bool _isPhoneValid = false;
  bool _isTOSRead = false;
  bool _submittingPhone = false;
  late final Future<void> _termsLoaded;
  late final TapGestureRecognizer _termsLink = TapGestureRecognizer()
    ..onTap = () => _showTOS();
  // #***! экспериментально: представляемся веб-клиентом, чтобы код пришёл по SMS
  late bool _alwaysSendSms = api.webHandshake;
  bool _switchingSmsMode = false;
  String? _phoneError;
  Timer? _phoneErrorTimer;
  int _logoTapCount = 0;
  Timer? _logoTapTimer;
  late SessionState _sessionState;
  StreamSubscription<SessionState>? _stateSub;

  bool get _isOnline => _sessionState == SessionState.online;

  @override
  void initState() {
    super.initState();
    _sessionState = api.state;
    logger.d(
      '[${api.debugTag}] экран входа: сессия=${api.state.name} '
      'всегда SMS=$_alwaysSendSms',
    );
    if (api.state == SessionState.disconnected) {
      // #***! экран входа по телефону — сокет без токена, прошлая версия
      unawaited(api.connect(authenticated: false, web: _alwaysSendSms));
    }
    _stateSub = api.stateStream.listen((state) {
      if (mounted) setState(() => _sessionState = state);
    });
    _selectedCountry = countriesByCode['RU'] ?? allCountries.first;
    _clampCountryToAllowed();
    _termsLoaded = _checkTOS();
  }

  // #***! режим зашит в рукопожатие, так что переподнимаем сессию целиком
  Future<void> _setAlwaysSendSms(bool value) async {
    if (_switchingSmsMode) return;
    setState(() {
      _alwaysSendSms = value;
      _switchingSmsMode = true;
    });
    logger.d('[${api.debugTag}] всегда SMS: переключаю на $value');
    try {
      await api.reconnectPreLogin(web: value);
      logger.d(
        '[${api.debugTag}] всегда SMS: сессия переподнята, '
        'состояние=${api.state.name}',
      );
    } catch (e) {
      logger.d('[${api.debugTag}] всегда SMS: переподнять не вышло: $e');
      if (!mounted) return;
      showCustomNotification(
        context,
        AppLocalizations.of(context)!.loginScreenReconnectFailed('$e'),
      );
    } finally {
      if (mounted) setState(() => _switchingSmsMode = false);
    }
  }

  Future<void> _ensurePreLoginSession() async {
    final fresh =
        !accountModule.isLoggedIn &&
        !api.isAuthenticatedHandshake &&
        api.webHandshake == _alwaysSendSms;
    logger.d(
      '[${api.debugTag}] pre-login сессия: '
      '${fresh ? 'годится' : 'переподнимаю'} '
      '(залогинен=${accountModule.isLoggedIn} '
      'боевой сокет=${api.isAuthenticatedHandshake} '
      'веб=${api.webHandshake} нужен веб=$_alwaysSendSms)',
    );
    if (fresh) return;
    await api.reconnectPreLogin(web: _alwaysSendSms);
  }

  // #***! предупреждение перед эксперим. SMS-входом: true=Принять, false=Отмена,
  // null=закрыли мимо (галочку не трогаем, но и дальше не идём)
  Future<bool?> _showExperimentalSmsWarning() {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: AppFrost.scrim(),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim1, anim2, child) {
        final cs = Theme.of(context).colorScheme;
        final l10n = AppLocalizations.of(context)!;
        final curve = Curves.easeOutQuart.transform(anim1.value);
        return Opacity(
          opacity: anim1.value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - curve)),
            child: Transform.scale(
              scale: 0.8 + (0.2 * curve),
              child: AlertDialog(
                backgroundColor: cs.surfaceContainerHigh,
                surfaceTintColor: Colors.transparent,
                shape: AppShape.dialogBorder,
                contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.loginScreenSmsWarningTitle,
                      style: TextStyle(
                        color: cs.error,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.loginScreenSmsWarningBody,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
                actions: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(
                          l10n.chatInfoActionCancel,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(
                          l10n.e2eeAccept,
                          style: TextStyle(
                            color: cs.primary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _onBackPressed() async {
    final returnId = widget.returnToAccountId;
    if (returnId != null) {
      await resetDigitalIdSession();
      try {
        await accountModule.switchAccount(returnId);
      } on AccountSessionLostException {
        if (!mounted) return;
        showCustomNotification(
          context,
          AppLocalizations.of(context)!.accountSessionLostTitle,
        );
        return;
      } catch (e) {
        logger.w('Возврат на аккаунт $returnId не удался: $e');
        if (!mounted) return;
        showCustomNotification(
          context,
          AppLocalizations.of(context)!.accountSwitchFailed,
        );
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AdaptiveShell()),
        (route) => false,
      );
      return;
    }
    if (Navigator.canPop(context)) Navigator.pop(context);
  }

  void _clampCountryToAllowed() {
    final allowed = api.registrationCountries;
    if (allowed.any((c) => c.code == _selectedCountry.code)) return;
    _selectedCountry = allowed.firstWhere(
      (c) => c.code == 'RU',
      orElse: () => allowed.first,
    );
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _phoneErrorTimer?.cancel();
    _logoTapTimer?.cancel();
    _phoneController.dispose();
    _termsLink.dispose();
    super.dispose();
  }

  Future<void> _checkTOS() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isTOSRead = prefs.getBool('IsReadeTOS') ?? false;
      });
    }
  }

  void _onLogoTap() {
    if (!BuildProfile.devTools) return;
    _logoTapTimer?.cancel();
    _logoTapTimer = Timer(const Duration(milliseconds: 600), () {
      _logoTapCount = 0;
    });
    _logoTapCount++;
    if (_logoTapCount >= 7) {
      _logoTapTimer?.cancel();
      _logoTapCount = 0;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const DebugMenuScreen()),
      );
    }
  }

  Future<void> _markTOSRead() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('IsReadeTOS', true);
    if (mounted) {
      setState(() {
        _isTOSRead = true;
      });
    }
  }

  void _showCountryPicker() async {
    final result = await Navigator.push<CountryName>(
      context,
      MaterialPageRoute(
        builder: (context) => SelectCountryScreen(
          selectedCountry: _selectedCountry,
          countries: api.registrationCountries,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _selectedCountry = result;
        _phoneController.clear();
        _isPhoneValid = false;
      });
    }
  }

  String _countryDisplayName(CountryName country) {
    final lang = Localizations.localeOf(context).languageCode;
    return country.displayName(lang);
  }

  String _phoneMaskHint(CountryName country) {
    return country.phoneMask.replaceAll('#', '0');
  }

  void _showLanguagePicker() {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final appContext = context;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: cs.surfaceContainerHigh,
      shape: kSheetShape,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 24.0,
              horizontal: 16.0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 8),
                  child: Text(
                    l10n.loginLanguage,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ListTile(
                  title: Text(
                    l10n.languageNameRu,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    KometApp.stateOf(appContext)
                        ?.applyLocale(const Locale('ru'));
                  },
                ),
                ListTile(
                  title: Text(
                    l10n.languageNameEn,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    KometApp.stateOf(appContext)
                        ?.applyLocale(const Locale('en'));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _showTOS({String? phoneNumber}) async {
    await _termsLoaded;
    if (!mounted) return false;
    FocusManager.instance.primaryFocus?.unfocus();
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: kSheetShape,
      builder: (_) =>
          LoginTermsSheet(accepted: _isTOSRead, phoneNumber: phoneNumber),
    );
    if (!mounted || accepted != true) return false;
    if (!_isTOSRead) await _markTOSRead();
    return mounted;
  }

  void _showPhoneError(String message) {
    _phoneErrorTimer?.cancel();
    setState(() => _phoneError = message);
    _phoneErrorTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _phoneError = null);
    });
  }

  Future<bool?> _showPhoneConfirmationDialog(String phoneNumber) {
    final l10n = AppLocalizations.of(context)!;

    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: AppFrost.scrim(),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim1, anim2, child) {
        final cs = Theme.of(context).colorScheme;
        final curve = Curves.easeOutQuart.transform(anim1.value);
        return Opacity(
          opacity: anim1.value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - curve)),
            child: Transform.scale(
              scale: 0.8 + (0.2 * curve),
              child: AlertDialog(
                backgroundColor: cs.surfaceContainerHigh,
                surfaceTintColor: Colors.transparent,
                shape: AppShape.dialogBorder,
                contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.loginConfirmPhoneTitle,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      phoneNumber,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                actions: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          l10n.loginEdit,
                          style: TextStyle(
                            color: cs.primary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(
                          l10n.loginDone,
                          style: TextStyle(
                            color: cs.primary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _validateAndSubmit() async {
    if (_submittingPhone || !_isPhoneValid) return;
    final country = _selectedCountry;
    final formattedPhone = _phoneController.text;
    final phoneNumber = '${country.phoneCode} $formattedPhone';
    final rawPhone = '${country.phoneCode}$formattedPhone';
    final l10n = AppLocalizations.of(context)!;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _submittingPhone = true);

    try {
      await _termsLoaded;
      if (!mounted) return;
      final confirmed = _isTOSRead
          ? await _showPhoneConfirmationDialog(phoneNumber)
          : await _showTOS(phoneNumber: phoneNumber);
      if (!mounted || confirmed != true) return;

      if (!_isOnline) {
        _showPhoneError(l10n.loginScreenOfflineWait);
        return;
      }

      if (ReviewAccess.matchesPhone(rawPhone)) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => CodeConfirmationScreen.review(
              phoneNumber: phoneNumber,
              rawPhone: rawPhone,
              countryCode: country.code,
            ),
          ),
        );
        return;
      }

      if (_alwaysSendSms) {
        final choice = await _showExperimentalSmsWarning();
        if (!mounted) return;
        logger.d('всегда SMS: предупреждение — $choice');
        if (choice == false) await _setAlwaysSendSms(false);
        if (choice != true) return;
      }

      await _ensurePreLoginSession();
      if (!mounted) return;
      final result = await accountModule.requestCode(rawPhone);
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      final callOut = result.callOut;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => callOut == null
              ? CodeConfirmationScreen(
                  phoneNumber: phoneNumber,
                  rawPhone: rawPhone,
                  countryCode: country.code,
                  token: result.token,
                )
              : CallOutConfirmationScreen(
                  phoneNumber: phoneNumber,
                  rawPhone: rawPhone,
                  countryCode: country.code,
                  callOut: callOut,
                ),
        ),
      );
    } catch (e, st) {
      logger.d('[${api.debugTag}] запрос кода упал: $e\n$st');
      if (!mounted) return;
      _showPhoneError(
        isSessionStateError(e) ? l10n.loginScreenOfflineRetry : e.toString(),
      );
    } finally {
      if (mounted) setState(() => _submittingPhone = false);
    }
  }

  void _notifyConnecting() {
    showCustomNotification(
      context,
      AppLocalizations.of(context)!.loginScreenConnecting,
    );
  }

  void _showServerSettingsSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surfaceContainerHigh,
      shape: kSheetShape,
      builder: (_) {
        return SafeArea(child: const ServerSettingsSheet());
      },
    );
  }

  void _showProxySettingsSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surfaceContainerHigh,
      shape: kSheetShape,
      builder: (_) {
        return SafeArea(child: const ProxySettingsSheet());
      },
    );
  }

  void _showSecurityOptions(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surfaceContainerHigh,
      shape: kSheetShape,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 24.0,
              horizontal: 16.0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (BuildProfile.spoofUi)
                  ListTile(
                    leading: Icon(Symbols.security, color: cs.onSurface),
                    title: Text(
                      l10n.loginSpoofRedacted,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SpoofScreen(),
                        ),
                      );
                    },
                  ),
                ListTile(
                  leading: Icon(Symbols.vpn_lock, color: cs.onSurface),
                  title: Text(
                    l10n.loginProxy,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showProxySettingsSheet(context);
                  },
                ),
                ListTile(
                  leading: Icon(Symbols.dns, color: cs.onSurface),
                  title: Text(
                    l10n.loginChangeServer,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showServerSettingsSheet(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showOtherLoginMethods(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surfaceContainerHigh,
      shape: kSheetShape,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 24.0,
              horizontal: 16.0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (BuildProfile.qrLogin)
                  ListTile(
                    leading: Icon(Symbols.qr_code_2, color: cs.onSurface),
                    title: Text(
                      l10n.loginSignInWithQr,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                    },
                  ),
                if (BuildProfile.tokenLogin)
                  ListTile(
                    leading: Icon(Symbols.key, color: cs.onSurface),
                    title: Text(
                      l10n.loginSignInWithToken,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TokenLoginScreen(
                            returnToAccountId: widget.returnToAccountId,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: cs.surface,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 44),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (Navigator.canPop(context) ||
                                  widget.returnToAccountId != null)
                                IconButton(
                                  onPressed: _onBackPressed,
                                  icon: Icon(
                                    Symbols.arrow_back,
                                    color: cs.onSurfaceVariant,
                                    weight: 400,
                                  ),
                                )
                              else
                                const SizedBox.shrink(),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    onPressed: () =>
                                        _showSecurityOptions(context),
                                    icon: Icon(
                                      Symbols.admin_panel_settings,
                                      color: cs.onSurfaceVariant,
                                      weight: 400,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _showLanguagePicker,
                                    icon: Icon(
                                      Symbols.language,
                                      color: cs.onSurfaceVariant,
                                      weight: 400,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 74),
                          Center(
                            child: Column(
                              children: [
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _onLogoTap,
                                  child: Image.asset(
                                    'assets/komet.png',
                                    height: 80,
                                    color: cs.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  l10n.loginTitle,
                                  style: TextStyle(
                                    color: cs.onSurface,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  l10n.loginSubtitle,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w400,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 48),
                          InkWell(
                            onTap: _showCountryPicker,
                            borderRadius: BorderRadius.circular(50),
                            child: _buildInputField(
                              label: l10n.loginCountry,
                              content: Row(
                                children: [
                                  Text(
                                    _countryDisplayName(_selectedCountry),
                                    style: TextStyle(
                                      color: cs.onSurface,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  const Spacer(),
                                  Icon(
                                    Symbols.keyboard_arrow_down,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 40),
                          _buildInputField(
                            label: l10n.loginPhoneNumber,
                            content: Row(
                              children: [
                                Text(
                                  _selectedCountry.phoneCode,
                                  style: TextStyle(
                                    color: cs.onSurface,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  width: 1,
                                  height: 24,
                                  color: cs.outlineVariant,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    key: ValueKey(_selectedCountry.code),
                                    controller: _phoneController,
                                    keyboardType: TextInputType.phone,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      PhoneInputFormatter(_selectedCountry),
                                    ],
                                    style: TextStyle(
                                      color: cs.onSurface,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: _phoneMaskHint(
                                        _selectedCountry,
                                      ),
                                      hintStyle: TextStyle(
                                        color: cs.outline,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w400,
                                      ),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    onChanged: (value) {
                                      final digits = value.replaceAll(
                                        RegExp(r'\D'),
                                        '',
                                      );
                                      setState(() {
                                        _isPhoneValid =
                                            digits.length ==
                                            _selectedCountry.phoneDigits;
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.topLeft,
                            child: _phoneError != null
                                ? Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      _phoneError!,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: _switchingSmsMode
                                ? null
                                : () => _setAlwaysSendSms(!_alwaysSendSms),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      l10n.loginScreenAlwaysSendSms,
                                      style: TextStyle(
                                        color: cs.onSurface,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w400,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Switch(
                                    value: _alwaysSendSms,
                                    onChanged: _switchingSmsMode
                                        ? null
                                        : _setAlwaysSendSms,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (BuildProfile.qrLogin || BuildProfile.tokenLogin)
                            TextButton(
                              onPressed: () => _showOtherLoginMethods(context),
                              child: Text(
                                l10n.loginOtherSignInMethods,
                                style: TextStyle(
                                  color: cs.primary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          const Spacer(),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 24.0),
                                  child: RichText(
                                    text: TextSpan(
                                      style: TextStyle(
                                        color: cs.onSurface,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        height: 1.4,
                                      ),
                                      children: [
                                        TextSpan(
                                          text: l10n.loginTermsIntro,
                                          style: TextStyle(
                                            color: cs.onSurface,
                                            fontSize: 14,
                                            height: 1.4,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                        TextSpan(
                                          text: l10n.loginTermsLink,
                                          style: TextStyle(
                                            color: cs.primary,
                                            fontSize: 14,
                                            height: 1.4,
                                            fontWeight: FontWeight.w400,
                                          ),
                                          recognizer: _submittingPhone
                                              ? null
                                              : _termsLink,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16.0),
                                child: FloatingActionButton(
                                  onPressed: !_isPhoneValid || _submittingPhone
                                      ? null
                                      : (_isOnline
                                            ? _validateAndSubmit
                                            : _notifyConnecting),
                                  backgroundColor: _isPhoneValid
                                      ? cs.primaryContainer
                                      : cs.surfaceContainerHighest,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(50),
                                  ),
                                  child:
                                      _submittingPhone ||
                                          (_isPhoneValid && !_isOnline)
                                      ? SmallSpinner(
                                          size: 24,
                                          color: cs.onPrimaryContainer,
                                        )
                                      : Icon(
                                          Symbols.arrow_forward,
                                          color: _isPhoneValid
                                              ? cs.onPrimaryContainer
                                              : cs.onSurfaceVariant,
                                        ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({required String label, required Widget content}) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: double.infinity,
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(color: cs.primary, width: 1.5),
                borderRadius: BorderRadius.circular(50),
              ),
              child: content,
            ),
            Positioned(
              top: -10,
              left: 20,
              child: Container(
                color: cs.surface,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  label,
                  style: TextStyle(
                    color: cs.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
