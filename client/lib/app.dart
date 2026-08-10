import 'dart:async';

import 'package:flutter/material.dart';

import 'core/service_locator.dart';
import 'routing/app_routes.dart';
import 'theme/app_theme.dart';
import 'screens/arrival/arrival_screen.dart';
import 'screens/debug/api_health_check_screen.dart';
import 'screens/debug/floor_map_preview_screen.dart';
import 'screens/debug/pdr_svg_test_screen.dart';
import 'screens/destination/destination_screen.dart';
import 'screens/map_shell/map_shell_screen.dart';
import 'screens/route_guide/route_guide_screen.dart';

void defaultPdrBackgrounded() {
  unawaited(indoorNavigationDriver.onAppBackgrounded());
}

void defaultPdrForegrounded() {
  unawaited(indoorNavigationDriver.onAppForegrounded());
}

class NavigationApp extends StatefulWidget {
  const NavigationApp({
    super.key,
    this.onPdrBackgrounded = defaultPdrBackgrounded,
    this.onPdrForegrounded = defaultPdrForegrounded,
    this.home,
  });

  final VoidCallback onPdrBackgrounded;
  final VoidCallback onPdrForegrounded;
  final Widget? home;

  @override
  State<NavigationApp> createState() => _NavigationAppState();
}

class _NavigationAppState extends State<NavigationApp>
    with WidgetsBindingObserver {
  bool _pdrBackgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_pdrBackgrounded) return;
      _pdrBackgrounded = false;
      widget.onPdrForegrounded();
      return;
    }
    // iOS의 inactive는 알림 센터·시스템 시트·권한 UI에서도 잠깐 발생한다.
    // 이 짧은 상태에서 센서를 stop하면 곧바로 오는 resumed의 start와 경합해
    // EventChannel 구독만 남고 native motion이 멈출 수 있다.
    if (state == AppLifecycleState.inactive) return;
    if (_pdrBackgrounded) return;
    _pdrBackgrounded = true;
    widget.onPdrBackgrounded();
  }

  @override
  Widget build(BuildContext context) {
    final routes = <String, WidgetBuilder>{
      AppRoutes.outdoorMap: (context) => const MapShellScreen(),
      // 실내 전용 화면이 없어진 뒤에도 이 라우트는 남긴다. 도착 화면이
      // pushNamedAndRemoveUntil로 여기를 부르고, 지도는 하나뿐이라 같은
      // 셸로 보내면 된다.
      AppRoutes.indoorMap: (context) => const MapShellScreen(),
      AppRoutes.destination: (context) => const DestinationScreen(),
      AppRoutes.routeGuide: (context) => const RouteGuideScreen(),
      AppRoutes.arrival: (context) => const ArrivalScreen(),
      AppRoutes.debugApiHealth: (context) => const ApiHealthCheckScreen(),
      AppRoutes.debugFloorMapPreview: (context) =>
          const FloorMapPreviewScreen(),
      AppRoutes.pdrSvgTest: (context) => const PdrSvgTestScreen(),
    };
    if (widget.home != null) {
      routes.remove(AppRoutes.outdoorMap);
    }
    return MaterialApp(
      title: 'Navigation Client',
      theme: AppTheme.light,
      home: widget.home,
      initialRoute: widget.home == null ? AppRoutes.outdoorMap : null,
      routes: routes,
    );
  }
}
