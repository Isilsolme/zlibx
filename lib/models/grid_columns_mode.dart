/// How the home recommendation grid decides its column count.
///
/// [auto] is the default: the grid fits as many columns as the current width
/// allows (3 on a phone, 4–8 on a tablet), so the layout follows the window
/// instead of a fixed phone-only choice. [two] and [three] remain as explicit
/// overrides for users who prefer a specific density.
enum GridColumnsMode {
  auto,
  two,
  three;

  /// Column count for the manual modes, or null when the width decides.
  int? get fixedColumns => switch (this) {
    GridColumnsMode.auto => null,
    GridColumnsMode.two => 2,
    GridColumnsMode.three => 3,
  };
}
