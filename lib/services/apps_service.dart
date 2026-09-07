import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';

/// Wraps the installed_apps plugin — this returns the device's real
/// installed package list with real icons. Android has no public API to
/// mark "this is a game" pre-Play-Store-metadata, so we surface everything
/// and let the user pick, same as most optimizer apps actually do.
class AppsService {
  static Future<List<AppInfo>> getInstalledApps() async {
    return InstalledApps.getInstalledApps(true, true);
  }

  static Future<void> launchApp(String packageName) async {
    await InstalledApps.startApp(packageName);
  }
}
