import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komet/backend/modules/messages.dart';
import 'package:komet/frontend/screens/chats/chat/chat_search_controller.dart';
import 'package:komet/frontend/screens/chats/chat/view/search_view.dart';
import 'package:komet/l10n/app_localization_delegates.dart';
import 'package:komet/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

class _SearchSource implements MessagesModule {
  final Map<String, Completer<List<Map<String, dynamic>>>> _responses = {};

  @override
  Future<List<Map<String, dynamic>>> searchMessages(
    int chatId,
    String query, {
    int count = 30,
  }) => _responses
      .putIfAbsent(query, Completer<List<Map<String, dynamic>>>.new)
      .future;

  void reply(String query, List<Map<String, dynamic>> results) {
    _responses[query]!.complete(results);
  }

  @override
  Future<bool> ensureContactNames(Iterable<int> ids) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _match(String id, {String text = '', String? file}) => {
  'message': {
    'id': id,
    'sender': 1,
    'text': text,
    'time': DateTime(2024, 10, 17).millisecondsSinceEpoch,
    if (file != null)
      'attaches': [
        {'_type': 'FILE', 'name': file},
      ],
  },
};

void main() {
  test(
    'changing the query drops an in-flight response during debounce',
    () async {
      final source = _SearchSource();
      final opened = <String>[];
      final controller = ChatSearchController(
        chatId: 1,
        isMounted: () => true,
        source: source,
        onFirstResult: (result) => opened.add(result.id),
      );
      addTearDown(controller.dispose);
      controller.searchMode.value = true;
      controller.searchController.text = 'older';
      final older = controller.runSearch('older');

      controller.searchController.text = 'newer';
      source.reply('older', [_match('older')]);
      await older;

      expect(controller.results, isEmpty);
      expect(controller.loading, isTrue);
      expect(opened, isEmpty);
    },
  );

  testWidgets('the search bar navigates hits, shows a list and opens a date', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = _SearchSource();
    final opened = <String>[];
    DateTime? jumpedDate;
    final controller = ChatSearchController(
      chatId: 1,
      isMounted: () => true,
      source: source,
      onFirstResult: (result) => opened.add(result.id),
    );
    addTearDown(controller.dispose);
    controller.searchMode.value = true;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: appLocalizationDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final cs = Theme.of(context).colorScheme;
              return Column(
                children: [
                  Expanded(
                    child: SearchOverlay(
                      cs: cs,
                      search: controller,
                      onOpenResult: (result) => opened.add(result.id),
                      senderName: (_) => 'Synthetic sender',
                      senderAvatar: (_) => null,
                      topInset: 0,
                    ),
                  ),
                  SearchBottomBar(
                    cs: cs,
                    search: controller,
                    onOpenResult: (result) => opened.add(result.id),
                    onJumpToDate: (date) async => jumpedDate = date,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    final search = controller.runSearch('fixture');
    source.reply('fixture', [
      _match('1', text: 'Synthetic first result'),
      _match('2', file: 'fixture.zip'),
      _match('2', file: 'fixture.zip'),
    ]);
    await search;
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);
    expect(opened, ['1']);

    await tester.tap(find.byTooltip('Next result'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 2'), findsOneWidget);
    expect(opened, ['1', '2']);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Next result',
            ),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byTooltip('Results list'));
    await tester.pumpAndSettle();
    expect(find.text('fixture.zip'), findsOneWidget);
    expect(find.text('2 results loaded'), findsOneWidget);
    await tester.tap(find.text('Synthetic first result'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);
    expect(opened, ['1', '2', '1']);

    await tester.tap(find.byTooltip('Choose a date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go to date'));
    await tester.pumpAndSettle();
    expect(jumpedDate, DateTime(2024, 10, 17));
    expect(tester.takeException(), isNull);
  });
}
