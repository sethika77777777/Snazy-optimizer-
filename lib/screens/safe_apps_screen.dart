import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import '../services/apps_service.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';

class SafeAppsScreen extends StatefulWidget {
  final Set<String> initialSafeList;
  const SafeAppsScreen({super.key, required this.initialSafeList});

  @override
  State<SafeAppsScreen> createState() => _SafeAppsScreenState();
}

class _SafeAppsScreenState extends State<SafeAppsScreen> {
  List<AppInfo> _apps = [];
  late Set<String> _selected;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initialSafeList};
    _load();
  }

  Future<void> _load() async {
    final apps = await AppsService.getInstalledApps();
    apps.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
    setState(() {
      _apps = apps;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: SnazyTheme.pageGradient,
        child: SafeArea(
          child: Column(
            children: [
              AppBar(
                title: const Text('Keep alive during freeze'),
                backgroundColor: Colors.transparent,
                elevation: 0,
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: const Text('Save',
                        style: TextStyle(color: SnazyTheme.accentCyan)),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Apps checked here are skipped by Background Freeze '
                  '(e.g. your messenger, music player, or VPN).',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: SnazyTheme.accentCyan))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _apps.length,
                        itemBuilder: (context, i) {
                          final app = _apps[i];
                          final pkg = app.packageName ?? '';
                          final checked = _selected.contains(pkg);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: GlassCard(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              child: CheckboxListTile(
                                value: checked,
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selected.add(pkg);
                                    } else {
                                      _selected.remove(pkg);
                                    }
                                  });
                                },
                                activeColor: SnazyTheme.accentCyan,
                                title: Text(app.name ?? pkg,
                                    style:
                                        const TextStyle(color: Colors.white)),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              ),
                            ),
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
