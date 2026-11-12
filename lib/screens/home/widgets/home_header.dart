import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/s_keys.dart';

/// Time-based greeting shown above the user name.
String greetingFor(BuildContext context) {
  final hour = DateTime.now().hour;
  if (hour < 6) {
    return AppLocalizations.of(context).get(S.greetingLateNight);
  }
  if (hour < 12) {
    return AppLocalizations.of(context).get(S.goodMorning);
  }
  if (hour < 14) {
    return AppLocalizations.of(context).get(S.greetingNoon);
  }
  if (hour < 18) {
    return AppLocalizations.of(context).get(S.greetingAfternoon);
  }
  if (hour < 22) {
    return AppLocalizations.of(context).get(S.greetingEvening);
  }
  return AppLocalizations.of(context).get(S.greetingLateNight);
}

/// The glass header floating over the recommendation grid: a search trigger
/// and the greeting/name block.
///
/// The height is fixed (see [heightFor]) so the grid can reserve exactly that
/// much space and scroll underneath the blurred header instead of starting
/// below it.
class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.topInset,
    required this.userName,
    required this.onSearch,
  });

  /// Status-bar inset the header has to clear (0 when a banner above the
  /// header already consumed it).
  final double topInset;
  final String userName;
  final VoidCallback onSearch;

  static const double _pad = 12;
  static const double _searchHeight = 52;
  static const double _gap = 10;
  static const double _greetingHeight = 54;

  /// Height of the header below the status bar, honouring the user's text
  /// scale so a large font does not overflow the reserved band.
  static double contentHeightFor(BuildContext context) {
    final greeting = MediaQuery.textScalerOf(context).scale(_greetingHeight);
    return _pad + _searchHeight + _gap + greeting + _pad;
  }

  static double heightFor(BuildContext context, double topInset) =>
      topInset + contentHeightFor(context);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final greetingHeight = MediaQuery.textScalerOf(
      context,
    ).scale(_greetingHeight);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topInset + _pad, 20, _pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SearchTrigger(onTap: onSearch),
          const SizedBox(height: _gap),
          SizedBox(
            height: greetingHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  greetingFor(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.2,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 26,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchTrigger extends StatelessWidget {
  const _SearchTrigger({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: HomeHeader._searchHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(26),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              color: cs.surfaceContainerHigh.withValues(alpha: 0.92),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.search_rounded,
                    size: 21,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context).get(S.searchForBooks),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
