import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/poi_search_result.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_theme.dart';

const _autoDismissDelay = Duration(seconds: 2);

class ArrivalScreen extends StatefulWidget {
  const ArrivalScreen({super.key});

  @override
  State<ArrivalScreen> createState() => _ArrivalScreenState();
}

class _ArrivalScreenState extends State<ArrivalScreen> {
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _autoDismissTimer = Timer(_autoDismissDelay, _startNewSearch);
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  void _startNewSearch() {
    _autoDismissTimer?.cancel();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.indoorMap, (route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final destination =
        ModalRoute.of(context)?.settings.arguments as PoiSearchResult?;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.success.withValues(alpha: 0.28),
                      blurRadius: 56,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.check_circle,
                  color: AppColors.success,
                  size: 50,
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                '도착했습니다!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                destination == null
                    ? '목적지에 도착했습니다'
                    : '${destination.name}에 도착했습니다',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14.5, color: AppColors.muted),
              ),
              if (destination != null) ...[
                const SizedBox(height: 4),
                Text(
                  destination.floor,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _startNewSearch,
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('새 목적지 탐색'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
