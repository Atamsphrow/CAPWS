import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_identity.dart';
import 'screens/apps_list_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/permissions_list_screen.dart';
import 'services/error_reporter.dart';
import 'services/inventory_controller.dart';

void main() {
  // The binding has to exist before the reporter can schedule its notifications,
  // and the reporter has to be installed before the first frame so that errors
  // thrown during the very first build are captured too.
  WidgetsFlutterBinding.ensureInitialized();
  ErrorReporter.instance.install();
  runApp(const CapwsApp());
}

class CapwsApp extends StatefulWidget {
  const CapwsApp({super.key});

  @override
  State<CapwsApp> createState() => _CapwsAppState();
}

class _CapwsAppState extends State<CapwsApp> {
  final InventoryController _controller = InventoryController();

  @override
  void initState() {
    super.initState();
    _controller.refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // DynamicColorBuilder hands back the system palette on Android 12+; the seed
    // colour is only the fallback on anything older. It is deliberately not tied to
    // the launcher icon's palette — on any recent device the UI follows the
    // wallpaper, not this value.
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        const seed = Color(0xFF3F6DDA);
        final light = lightDynamic?.harmonized() ?? ColorScheme.fromSeed(seedColor: seed);
        final dark =
            darkDynamic?.harmonized() ??
            ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);

        return InventoryScope(
          controller: _controller,
          child: MaterialApp(
            title: AppIdentity.name,
            debugShowCheckedModeBanner: false,
            theme: ThemeData(colorScheme: light),
            darkTheme: ThemeData(colorScheme: dark),
            home: const HomeShell(),
          ),
        );
      },
    );
  }
}

/// Lets the dashboard send the user into a tab with filters already applied, which
/// is what makes its counters clickable.
class HomeNavigator extends InheritedWidget {
  const HomeNavigator({super.key, required this.go, required super.child});

  final void Function(int index, {Filters? filters}) go;

  static HomeNavigator of(BuildContext context) {
    final navigator = context.dependOnInheritedWidgetOfExactType<HomeNavigator>();
    assert(navigator != null, 'Aucun HomeNavigator dans l\'arbre de widgets.');
    return navigator!;
  }

  @override
  bool updateShouldNotify(HomeNavigator oldWidget) => false;
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// Guards against a second dialog when back is pressed repeatedly.
  bool _confirmingExit = false;

  void _go(int index, {Filters? filters}) {
    if (filters != null) InventoryScope.of(context).setFilters(filters);
    setState(() => _index = index);
  }

  /// Back on a secondary tab returns to the dashboard; back on the dashboard asks
  /// before leaving, since a stray back press otherwise drops the user out of the
  /// app entirely.
  Future<void> _handleBack(bool didPop) async {
    if (didPop) return;

    if (_index != 0) {
      setState(() => _index = 0);
      return;
    }

    if (_confirmingExit) return;
    _confirmingExit = true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.exit_to_app),
        title: const Text('Quitter CAPWS ?'),
        content: const Text('Tu es sur le point de fermer l\'application.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Rester'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quitter'),
          ),
        ],
      ),
    );
    _confirmingExit = false;
    if (leave ?? false) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return HomeNavigator(
      go: _go,
      // canPop is false so every back press reaches _handleBack; the cost is
      // losing the Android 14 predictive-back animation on this route.
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) => _handleBack(didPop),
        child: Scaffold(
          // IndexedStack keeps each tab's scroll position and avoids rebuilding the
          // long lists on every switch.
          body: IndexedStack(
            index: _index,
            children: const [DashboardScreen(), AppsListScreen(), PermissionsListScreen()],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (index) => setState(() => _index = index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Résumé',
              ),
              NavigationDestination(
                icon: Icon(Icons.apps_outlined),
                selectedIcon: Icon(Icons.apps),
                label: 'Apps',
              ),
              NavigationDestination(
                icon: Icon(Icons.key_outlined),
                selectedIcon: Icon(Icons.key),
                label: 'Permissions',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
