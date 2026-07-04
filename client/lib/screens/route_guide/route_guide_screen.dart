import 'package:flutter/material.dart';

import '../../models/poi_search_result.dart';
import '../../routing/app_routes.dart';

class RouteGuideScreen extends StatelessWidget {
  const RouteGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final destination =
        ModalRoute.of(context)?.settings.arguments as PoiSearchResult?;

    return Scaffold(
      appBar: AppBar(title: const Text('경로 안내')),
      body: Center(
        child: Text(
          destination == null
              ? '경로 오버레이 / ETA 카드 예정'
              : '${destination.name} (${destination.floor}층)로 안내합니다\n(경로 오버레이 / ETA 카드 예정)',
          textAlign: TextAlign.center,
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: () {
              Navigator.of(context).pushNamed(AppRoutes.arrival);
            },
            child: const Text('도착'),
          ),
        ),
      ),
    );
  }
}
