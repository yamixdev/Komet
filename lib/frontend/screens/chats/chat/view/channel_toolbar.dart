import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../widgets/glossy_pill.dart';
import '../../../../widgets/lottie_slash_icon.dart';
import '../../../../../l10n/app_localizations.dart';

class ChannelToolbar extends StatelessWidget {
  const ChannelToolbar({
    super.key,
    required this.subscribed,
    required this.muted,
    required this.busy,
    required this.onSearch,
    required this.onSubscribe,
    required this.onToggleMute,
  });

  final bool subscribed;
  final bool muted;
  final bool busy;
  final VoidCallback? onSearch;
  final VoidCallback? onSubscribe;
  final ValueChanged<BuildContext> onToggleMute;

  static const _controlSize = 48.0;
  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final motion = !MediaQuery.disableAnimationsOf(context);
    final duration = motion ? const Duration(milliseconds: 160) : Duration.zero;
    final foreground = subscribed
        ? colors.onSecondaryContainer
        : colors.onPrimary;
    final label = !subscribed
        ? l10n.chatInfoActionSubscribe
        : muted
        ? l10n.notificationsFkmEnableLabel
        : l10n.chatScreenMenuMute;
    final searchLabel = l10n.chatInfoMembersSearchHint;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            if (onSearch != null) ...[
              Tooltip(
                message: searchLabel,
                child: GlossyPill(
                  softGlass: true,
                  onTap: onSearch,
                  color: colors.surfaceContainerHigh,
                  depth: 4,
                  child: SizedBox.square(
                    dimension: _controlSize,
                    child: Icon(
                      Symbols.search,
                      color: colors.onSurface,
                      size: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: _gap),
            ],
            Expanded(
              child: Builder(
                builder: (anchor) => Semantics(
                  button: true,
                  enabled: !busy && (subscribed || onSubscribe != null),
                  label: label,
                  excludeSemantics: true,
                  onTap: busy
                      ? null
                      : subscribed
                      ? () => onToggleMute(anchor)
                      : onSubscribe,
                  child: GlossyPill(
                    softGlass: true,
                    onTap: busy
                        ? null
                        : subscribed
                        ? () => onToggleMute(anchor)
                        : onSubscribe,
                    color: subscribed
                        ? colors.secondaryContainer
                        : colors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    depth: 4,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 32),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (subscribed)
                            LottieSlashIcon(
                              asset: 'assets/lottie/ic_notifications_on_to_off.json',
                              slashed: muted,
                              color: foreground,
                              size: 20,
                              duration: motion
                                  ? const Duration(milliseconds: 240)
                                  : Duration.zero,
                            )
                          else if (busy)
                            SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: foreground,
                              ),
                            )
                          else
                            Icon(Symbols.add, color: foreground, size: 20),
                          const SizedBox(width: 7),
                          Flexible(
                            child: AnimatedSwitcher(
                              duration: duration,
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeOut,
                              child: Text(
                                label,
                                key: ValueKey(label),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: foreground,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (onSearch != null) const SizedBox(width: _controlSize + _gap),
          ],
        ),
      ),
    );
  }
}
