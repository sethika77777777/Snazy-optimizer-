import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import '../services/apps_service.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';

class GameSelectScreen extends StatefulWidget {
  final String? currentSelection;
  const GameSelectScreen({super.key, this.currentSelection});

  @override
  State<GameSelectScreen> createState() => _GameSelectScreenState();
}

class _GameSelectScreenState extends State<GameSelectScreen> {
  List<AppInfo> _apps = [];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
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
    final filtered = _apps
        .where((a) =>
            (a.name ?? '').toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Scaffold(
      body: Container(
        decoration: SnazyTheme.pageGradient,
        child: SafeArea(
          child: Column(
            children: [
              AppBar(
                title: const Text('Select a game'),
                backgroundColor: Colors.transparent,
                elevation: 0,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Search installed apps...',
                      hintStyle: TextStyle(color: Colors.white38),
                      icon: Icon(Icons.search, color: Colors.white38),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: SnazyTheme.accentCyan))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final app = filtered[i];
                          final selected =
                              app.packageName == widget.currentSelection;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: InkWell(
                              onTap: () =>
                                  Navigator.pop(context, app.packageName),
                              borderRadius: BorderRadius.circular(16),
                              child: GlassCard(
                                child: Row(
                                  children: [
                                    if (app.icon != null)
                                      ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        child: Image.memory(app.icon!,
                                            width: 36, height: 36),
                                      )
                                    else
                                      const Icon(Icons.apps,
                                          color: Colors.white54),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(app.name ?? app.packageName ?? '',
                                          style: const TextStyle(
                                              color: Colors.white)),
                                    ),
                                    if (selected)
                                      const Icon(Icons.check_circle,
                                          color: SnazyTheme.accentCyan),
                                  ],
                                ),
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
