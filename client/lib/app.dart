import 'package:flutter/material.dart';

import 'routing/app_routes.dart';
import 'theme/app_theme.dart';
import 'screens/arrival/arrival_screen.dart';
import 'screens/debug/api_health_check_screen.dart';
import 'screens/debug/floor_map_preview_screen.dart';
import 'screens/destination/destination_screen.dart';
import 'screens/map_shell/map_shell_screen.dart';
import 'screens/route_guide/route_guide_screen.dart';
import 'widgets/map_bottom_bar.dart';

class NavigationApp extends StatelessWidget {
  const NavigationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Navigation Client',
      theme: AppTheme.light,
      initialRoute: AppRoutes.outdoorMap,
      routes: {
        AppRoutes.outdoorMap: (context) => const MapShellScreen(),
        AppRoutes.indoorMap: (context) => const MapShellScreen(initialMode: MapMode.indoor),
        AppRoutes.destination: (context) => const DestinationScreen(),
        AppRoutes.routeGuide: (context) => const RouteGuideScreen(),
        AppRoutes.arrival: (context) => const ArrivalScreen(),
        AppRoutes.debugApiHealth: (context) => const ApiHealthCheckScreen(),
        AppRoutes.debugFloorMapPreview: (context) => const FloorMapPreviewScreen(),
      },
    );
  }
}
