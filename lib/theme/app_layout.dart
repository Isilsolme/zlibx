import 'package:flutter/widgets.dart';

import '../models/grid_columns_mode.dart';

/// Material 3 window size classes, in logical pixels.
///
/// Only the two boundaries the app actually reacts to are kept: [medium] is
/// where phones end and tablets begin, [expanded] is where a tablet is wide
/// enough for a roomier page gutter.
abstract final class AppBreakpoints {
  /// Phones are narrower than this; rails, wider grids and tablet chrome
  /// start here.
  static const double medium = 600;

  /// Large tablet / desktop windows: wider page gutters.
  static const double expanded = 1240;
}

/// Responsive rules shared by the app shell, the navigation and the grids.
///
/// Everything is computed from the current width (via [MediaQuery] or a
/// [LayoutBuilder] constraint) so a tablet in portrait, a tablet in
/// landscape, a foldable half-open and a free-form desktop window all get a
/// sensible layout without extra configuration.
abstract final class AppLayout {
  /// At and above this width the four destinations move from the floating
  /// bottom bar into a vertical navigation rail on the left.
  ///
  /// M3's compact→medium boundary: a 7" tablet in portrait (600x1024)
  /// already gets the rail, while a phone in landscape (about 880x411) does
  /// too — which is desirable, the bar would eat the little height it has.
  static const double navRailWidth = AppBreakpoints.medium;

  /// Width of the left navigation rail (Material's default minimum, with a
  /// little extra so translated labels never wrap).
  static const double navRailMinWidth = 80;

  static bool usesNavRail(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= navRailWidth;

  /// Space a tab's scrollable should reserve below its content so nothing is
  /// trapped under the navigation.
  ///
  /// Phone: the floating bar's clearance (96dp) is reserved inside each
  /// list, matching the previous fixed paddings. Tablet: the rail takes no
  /// vertical space, so only breathing room plus the system inset remains.
  static double navClearance(BuildContext context) {
    if (usesNavRail(context)) {
      return 24 + MediaQuery.viewPaddingOf(context).bottom;
    }
    return 96;
  }

  /// Horizontal page gutter for the home grid and its header.
  static double pageGutter(double width) {
    if (width >= AppBreakpoints.expanded) return 48;
    if (width >= AppBreakpoints.medium) return 32;
    return 20;
  }

  /// Gap between grid cells.
  static const double gridSpacing = 16;

  /// Narrowest a book card may get before the grid drops a column. Phones
  /// keep their current 3-column density (~113dp cards at 411dp wide).
  static const double minCardWidth = 112;

  /// Upper bound so a very wide window does not turn covers into stamps.
  static const int maxGridColumns = 8;

  /// Resolves the home grid column count for [contentWidth] (already minus
  /// the page gutter).
  static int gridColumns(GridColumnsMode mode, double contentWidth) {
    final fixed = mode.fixedColumns;
    if (fixed != null) return fixed;
    final fitting =
        ((contentWidth + gridSpacing) / (minCardWidth + gridSpacing)).floor();
    return fitting.clamp(2, maxGridColumns).toInt();
  }
}
