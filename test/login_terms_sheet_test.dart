import 'package:flutter_test/flutter_test.dart';
import 'package:komet/frontend/screens/auth/login_terms_sheet.dart';
import 'package:komet/l10n/app_localization_delegates.dart';
import 'package:komet/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('acceptance becomes available after reading the full terms', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 680);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    bool? accepted;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: appLocalizationDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                accepted = await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const LoginTermsSheet(
                    accepted: false,
                    phoneNumber: '+1 202 555 0101',
                  ),
                );
              },
              child: const Text('Open terms'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open terms'));
    await tester.pumpAndSettle();
    expect(find.text('+1 202 555 0101'), findsOneWidget);
    final accept = find.widgetWithText(FilledButton, 'Accept and continue');
    expect(tester.widget<FilledButton>(accept).onPressed, isNull);
    expect(find.text('Scroll to the end to continue'), findsOneWidget);

    final content = find.byType(ListView);
    for (var page = 0; page < 20; page++) {
      await tester.drag(content, const Offset(0, -600));
      await tester.pumpAndSettle();
      if (tester.widget<FilledButton>(accept).onPressed != null) break;
    }
    expect(tester.widget<FilledButton>(accept).onPressed, isNotNull);
    expect(accepted, isNull);

    await tester.tap(accept);
    await tester.pumpAndSettle();
    expect(accepted, isTrue);
  });
}
