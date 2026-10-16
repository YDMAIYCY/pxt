import 'package:flutter/material.dart';

import '../../common/app_assets.dart';
import '../../community/app_account_repository.dart';
import '../../community/cloud_backend.dart';
import '../../database/models/user_profile.dart';
import '../theme/app_theme.dart';
import 'home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.accounts, this.returnResult = false});

  final AppAccountRepository? accounts;
  final bool returnResult;

  static const routeName = '/login';

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final _accounts = widget.accounts ?? AppAccountRepository();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _nickname = TextEditingController();
  final _legacyUsername = TextEditingController();
  final _legacyPassword = TextEditingController();

  bool _initializing = true;
  bool _submitting = false;
  bool _register = false;
  bool _obscurePassword = true;
  bool _showLegacyRecovery = false;
  bool _legacyConsent = false;
  bool _canViewOffline = false;
  UserProfile? _legacyUser;
  String? _message;

  bool get _busy => _initializing || _submitting;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _nickname.dispose();
    _legacyUsername.dispose();
    _legacyPassword.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final offline = await _accounts.offlineUser();
      if (!mounted) return;
      setState(() => _canViewOffline = offline != null);
      final restored = await _accounts.restoreSession();
      if (!mounted) return;
      if (restored != null && !widget.returnResult) {
        _finish();
        return;
      }
      final legacy = await _accounts.legacyUser();
      if (!mounted) return;
      if (legacy != null) {
        setState(() {
          _selectLegacy(legacy);
          // An unlinked local account may always be opened offline: its learning
          // data stays usable whether or not the cloud is reachable.
          _canViewOffline = true;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = cloudError(error));
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  void _finish() {
    if (widget.returnResult) {
      Navigator.of(context).pop(true);
    } else {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(HomePage.routeName, (route) => false);
    }
  }

  void _selectLegacy(UserProfile profile) {
    _legacyUser = profile;
    _nickname.text = profile.primaryName;
    _legacyConsent = false;
    _register = true;
    _showLegacyRecovery = false;
  }

  void _useOtherAccount() {
    setState(() {
      _legacyUser = null;
      _legacyConsent = false;
      _register = false;
      _message = null;
      _email.clear();
      _password.clear();
      _nickname.clear();
    });
  }

  bool _validateEmail() {
    if (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())) {
      return true;
    }
    setState(() => _message = '请输入有效的邮箱地址');
    return false;
  }

  Future<void> _submit() async {
    if (_busy || !_validateEmail()) return;
    if (_password.text.isEmpty || (_register && _password.text.length < 8)) {
      setState(() {
        _message = _register ? '请设置至少 8 位密码' : '请输入密码';
      });
      return;
    }
    if (_register && _nickname.text.trim().isEmpty) {
      setState(() => _message = '请输入昵称');
      return;
    }
    if (_legacyUser != null && !_legacyConsent) {
      setState(() => _message = '请先确认使用此邮箱保留原有资料');
      return;
    }
    setState(() {
      _submitting = true;
      _message = null;
    });
    try {
      if (_register) {
        final profile = await _accounts.register(
          email: _email.text.trim(),
          password: _password.text,
          nickname: _nickname.text.trim(),
          legacyUserId: _legacyUser?.id,
        );
        if (!mounted) return;
        if (profile == null) {
          setState(() {
            _message = '注册成功，请到邮箱确认后返回登录';
            _register = false;
          });
          return;
        }
      } else {
        await _accounts.signIn(
          email: _email.text.trim(),
          password: _password.text,
          legacyUserId: _legacyUser?.id,
        );
        if (!mounted) return;
      }
      _finish();
    } catch (error) {
      if (mounted) setState(() => _message = cloudError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_busy || !_validateEmail()) return;
    setState(() {
      _submitting = true;
      _message = null;
    });
    try {
      await _accounts.resetPassword(_email.text.trim());
      if (mounted) setState(() => _message = '密码重置邮件已发送，请查看邮箱');
    } catch (error) {
      if (mounted) setState(() => _message = cloudError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _recoverLegacy() async {
    if (_busy) return;
    if (_legacyUsername.text.trim().isEmpty || _legacyPassword.text.isEmpty) {
      setState(() => _message = '请输入原用户名和原密码');
      return;
    }
    setState(() {
      _submitting = true;
      _message = null;
    });
    try {
      final profile = await _accounts.openLegacySpace(
        username: _legacyUsername.text.trim(),
        password: _legacyPassword.text,
      );
      if (!mounted) return;
      setState(() {
        if (profile == null) {
          _message = '原用户名或原密码不正确，请重试';
        } else {
          _selectLegacy(profile);
          _canViewOffline = false;
          _legacyPassword.clear();
          _message = '已找到原账号资料，请设置邮箱后继续';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _message = cloudError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _modeButton(String label, bool register) {
    return Expanded(
      child: OutlinedButton(
        key: ValueKey(register ? 'register-mode' : 'login-mode'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          backgroundColor: _register == register
              ? AppColors.primarySoft
              : Colors.white,
        ),
        onPressed: _busy
            ? null
            : () => setState(() {
                _register = register;
                _message = null;
              }),
        child: Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final legacy = _legacyUser;
    return Scaffold(
      appBar: widget.returnResult ? AppBar(title: const Text('账号登录')) : null,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primarySoft, Colors.white],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    boxShadow: AppShadows.cardMediumList,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 28,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        child: Container(
                          width: 72,
                          height: 72,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Image.asset(
                            AppAssets.logoIcon,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.auto_stories_rounded,
                                  size: 38,
                                  color: AppColors.primary,
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        legacy != null
                            ? '完善账号'
                            : _register
                            ? '注册智学帮'
                            : '欢迎登录智学帮',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.h1(context),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        legacy != null
                            ? '为「${legacy.primaryName}」设置邮箱，保留原有学习资料。也可使用已有邮箱登录。'
                            : '用邮箱继续你的学习旅程',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodySmall(context),
                      ),
                      if (_initializing) ...[
                        const SizedBox(height: 16),
                        const LinearProgressIndicator(),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          _modeButton('登录', false),
                          const SizedBox(width: 12),
                          _modeButton('注册', true),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (_register) ...[
                        TextField(
                          key: const ValueKey('nickname'),
                          controller: _nickname,
                          enabled: !_busy,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.nickname],
                          decoration: const InputDecoration(
                            labelText: '昵称',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextField(
                        key: const ValueKey('email'),
                        controller: _email,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                        onChanged: (_) {
                          if (_legacyConsent) {
                            setState(() => _legacyConsent = false);
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: '邮箱',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        key: const ValueKey('password'),
                        controller: _password,
                        enabled: !_busy,
                        obscureText: _obscurePassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: [
                          _register
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: '密码',
                          helperText: _register ? '至少 8 位' : null,
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                            onPressed: _busy
                                ? null
                                : () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                      ),
                      if (!_register)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            key: const ValueKey('forgot-password'),
                            onPressed: _busy ? null : _resetPassword,
                            child: const Text('忘记密码'),
                          ),
                        ),
                      if (legacy != null)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _legacyConsent,
                          onChanged: _busy
                              ? null
                              : (value) => setState(
                                  () => _legacyConsent = value ?? false,
                                ),
                          title: Text(
                            '我确认使用此邮箱完善「${legacy.primaryName}」的账号，并保留原有资料',
                            style: AppTextStyles.bodySmall(context),
                          ),
                        ),
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            _message!,
                            key: const ValueKey('account-message'),
                            style: AppTextStyles.bodySmall(context),
                          ),
                        ),
                      const SizedBox(height: 12),
                      FilledButton(
                        key: const ValueKey('submit-account'),
                        onPressed: _busy ? null : _submit,
                        child: Text(
                          _submitting
                              ? '正在提交…'
                              : _register
                              ? '注册'
                              : '登录',
                        ),
                      ),
                      if (legacy != null) ...[
                        TextButton(
                          onPressed: _busy ? null : _useOtherAccount,
                          child: const Text('使用其他账号登录'),
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _showLegacyRecovery = !_showLegacyRecovery;
                                  _message = null;
                                }),
                          child: const Text('找回本机原账号资料'),
                        ),
                        if (_showLegacyRecovery) ...[
                          const Text('验证原用户名和密码后，为原有资料设置邮箱。'),
                          const SizedBox(height: 14),
                          TextField(
                            key: const ValueKey('legacy-username'),
                            controller: _legacyUsername,
                            enabled: !_busy,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: '原用户名',
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            key: const ValueKey('legacy-password'),
                            controller: _legacyPassword,
                            enabled: !_busy,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            onSubmitted: (_) => _recoverLegacy(),
                            decoration: const InputDecoration(labelText: '原密码'),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _busy ? null : _recoverLegacy,
                            child: const Text('验证原账号资料'),
                          ),
                        ],
                      ],
                      if (_canViewOffline && !widget.returnResult)
                        TextButton(
                          onPressed: _busy ? null : _finish,
                          child: const Text('离线查看原有资料'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
