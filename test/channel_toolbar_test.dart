import 'package:flutter_test/flutter_test.dart';
import 'package:komet/frontend/screens/chats/chat/view/channel_toolbar.dart';
import 'package:komet/frontend/widgets/glossy_pill.dart';
import 'package:komet/frontend/widgets/lottie_slash_icon.dart';
import 'package:komet/l10n/app_localization_delegates.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('search stays on the leading edge and mute stays centered', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 780);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var searched = false;
    var muted = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.35)),
          child: child!,
        ),
        home: Scaffold(
          bottomNavigationBar: StatefulBuilder(
            builder: (context, setState) => ChannelToolbar(
              subscribed: true,
              muted: muted,
              busy: false,
              onSearch: () => searched = true,
              onSubscribe: null,
              onToggleMute: (anchor) {
                expect(anchor.mounted, isTrue);
                setState(() => muted = !muted);
              },
            ),
          ),
        ),
      ),
    );

    final search = find.byIcon(Symbols.search);
    final mute = find.text('Disable notifications');
    final centerPill = find.ancestor(
      of: mute,
      matching: find.byType(GlossyPill),
    );
    expect(
      tester.getCenter(centerPill).dx,
      tester.getCenter(find.byType(Scaffold)).dx,
    );
    expect(
      tester.getCenter(search).dx,
      lessThan(tester.getCenter(centerPill).dx),
    );

    await tester.tap(search);
    await tester.tap(mute);
    await tester.pumpAndSettle();

    expect(searched, isTrue);
    expect(find.text('Enable notifications'), findsOneWidget);
    expect(
      tester.widget<LottieSlashIcon>(find.byType(LottieSlashIcon)).slashed,
      isTrue,
    );
  });

  testWidgets('channel visitors can search during a pending subscription', (
    tester,
  ) async {
    var searched = false;
    var subscribed = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          bottomNavigationBar: ChannelToolbar(
            subscribed: false,
            muted: false,
            busy: true,
            onSearch: () => searched = true,
            onSubscribe: () => subscribed = true,
            onToggleMute: (_) => fail('Channel is not joined'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Subscribe'), warnIfMissed: false);
    await tester.tap(find.byIcon(Symbols.search));
    expect(searched, isTrue);
    expect(subscribed, isFalse);
  });
}
