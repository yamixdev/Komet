import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoDatePicker,
        CupertinoDatePickerMode,
        CupertinoPickerDefaultSelectionOverlay,
        CupertinoTextThemeData,
        CupertinoTheme,
        CupertinoThemeData;
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:komet/core/config/app_motion.dart';
import 'package:komet/core/config/app_shape.dart';
import 'package:komet/core/utils/format.dart';
import 'package:komet/frontend/widgets/glossy_pill.dart';
import 'package:komet/frontend/widgets/komet_avatar.dart';
import 'package:komet/frontend/widgets/sheet_helpers.dart';
import 'package:komet/frontend/widgets/small_spinner.dart';
import 'package:komet/frontend/screens/chats/chat/chat_search_controller.dart';
import 'package:komet/frontend/screens/chats/chat/message_search_result.dart';
import 'package:komet/l10n/app_localizations.dart';

import '../../../../../core/config/app_fonts.dart';

class SearchTopBar extends StatelessWidget {
  const SearchTopBar({
    super.key,
    required this.cs,
    required this.glossy,
    required this.search,
    required this.focusNode,
    required this.onClose,
  });

  final ColorScheme cs;
  final bool glossy;
  final ChatSearchController search;
  final FocusNode focusNode;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    final field = TextField(
      controller: search.searchController,
      focusNode: focusNode,
      textInputAction: TextInputAction.search,
      onSubmitted: search.submit,
      cursorColor: cs.primary,
      style: TextStyle(
        color: cs.onSurface,
        fontSize: 16,
        fontFamily: displayFontOf(context),
      ),
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context)!.searchViewHint,
        hintStyle: TextStyle(
          color: cs.onSurfaceVariant,
          fontSize: 16,
          fontFamily: displayFontOf(context),
        ),
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
    );

    final backBtn = IconButton(
      icon: Icon(
        Symbols.arrow_back,
        weight: glossy ? 500 : 400,
        color: cs.onSurface,
      ),
      onPressed: onClose,
      tooltip: material.backButtonTooltip,
    );
    final searchBtn = ValueListenableBuilder<TextEditingValue>(
      valueListenable: search.searchController,
      builder: (context, value, _) => value.text.isEmpty
          ? const SizedBox(width: 48)
          : IconButton(
              icon: const Icon(Symbols.close),
              onPressed: () {
                search.searchController.clear();
                focusNode.requestFocus();
              },
              tooltip: AppLocalizations.of(context)!.searchViewClear,
            ),
    );

    if (!glossy) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            backBtn,
            Expanded(child: field),
            searchBtn,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: GlossyPill(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              backBtn,
              Expanded(child: field),
              searchBtn,
            ],
          ),
        ),
      ),
    );
  }
}

Duration searchMotion(BuildContext context, Duration duration) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : AppMotion.of(duration);

class SearchBottomBar extends StatelessWidget {
  const SearchBottomBar({
    super.key,
    required this.search,
    required this.cs,
    required this.onOpenResult,
    required this.onJumpToDate,
  });

  final ChatSearchController search;
  final ColorScheme cs;
  final void Function(MessageSearchResult) onOpenResult;
  final Future<void> Function(DateTime)? onJumpToDate;

  void _move(int delta) {
    final result = search.step(delta);
    if (result == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    onOpenResult(result);
  }

  Future<void> _pickDate(BuildContext context) async {
    final jump = onJumpToDate;
    if (jump == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final time = search.selected?.time;
    final date = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: cs.surfaceContainerHigh,
      shape: kSheetShape,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      sheetAnimationStyle:
          searchMotion(context, const Duration(milliseconds: 200)) ==
              Duration.zero
          ? AnimationStyle.noAnimation
          : null,
      builder: (context) => _SearchDateSheet(
        initial: time != null && time > 0
            ? DateTime.fromMillisecondsSinceEpoch(time)
            : DateTime.now(),
      ),
    );
    if (!context.mounted || date == null || !search.searchMode.value) return;
    search.showResults.value = false;
    await jump(date);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Material(
        color: cs.surfaceContainerHigh,
        shape: AppShape.buttonBorder,
        clipBehavior: Clip.antiAlias,
        child: ListenableBuilder(
          listenable: Listenable.merge([search, search.showResults]),
          builder: (context, _) {
            final list = search.showResults.value;
            final count = search.results.length;
            final index = search.selectedIndex;
            final status = switch ((
              search.failed,
              search.performed,
              list,
              count,
            )) {
              (true, _, _, _) => l10n.searchViewFailure,
              (_, true, _, 0) => l10n.searchViewNoResults,
              (_, _, true, > 0) => l10n.searchViewCount(count),
              (_, _, false, > 0) => l10n.searchViewPosition(index + 1, count),
              _ => '',
            };
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                children: [
                  if (onJumpToDate != null)
                    IconButton(
                      tooltip: l10n.searchViewChooseDate,
                      icon: const Icon(Symbols.calendar_today, size: 21),
                      onPressed: () => _pickDate(context),
                    ),
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: search.loading
                          ? SmallSpinner(size: 17, color: cs.primary)
                          : Text(
                              status,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                    ),
                  ),
                  if (!list && count > 0) ...[
                    IconButton(
                      tooltip: l10n.searchViewPrevious,
                      onPressed: index > 0 ? () => _move(-1) : null,
                      icon: const Icon(Symbols.keyboard_arrow_up),
                    ),
                    IconButton(
                      tooltip: l10n.searchViewNext,
                      onPressed: index + 1 < count ? () => _move(1) : null,
                      icon: const Icon(Symbols.keyboard_arrow_down),
                    ),
                  ],
                  if (count > 0 || list)
                    IconButton(
                      tooltip: list
                          ? l10n.searchViewInChat
                          : l10n.searchViewList,
                      onPressed: () {
                        search.showResults.value = !list;
                        if (!list) {
                          FocusManager.instance.primaryFocus?.unfocus();
                        } else {
                          final result = search.selected;
                          if (result != null) onOpenResult(result);
                        }
                      },
                      icon: AnimatedSwitcher(
                        duration: searchMotion(
                          context,
                          const Duration(milliseconds: 160),
                        ),
                        child: Icon(
                          list
                              ? Symbols.chat_bubble_outline
                              : Symbols.format_list_bulleted,
                          key: ValueKey(list),
                          size: 21,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SearchDateSheet extends StatefulWidget {
  const _SearchDateSheet({required this.initial});

  final DateTime initial;

  @override
  State<_SearchDateSheet> createState() => _SearchDateSheetState();
}

class _SearchDateSheetState extends State<_SearchDateSheet> {
  static final _earliest = DateTime(2000);
  late final DateTime _today = DateUtils.dateOnly(DateTime.now());
  late final DateTime _initial = _clamp(widget.initial);
  late DateTime _selected = _initial;

  DateTime _clamp(DateTime date) {
    final day = DateUtils.dateOnly(date);
    if (day.isBefore(_earliest)) return _earliest;
    return day.isAfter(_today) ? _today : day;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.searchViewChooseDate,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(
              height: 168,
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: cs.brightness,
                  primaryColor: cs.primary,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(
                      color: cs.onSurface,
                      fontSize: 18,
                    ),
                  ),
                ),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: _initial,
                  minimumDate: _earliest,
                  minimumYear: _earliest.year,
                  maximumDate: _today,
                  maximumYear: _today.year,
                  itemExtent: 36,
                  selectionOverlayBuilder:
                      (_, {required columnCount, required selectedIndex}) =>
                          CupertinoPickerDefaultSelectionOverlay(
                            background: cs.primary.withValues(alpha: 0.08),
                            capStartEdge: selectedIndex == 0,
                            capEndEdge: selectedIndex == columnCount - 1,
                          ),
                  onDateTimeChanged: (date) => _selected = date,
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_selected),
              child: Text(l10n.searchViewGoToDate),
            ),
          ],
        ),
      ),
    );
  }
}

class SearchOverlay extends StatelessWidget {
  const SearchOverlay({
    super.key,
    required this.cs,
    required this.search,
    required this.onOpenResult,
    required this.senderName,
    required this.senderAvatar,
    required this.topInset,
  });

  final ColorScheme cs;
  final ChatSearchController search;
  final void Function(MessageSearchResult) onOpenResult;
  final String Function(int) senderName;
  final String? Function(int) senderAvatar;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: search.showResults,
      builder: (context, showResults, child) => IgnorePointer(
        ignoring: !showResults,
        child: AnimatedSwitcher(
          duration: searchMotion(context, const Duration(milliseconds: 170)),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOut,
          layoutBuilder: (current, previous) =>
              Stack(fit: StackFit.expand, children: [...previous, ?current]),
          child: showResults ? child : const SizedBox.expand(),
        ),
      ),
      child: Material(
        color: cs.surface,
        child: Padding(
          padding: EdgeInsets.only(top: topInset),
          child: ListenableBuilder(
            listenable: search,
            builder: (context, _) => _resultsContent(context),
          ),
        ),
      ),
    );
  }

  Widget _resultsContent(BuildContext context) {
    if (search.loading) {
      return Center(child: SmallSpinner(size: 26, color: cs.primary));
    }
    final results = search.results;
    if (results.isNotEmpty) {
      return ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: results.length,
        itemBuilder: (context, index) => _tile(context, results[index]),
      );
    }
    if (!search.performed) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          search.failed ? l10n.searchViewFailure : l10n.searchViewNoResults,
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      ),
    );
  }

  String _resultPreview(BuildContext context, MessageSearchResult result) {
    if (result.text.isNotEmpty) return result.text;
    final name = result.attachmentName;
    if (name != null && name.isNotEmpty) return name;
    final l10n = AppLocalizations.of(context)!;
    return switch (result.attachmentType) {
      'PHOTO' => l10n.scheduledAttachPhoto,
      'VIDEO' => l10n.scheduledAttachVideo,
      'AUDIO' => l10n.scheduledAttachVoice,
      'FILE' => l10n.scheduledAttachFile,
      'CONTACT' => l10n.attachmentContactFallback,
      'LOCATION' => l10n.scheduledAttachLocation,
      'FORWARD' => l10n.scheduledAttachForwarded,
      _ => l10n.scheduledAttachGeneric,
    };
  }

  Widget _tile(BuildContext context, MessageSearchResult r) {
    final name = senderName(r.senderId);
    final date = formatDateWords(
      AppLocalizations.of(context)!,
      DateTime.fromMillisecondsSinceEpoch(r.time),
    );
    final selected = search.selected?.id == r.id;
    return Ink(
      color: selected
          ? cs.primaryContainer.withValues(alpha: 0.28)
          : cs.surface,
      child: InkWell(
        key: ValueKey(r.id),
        onTap: () {
          FocusManager.instance.primaryFocus?.unfocus();
          search.select(r);
          onOpenResult(r);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KometAvatar(
                name: name,
                imageUrl: senderAvatar(r.senderId),
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: cs.primary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              fontFamily: displayFontOf(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          date,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    _highlighted(_resultPreview(context, r), r.highlights),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _highlighted(String text, List<String> highlights) {
    final baseStyle = TextStyle(color: cs.onSurface, fontSize: 15);
    final terms = highlights
        .where((h) => h.trim().isNotEmpty)
        .map((h) => h.toLowerCase())
        .toSet();
    if (text.isEmpty || terms.isEmpty) {
      return Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }

    final lower = text.toLowerCase();
    final ranges = <List<int>>[];
    for (final term in terms) {
      var start = 0;
      while (true) {
        final idx = lower.indexOf(term, start);
        if (idx < 0) break;
        ranges.add([idx, idx + term.length]);
        start = idx + term.length;
      }
    }
    if (ranges.isEmpty) {
      return Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }

    ranges.sort((a, b) => a[0].compareTo(b[0]));
    final merged = <List<int>>[];
    for (final r in ranges) {
      if (merged.isNotEmpty && r[0] <= merged.last[1]) {
        merged.last[1] = math.max(merged.last[1], r[1]);
      } else {
        merged.add([r[0], r[1]]);
      }
    }

    final highlightStyle = baseStyle.copyWith(
      color: cs.primary,
      fontWeight: FontWeight.w600,
      backgroundColor: cs.primary.withValues(alpha: 0.18),
    );
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final r in merged) {
      if (r[0] > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, r[0])));
      }
      spans.add(
        TextSpan(text: text.substring(r[0], r[1]), style: highlightStyle),
      );
      cursor = r[1];
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return Text.rich(
      TextSpan(style: baseStyle, children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
