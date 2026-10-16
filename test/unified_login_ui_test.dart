import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/community/app_account_repository.dart';
import 'package:pxt1/community/cloud_backend.dart';
import 'package:pxt1/database/models/user_profile.dart';
import 'package:pxt1/ui/pages/home_page.dart';
import 'package:pxt1/ui/pages/login_page.dart';
import 'package:pxt1/ui/theme/app_theme.dart';

const _profile = UserProfile(
  id: 42,
  username: 'old-student',
  displayName: '原来的同学',
  bio: '',
  gender: '保密',
  avatarStyle: ProfilePresetIds.defaultAvatarStyle,
  backgroundStyle: ProfilePresetIds.defaultBackgroundStyle,
);

// All repository operations are overridden; no database or network is opened.
class _FakeAccounts extends AppAccountRepository {
  UserProfile? restored;
  UserProfile? legacy;
  UserProfile? recovered;
  UserProfile? registered;
  Object? signInError;
  Object? restoreError;
  Future<UserProfile>? pendingSignIn;
  final signIns = <Map<String, Object?>>[];
  final registrations = <Map<String, Object?>>[];
  final recoveries = <Map<String, String>>[];
  final resets = <String>[];

  @override
  Future<UserProfile?> restoreSession() async {
    if (restoreError != null) throw restoreError!;
    return restored;
  }

  @override
  Future<UserProfile?> legacyUser() async => legacy;

  @override
  Future<UserProfile> signIn({
    required String email,
    required String password,
    int? legacyUserId,
  }) async {
    signIns.add({
      'email': email,
      'password': password,
      'legacyUserId': legacyUserId,
    });
    if (signInError != null) throw signInError!;
    return await (pendingSignIn ?? Future.value(_profile));
  }

  @override
  Future<UserProfile?> register({
    required String email,
    required String password,
    required String nickname,
    int? legacyUserId,
  }) async {
    registrations.add({
      'email': email,
      'password': password,
      'nickname': nickname,
      'legacyUserId': legacyUserId,
    });
    return registered;
  }

  @override
  Future<void> resetPassword(String email) async => resets.add(email);

  @override
  Future<UserProfile?> openLegacySpace({
    required String username,
    required String password,
  }) async {
    recoveries.add({'username': username, 'password': password});
    return recovered;
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _pumpLogin(
  WidgetTester tester,
  _FakeAccounts accounts, {
  bool returnResult = false,
  ValueChanged<bool?>? onResult,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      routes: {HomePage.routeName: (_) => const Scaffold(body: Text('首页占位'))},
      home: returnResult
          ? Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    final result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) =>
                            LoginPage(accounts: accounts, returnResult: true),
                      ),
                    );
                    onResult?.call(result);
                  },
                  child: const Text('打开登录页'),
                ),
              ),
            )
          : LoginPage(accounts: accounts),
    ),
  );
  await tester.pumpAndSettle();
  if (returnResult) await _tap(tester, find.text('打开登录页'));
}

Future<void> _enterCredentials(WidgetTester tester) async {
  await tester.enterText(find.byKey(const ValueKey('email')), 'me@example.com');
  await tester.enterText(find.byKey(const ValueKey('password')), 'password123');
}

void main() {
  testWidgets('登录只展示单一邮箱密码表单，找回资料默认折叠', (tester) async {
    await _pumpLogin(tester, _FakeAccounts());

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byKey(const ValueKey('email')), findsOneWidget);
    expect(find.byKey(const ValueKey('password')), findsOneWidget);
    expect(find.byKey(const ValueKey('nickname')), findsNothing);
    expect(find.byKey(const ValueKey('legacy-username')), findsNothing);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.text('找回本机原账号资料'), findsOneWidget);
    expect(find.textContaining(RegExp('云端|关联|绑定')), findsNothing);
    expect(find.text('使用云端邮箱账号登录'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('注册显示昵称并提交邮箱，等待邮箱确认时留在登录页', (tester) async {
    final accounts = _FakeAccounts();
    await _pumpLogin(tester, accounts);
    await _tap(tester, find.byKey(const ValueKey('register-mode')));

    expect(find.byType(TextField), findsNWidgets(3));
    await tester.enterText(find.byKey(const ValueKey('nickname')), ' 新同学 ');
    await tester.enterText(
      find.byKey(const ValueKey('email')),
      ' me@example.com ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('password')),
      'password123',
    );
    await _tap(tester, find.byKey(const ValueKey('submit-account')));

    expect(accounts.registrations.single, {
      'email': 'me@example.com',
      'password': 'password123',
      'nickname': '新同学',
      'legacyUserId': null,
    });
    expect(find.text('注册成功，请到邮箱确认后返回登录'), findsOneWidget);
    expect(find.byKey(const ValueKey('nickname')), findsNothing);
    expect(find.text('首页占位'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('email')))
          .controller!
          .text,
      ' me@example.com ',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('旧会话需明确确认，邮箱确认后继续使用原资料编号登录', (tester) async {
    final accounts = _FakeAccounts()..legacy = _profile;
    await _pumpLogin(tester, accounts);

    expect(find.text('完善账号'), findsOneWidget);
    expect(find.text('离线查看原有资料'), findsOneWidget);
    await _enterCredentials(tester);
    await _tap(tester, find.byKey(const ValueKey('submit-account')));
    expect(accounts.registrations, isEmpty);
    expect(find.text('请先确认使用此邮箱保留原有资料'), findsOneWidget);

    await _tap(tester, find.byType(CheckboxListTile));
    await _tap(tester, find.byKey(const ValueKey('submit-account')));
    expect(accounts.registrations.single['legacyUserId'], _profile.id);
    expect(find.text('注册成功，请到邮箱确认后返回登录'), findsOneWidget);
    expect(find.text('完善账号'), findsOneWidget);
    expect(accounts.legacy, same(_profile));

    await _tap(tester, find.byKey(const ValueKey('submit-account')));
    expect(accounts.signIns.single['legacyUserId'], _profile.id);
    expect(find.text('首页占位'), findsOneWidget);
  });

  testWidgets('使用其他账号登录仅清除界面选择，邮箱登录不携带旧编号', (tester) async {
    final accounts = _FakeAccounts()..legacy = _profile;
    await _pumpLogin(tester, accounts);
    await _tap(tester, find.text('使用其他账号登录'));

    expect(find.text('完善账号'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.byKey(const ValueKey('nickname')), findsNothing);
    expect(accounts.legacy, same(_profile));
    await _enterCredentials(tester);
    await _tap(tester, find.byKey(const ValueKey('submit-account')));

    expect(accounts.signIns.single['legacyUserId'], isNull);
    expect(accounts.legacy, same(_profile));
    expect(find.text('首页占位'), findsOneWidget);
  });

  testWidgets('修改邮箱后重新要求旧资料确认', (tester) async {
    final accounts = _FakeAccounts()..legacy = _profile;
    await _pumpLogin(tester, accounts);
    await _enterCredentials(tester);
    await _tap(tester, find.byType(CheckboxListTile));
    await tester.enterText(
      find.byKey(const ValueKey('email')),
      'other@example.com',
    );
    await _tap(tester, find.byKey(const ValueKey('submit-account')));

    expect(accounts.registrations, isEmpty);
    expect(find.text('请先确认使用此邮箱保留原有资料'), findsOneWidget);
  });

  testWidgets('找回原账号只进入完善表单，不直接进入首页', (tester) async {
    final accounts = _FakeAccounts()..recovered = _profile;
    await _pumpLogin(tester, accounts);
    await _tap(tester, find.text('找回本机原账号资料'));
    await tester.enterText(
      find.byKey(const ValueKey('legacy-username')),
      ' old-student ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('legacy-password')),
      'oldpass',
    );
    await _tap(tester, find.text('验证原账号资料'));

    expect(accounts.recoveries.single, {
      'username': 'old-student',
      'password': 'oldpass',
    });
    expect(find.text('完善账号'), findsOneWidget);
    expect(find.byKey(const ValueKey('nickname')), findsOneWidget);
    expect(find.byKey(const ValueKey('legacy-username')), findsNothing);
    expect(find.text('离线查看原有资料'), findsNothing);
    expect(find.text('首页占位'), findsNothing);
    expect(accounts.signIns, isEmpty);
    expect(accounts.registrations, isEmpty);

    await _enterCredentials(tester);
    await _tap(tester, find.byType(CheckboxListTile));
    await _tap(tester, find.byKey(const ValueKey('submit-account')));
    expect(accounts.registrations.single['legacyUserId'], _profile.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('原账号验证失败保留找回表单', (tester) async {
    final accounts = _FakeAccounts();
    await _pumpLogin(tester, accounts);
    await _tap(tester, find.text('找回本机原账号资料'));
    await tester.enterText(
      find.byKey(const ValueKey('legacy-username')),
      'wrong',
    );
    await tester.enterText(
      find.byKey(const ValueKey('legacy-password')),
      'wrong',
    );
    await _tap(tester, find.text('验证原账号资料'));

    expect(find.text('原用户名或原密码不正确，请重试'), findsOneWidget);
    expect(find.byKey(const ValueKey('legacy-username')), findsOneWidget);
    expect(find.text('完善账号'), findsNothing);
    expect(find.text('首页占位'), findsNothing);
  });

  testWidgets('未升级会话可以离线查看，保留旧账号数据', (tester) async {
    final accounts = _FakeAccounts()..legacy = _profile;
    await _pumpLogin(tester, accounts);
    await _tap(tester, find.text('离线查看原有资料'));

    expect(find.text('首页占位'), findsOneWidget);
    expect(accounts.legacy, same(_profile));
    expect(accounts.signIns, isEmpty);
    expect(accounts.registrations, isEmpty);
  });

  testWidgets('有效会话自动进入首页并清空返回栈', (tester) async {
    await _pumpLogin(tester, _FakeAccounts()..restored = _profile);

    expect(find.text('首页占位'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    expect(Navigator.of(tester.element(find.text('首页占位'))).canPop(), isFalse);
  });

  testWidgets('returnResult 初始化不自动导航，成功登录返回 true', (tester) async {
    bool? result;
    final accounts = _FakeAccounts()..restored = _profile;
    await _pumpLogin(
      tester,
      accounts,
      returnResult: true,
      onResult: (value) => result = value,
    );

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('首页占位'), findsNothing);
    expect(result, isNull);
    await _enterCredentials(tester);
    await _tap(tester, find.byKey(const ValueKey('submit-account')));

    expect(result, isTrue);
    expect(find.byType(LoginPage), findsNothing);
    expect(find.text('打开登录页'), findsOneWidget);
    expect(find.text('首页占位'), findsNothing);
  });

  testWidgets('returnResult 显示待完善资料，注册成功返回 true', (tester) async {
    bool? result;
    final accounts = _FakeAccounts()
      ..legacy = _profile
      ..registered = _profile;
    await _pumpLogin(
      tester,
      accounts,
      returnResult: true,
      onResult: (value) => result = value,
    );

    expect(find.text('完善账号'), findsOneWidget);
    expect(find.text('离线查看原有资料'), findsNothing);
    await _enterCredentials(tester);
    await _tap(tester, find.byType(CheckboxListTile));
    await _tap(tester, find.byKey(const ValueKey('submit-account')));

    expect(result, isTrue);
    expect(accounts.registrations.single['legacyUserId'], _profile.id);
    expect(find.text('首页占位'), findsNothing);
  });

  testWidgets('忘记密码使用当前邮箱，服务错误显示安全反馈且可重试', (tester) async {
    final accounts = _FakeAccounts()
      ..signInError = const CloudFailure('邮箱或密码不正确');
    await _pumpLogin(tester, accounts);
    await _enterCredentials(tester);
    await _tap(tester, find.text('忘记密码'));

    expect(accounts.resets, ['me@example.com']);
    expect(find.text('密码重置邮件已发送，请查看邮箱'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('submit-account')));
    expect(find.text('邮箱或密码不正确'), findsOneWidget);
    expect(find.text('首页占位'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('submit-account')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('恢复会话失败显示安全反馈，仍可输入邮箱登录', (tester) async {
    await _pumpLogin(
      tester,
      _FakeAccounts()..restoreError = const CloudFailure('连接暂不可用，请重试'),
    );

    expect(find.text('连接暂不可用，请重试'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('email'))).enabled,
      isTrue,
    );
    expect(find.text('首页占位'), findsNothing);
  });

  testWidgets('请求期间禁用提交和切换，避免重复请求', (tester) async {
    final pending = Completer<UserProfile>();
    final accounts = _FakeAccounts()..pendingSignIn = pending.future;
    await _pumpLogin(tester, accounts);
    await _enterCredentials(tester);
    await _tap(tester, find.byKey(const ValueKey('submit-account')));

    expect(accounts.signIns, hasLength(1));
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('email'))).enabled,
      isFalse,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('register-mode')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('submit-account')))
          .onPressed,
      isNull,
    );
    pending.complete(_profile);
    await tester.pumpAndSettle();
    expect(find.text('首页占位'), findsOneWidget);
  });
}
