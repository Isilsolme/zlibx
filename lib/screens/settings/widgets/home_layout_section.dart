import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../models/grid_columns_mode.dart';
import '../../../providers/settings_provider.dart';
import 'section_header.dart';
import 'settings_card.dart';

/// Home layout: the book grid follows the screen by default (3 columns on a
/// phone, more on a tablet); 2 and 3 stay available as manual overrides.
class HomeLayoutSection extends ConsumerWidget {
  const HomeLayoutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context)!;
    final mode = ref.watch(homeGridColumnsModeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(icon: Icons.grid_view_rounded, title: t.homeLayout),
        SettingsCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.grid_view_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      t.gridColumns,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<GridColumnsMode>(
                  segments: <ButtonSegment<GridColumnsMode>>[
                    ButtonSegment<GridColumnsMode>(
                      value: GridColumnsMode.auto,
                      label: Text(t.autoGridColumns),
                    ),
                    ButtonSegment<GridColumnsMode>(
                      value: GridColumnsMode.two,
                      label: Text(t.twoColumns),
                    ),
                    ButtonSegment<GridColumnsMode>(
                      value: GridColumnsMode.three,
                      label: Text(t.threeColumns),
                    ),
                  ],
                  selected: <GridColumnsMode>{mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    unawaited(
                      ref
                          .read(homeGridColumnsModeProvider.notifier)
                          .setMode(selection.first),
                    );
                  },
                  style: ButtonStyle(
                    side: const WidgetStatePropertyAll(BorderSide.none),
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      return states.contains(WidgetState.selected)
                          ? cs.primaryContainer
                          : cs.surfaceContainerHigh;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      return states.contains(WidgetState.selected)
                          ? cs.onPrimaryContainer
                          : cs.onSurfaceVariant;
                    }),
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                t.autoGridColumnsHint,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
