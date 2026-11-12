import 'package:flutter/material.dart';

/// Opens the one and only settings popup shape used across the app: a
/// Material 3 modal bottom sheet (28dp top corners, drag handle, tonal
/// surface, shared barrier and slide animation).
///
/// legado routes every choice through its AppModalBottomSheet; keeping a
/// single helper here is the Flutter equivalent. Text-input and confirmation
/// dialogs stay dialogs, but inherit the matching 28dp shape from
/// AppTheme.dialogTheme.
Future<T?> showSettingsSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  List<Widget>? actions,
  bool scrollable = true,
}) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: cs.surfaceContainerLow,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      final content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          child,
          if (actions != null && actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions,
              ),
            ),
        ],
      );

      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.82),
        child: Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          // A single scroll view that shrink-wraps short content and scrolls
          // tall content. Do not use Flexible here: inside a min-size Column
          // it collapsed the sheet to zero height.
          child: scrollable
              ? SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: content,
                )
              : content,
        ),
      );
    },
  );
}

/// A selectable row inside showSettingsSheet. Selected rows get the M3
/// secondary-container pill and a check, like legado's option rows.
class SettingsOptionTile extends StatelessWidget {
  const SettingsOptionTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.leading,
    this.selected = false,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? leading;
  final bool selected;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foreground = selected ? cs.onSecondaryContainer : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          enabled: enabled,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          leading:
              leading ??
              (icon == null
                  ? null
                  : Icon(
                      icon,
                      color: selected
                          ? cs.onSecondaryContainer
                          : cs.onSurfaceVariant,
                    )),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: foreground,
            ),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  style: TextStyle(
                    color: selected
                        ? cs.onSecondaryContainer.withValues(alpha: 0.78)
                        : cs.onSurfaceVariant,
                  ),
                ),
          trailing:
              trailing ??
              (selected
                  ? Icon(Icons.check_rounded, color: cs.onSecondaryContainer)
                  : null),
          onTap: enabled ? onTap : null,
        ),
      ),
    );
  }
}

/// A switch row with the same padding/shape as SettingsOptionTile.
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.icon,
    this.onChanged,
  });

  final String title;
  final bool value;
  final String? subtitle;
  final IconData? icon;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: SwitchListTile(
        secondary: icon == null ? null : Icon(icon, color: cs.onSurfaceVariant),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: subtitle == null ? null : Text(subtitle!),
        value: value,
        onChanged: onChanged,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        activeThumbColor: cs.primary,
      ),
    );
  }
}
