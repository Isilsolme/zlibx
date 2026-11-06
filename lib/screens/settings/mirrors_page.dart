// Ported from warreth/OpenlibExtended (AGPL-3.0) — Mirror management page.
// Original file: lib/ui/instances_page.dart
// zlibx is AGPL-3.0 (see LICENSE); upstream MIT attribution for
// shiyi-0x7f/olib-mobile is preserved in LICENSE.
//
// Adaptations: upstream reads the manager through Riverpod providers
// (instanceManagerProvider / serviceInstancesProvider /
// instanceAutoModeProvider); zlibx's InstanceManager is a plain
// singleton, so this page keeps its own state and calls it directly.
// The app bar uses zlibx's GradientAppBar like the other settings
// screens, and every user-facing string goes through AppLocalizations.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/instance_manager.dart';
import '../../widgets/gradient_app_bar.dart';

/// Settings > Network > Mirrors.
///
/// Every mirror the app can talk to, per service, exactly as
/// open-slum.org reports it — the app hardcodes no mirror URLs. Each row
/// shows SLUM's status, the protection gate and its latency, and can be
/// switched off. Ordering is automatic by default (easiest protection
/// first, then fastest); flipping the switch to manual lets the user
/// move mirrors with the arrows. A mirror SLUM reports DOWN is shown
/// greyed out and is never contacted.
class MirrorsPage extends StatefulWidget {
  const MirrorsPage({super.key});

  @override
  State<MirrorsPage> createState() => _MirrorsPageState();
}

class _MirrorsPageState extends State<MirrorsPage> {
  bool _refreshing = false;
  bool _loading = true;
  bool _loadError = false;
  bool _autoMode = true;
  final Map<MirrorService, List<InstanceView>> _views = {};

  static const _serviceOrder = [
    MirrorService.libgen,
    MirrorService.zlibrary,
    MirrorService.welib,
    MirrorService.annasArchive,
  ];

  static const _serviceTitles = {
    MirrorService.libgen: 'Library Genesis',
    MirrorService.zlibrary: 'Z-Library',
    MirrorService.welib: 'WeLib',
    MirrorService.annasArchive: "Anna's Archive",
  };

  static const _serviceSubtitleKeys = {
    MirrorService.libgen: 'mirror_service_libgen_desc',
    MirrorService.zlibrary: 'mirror_service_zlibrary_desc',
    MirrorService.welib: 'mirror_service_welib_desc',
    MirrorService.annasArchive: 'mirror_service_annas_desc',
  };

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    try {
      final auto = await InstanceManager().isAutoMode();
      final views = <MirrorService, List<InstanceView>>{};
      await Future.wait([
        for (final service in _serviceOrder)
          InstanceManager()
              .instances(service)
              .then((list) => views[service] = list),
      ]);
      if (!mounted) return;
      setState(() {
        _autoMode = auto;
        _views.addAll(views);
        _loading = false;
        _loadError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = true;
      });
    }
  }

  Future<void> _loadService(MirrorService service) async {
    final views = await InstanceManager().instances(service);
    if (!mounted) return;
    setState(() => _views[service] = views);
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await InstanceManager().refresh();
      if (!mounted) return;
      await _loadAll();
      if (!mounted) return;
      if (!result.hasMirrorList) {
        // Nothing is known — saying "up to date" would claim the empty
        // list is SLUM's answer.
        messenger.showSnackBar(SnackBar(
          content: Text(l10n.get('mirror_list_unreachable')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
        return;
      }
      messenger.showSnackBar(SnackBar(
        content: Text(result.changes.isEmpty
            ? l10n.get('mirror_list_up_to_date')
            : l10n
                .get('mirror_list_updated')
                .replaceAll('{count}', '${result.changes.length}')),
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.get('mirror_refresh_failed')),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: GradientAppBar(title: l10n.get('mirrors')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 12),
                    Text(l10n.get('mirrors_load_failed')),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _loading = true;
                          _loadError = false;
                        });
                        _loadAll();
                      },
                      child: Text(l10n.get('search_retry')),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  _buildModeCard(l10n),
                  for (final service in _serviceOrder) ...[
                    _sectionHeader(l10n, service),
                    _serviceList(l10n, service),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Text(
                      l10n.get('mirrors_footer_note'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildModeCard(AppLocalizations l10n) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: SwitchListTile(
        value: _autoMode,
        onChanged: (value) async {
          await InstanceManager().setAutoMode(value);
          if (!mounted) return;
          setState(() => _autoMode = value);
          await _loadAll();
        },
        title: Text(l10n.get('mirror_auto_order')),
        subtitle: Text(_autoMode
            ? l10n.get('mirror_auto_desc')
            : l10n.get('mirror_manual_desc')),
        secondary:
            Icon(_autoMode ? Icons.auto_awesome : Icons.touch_app),
      ),
    );
  }

  Widget _sectionHeader(AppLocalizations l10n, MirrorService service) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _serviceTitles[service] ?? service.name,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            l10n.get(_serviceSubtitleKeys[service] ?? ''),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _serviceList(AppLocalizations l10n, MirrorService service) {
    final views = _views[service];
    if (views == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (views.isEmpty) {
      return ListTile(
        dense: true,
        leading: const Icon(Icons.cloud_off),
        title: Text(l10n.get('mirrors_no_mirrors')),
        subtitle: Text(l10n.get('mirrors_no_mirrors_hint')),
        trailing: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _refresh,
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < views.length; i++)
          _mirrorTile(l10n, service, views[i], i, views.length),
      ],
    );
  }

  Widget _mirrorTile(AppLocalizations l10n, MirrorService service,
      InstanceView view, int index, int total) {
    final site = view.site;
    final down = site.isDown;

    return Opacity(
      opacity: down ? 0.55 : 1,
      child: ListTile(
        dense: true,
        leading: _statusDot(site.status),
        title: Text(
          site.host,
          style: TextStyle(
            decoration: down ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          [
            site.status.name.toUpperCase(),
            if (site.protection != Protection.none) site.protection.label,
            if (site.latencyMs != null) '${site.latencyMs}ms',
            if (down) l10n.get('mirrors_down_hint'),
          ].join(' · '),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_autoMode) ...[
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up),
                iconSize: 20,
                tooltip: l10n.get('mirror_move_up'),
                onPressed: index == 0
                    ? null
                    : () async {
                        await InstanceManager()
                            .move(service, site.host, -1);
                        await _loadService(service);
                      },
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down),
                iconSize: 20,
                tooltip: l10n.get('mirror_move_down'),
                onPressed: index == total - 1
                    ? null
                    : () async {
                        await InstanceManager()
                            .move(service, site.host, 1);
                        await _loadService(service);
                      },
              ),
            ],
            Switch(
              value: view.enabled && !down,
              onChanged: down
                  ? null
                  : (value) async {
                      await InstanceManager()
                          .setEnabled(service, site.host, value);
                      await _loadService(service);
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusDot(SlumStatus status) {
    final (color, icon) = switch (status) {
      SlumStatus.up => (Colors.green, Icons.check_circle),
      SlumStatus.degraded => (Colors.orange, Icons.error_outline),
      SlumStatus.protected => (Colors.blue, Icons.shield),
      SlumStatus.down => (Colors.red, Icons.cancel),
      SlumStatus.unknown => (Colors.grey, Icons.help_outline),
    };
    return Icon(icon, color: color);
  }
}
