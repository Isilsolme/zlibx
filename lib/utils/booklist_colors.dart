import 'package:flutter/material.dart';

/// The six list colors the Z-Library site offers (`color` 0–5,
/// named Marine / Velvet / Night Blue / Green / Yellow / Red in the
/// site's color submenu).
///
/// The exact gradient stops were NOT captured from the live site —
/// these two-stop gradients are reasonable stand-ins per name, to be
/// corrected from the site's stylesheet when a capture shows them.
/// [Booklist.color] is -1 (or null) when a list carries no color.
class BooklistColors {
  const BooklistColors._();

  /// (start, end) gradient stops per color value, index = `color`.
  static const List<(Color, Color)> gradients = [
    // Marine: blue → cyan.
    (Color(0xFF1E88E5), Color(0xFF26C6DA)),
    // Velvet: purple → pink.
    (Color(0xFF7E57C2), Color(0xFFEC407A)),
    // Night blue: deep indigo → indigo.
    (Color(0xFF1A237E), Color(0xFF3949AB)),
    // Green: green → light green.
    (Color(0xFF43A047), Color(0xFF9CCC65)),
    // Yellow: amber → yellow.
    (Color(0xFFF9A825), Color(0xFFFFD54F)),
    // Red: red → deep orange.
    (Color(0xFFE53935), Color(0xFFFF7043)),
  ];

  /// True when [color] is one of the six site colors.
  static bool isValid(int? color) =>
      color != null && color >= 0 && color < gradients.length;

  /// The gradient for [color], or null when the list carries no color.
  static LinearGradient? gradientFor(int? color) {
    if (!isValid(color)) return null;
    final (start, end) = gradients[color!];
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [start, end],
    );
  }

  /// The leading color of the gradient for [color], or null when the
  /// list carries no color. Used for small accents (dots, icons)
  /// where a full gradient does not fit.
  static Color? primaryFor(int? color) {
    if (!isValid(color)) return null;
    return gradients[color!].$1;
  }
}
