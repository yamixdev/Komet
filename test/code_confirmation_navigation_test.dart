import 'package:flutter_test/flutter_test.dart';
import 'package:komet/frontend/screens/auth/code_confirmation_screen.dart';
import 'package:komet/l10n/app_localization_delegates.dart';
import 'package:komet/l10n/app_localizations.dart';
import 'package:komet/main.dart' show api;
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

const _number = '+1 202 555 0101';

Future<void> _openCodeEntry(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 750);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: appLocalizationDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const CodeConfirmationScreen.review(
                  phoneNumber: _number,
                  rawPhone: '+12025550101',
                  countryCode: 'US',
                ),
              ),
            ),
            child: const Text('Open code entry'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open code entry'));
  await tester.pumpAndSettle();
  tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  await tester.pumpAndSettle();
  expect(find.text(_number), findsOneWidget);
  expect(
    tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
    isTrue,
  );
}

void main() {
  setUpAll(() => api.state);

  testWidgets('system back dismisses a visible keyboard before the SMS route', (
    tester,
  ) async {
    await _openCodeEntry(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(_number), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isFalse,
    );

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Open code entry'), findsOneWidget);
    expect(find.text(_number), findsNothing);
  });

  testWidgets('toolbar back also hides the keyboard before leaving SMS', (
    tester,
  ) async {
    await _openCodeEntry(tester);
    await tester.tap(find.byIcon(Symbols.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text(_number), findsOneWidget);

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Symbols.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Open code entry'), findsOneWidget);
  });

  testWidgets('SMS survives backgrounding and accepts back after IME closes', (
    tester,
  ) async {
    await _openCodeEntry(tester);
    await tester.enterText(find.byType(EditableText), '123');
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.view.resetViewInsets();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    final codeField = tester.widget<EditableText>(find.byType(EditableText));
    expect(codeField.controller.text, '123');
    expect(find.text(_number), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Open code entry'), findsOneWidget);
  });
}
