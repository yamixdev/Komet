import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/terms_of_service.dart';

class LoginTermsSheet extends StatefulWidget {
  const LoginTermsSheet({super.key, required this.accepted, this.phoneNumber});

  final bool accepted;
  final String? phoneNumber;

  @override
  State<LoginTermsSheet> createState() => _LoginTermsSheetState();
}

class _LoginTermsSheetState extends State<LoginTermsSheet> {
  final _progress = ValueNotifier<double>(0);
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _progress.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _updateReadingProgress(ScrollMetrics metrics) {
    if (widget.accepted || _progress.value == 1) return false;
    if (metrics.extentAfter <= 1) {
      _progress.value = 1;
    } else {
      final extent = metrics.maxScrollExtent - metrics.minScrollExtent;
      _progress.value = ((metrics.pixels - metrics.minScrollExtent) / extent)
          .clamp(0.0, 0.99);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final typography = theme.textTheme;
    final sections = termsOfServiceBody(Localizations.localeOf(context))
        .trim()
        .split(RegExp(r'\n\s*\n'));

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: FractionallySizedBox(
          heightFactor: 0.91,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.loginTermsOfUse,
                        style: typography.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Symbols.close),
                    ),
                  ],
                ),
              ),
              if (widget.phoneNumber case final phone?)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.loginConfirmPhoneTitle,
                        style: typography.bodyMedium,
                      ),
                      Text(
                        phone,
                        style: typography.titleMedium,
                        textDirection: TextDirection.ltr,
                      ),
                    ],
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: NotificationListener<ScrollMetricsNotification>(
                  onNotification: (event) =>
                      _updateReadingProgress(event.metrics),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (event) =>
                        _updateReadingProgress(event.metrics),
                    child: Scrollbar(
                      controller: _scrollController,
                      child: ListView.separated(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                        itemCount: sections.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 18),
                        itemBuilder: (context, index) {
                          final section = sections[index];
                          final titleEnd = section.indexOf('\n');
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(
                                header: true,
                                child: Text(
                                  titleEnd < 0
                                      ? section
                                      : section.substring(0, titleEnd),
                                  style: typography.titleMedium,
                                ),
                              ),
                              if (titleEnd >= 0) ...[
                                const SizedBox(height: 8),
                                Text(
                                  section.substring(titleEnd + 1),
                                  style: typography.bodyMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                child: ValueListenableBuilder<double>(
                  valueListenable: _progress,
                  builder: (context, progress, _) {
                    final canAccept = widget.accepted || progress == 1;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!widget.accepted) ...[
                          LinearProgressIndicator(value: progress),
                          Visibility(
                            visible: !canAccept,
                            maintainState: true,
                            maintainAnimation: true,
                            maintainSize: true,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                l10n.loginReadTermsToEnd,
                                style: typography.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: canAccept
                              ? () => Navigator.pop(context, true)
                              : null,
                          child: Text(
                            widget.accepted
                                ? l10n.loginDone
                                : widget.phoneNumber == null
                                ? l10n.e2eeAccept
                                : l10n.loginAcceptAndContinue,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
