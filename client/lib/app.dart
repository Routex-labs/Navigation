import 'package:flutter/material.dart';

import 'routing/app_routes.dart';
import 'screens/arrival/arrival_screen.dart';
import 'screens/debug/api_health_check_screen.dart';
import 'screens/debug/floor_map_preview_screen.dart';
import 'screens/destination/destination_screen.dart';
import 'screens/indoor_map/indoor_map_screen.dart';
import 'screens/outdoor_map/outdoor_map_screen.dart';
import 'screens/route_guide/route_guide_screen.dart';
import 'screens/splash/splash_screen.dart';

class NavigationApp extends StatelessWidget {
  const NavigationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Navigation Client',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      initialRoute: AppRoutes.splash,
      routes: {
        AppRoutes.splash: (context) => const SplashScreen(),
        AppRoutes.outdoorMap: (context) => const OutdoorMapScreen(),
        AppRoutes.indoorMap: (context) => const IndoorMapScreen(),
        AppRoutes.destination: (context) => const DestinationScreen(),
        AppRoutes.routeGuide: (context) => const RouteGuideScreen(),
        AppRoutes.arrival: (context) => const ArrivalScreen(),
        AppRoutes.debugApiHealth: (context) => const ApiHealthCheckScreen(),
        AppRoutes.debugFloorMapPreview: (context) => const FloorMapPreviewScreen(),
      },
    );
  }
}
