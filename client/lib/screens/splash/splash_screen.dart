import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/service_locator.dart';
import '../../routing/app_routes.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _requestingPermissions = true;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    var anyDenied = false;
    try {
      final statuses = await requestStartupPermissions();
      anyDenied = statuses.values.any((status) => !status.isGranted);
    } catch (_) {
      // 권한 플러그인을 쓸 수 없는 환경(테스트 등)에서도 앱을 계속 진행한다.
    }

    if (!mounted) return;
    setState(() => _requestingPermissions = false);

    if (anyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('일부 권한이 거부되어 위치·실내 이동 관련 기능이 제한될 수 있습니다'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (_requestingPermissions) const LinearProgressIndicator(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Navigation', style: TextStyle(fontSize: 28)),
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: () {
                        Navigator.of(context).pushNamed(AppRoutes.outdoorMap);
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('시작하기'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pushNamed(AppRoutes.debugApiHealth);
                      },
                      child: const Text('API 상태 확인 (dev)'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pushNamed(AppRoutes.debugFloorMapPreview);
                      },
                      child: const Text('더현대 서울 평면도 미리보기 (dev)'),
                    ),
                    TextButton(
                      onPressed: () {
                        // 실제 실내 지도는 야외 지도에서 GPS로 건물 입구를 감지해야
                        // 들어갈 수 있는데, 데모 건물 입구가 고정 좌표(서울시청 부근)라
                        // 그 자리에 있지 않으면 실기기에서 도달할 방법이 없다.
                        // 목적지 검색/경로 안내까지 바로 테스트할 수 있게 지름길을 둔다.
                        Navigator.of(context).pushNamed(AppRoutes.indoorMap);
                      },
                      child: const Text('실내 지도 바로 보기 (dev)'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
