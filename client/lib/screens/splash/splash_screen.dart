import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/service_locator.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_theme.dart';

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
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-0.4, -1),
            end: Alignment(0.6, 1),
            colors: [Color(0xFF1A73E8), Color(0xFF0A47B0), Color(0xFF0A3B92)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              if (_requestingPermissions)
                LinearProgressIndicator(
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  color: Colors.white.withValues(alpha: 0.85),
                  minHeight: 3,
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
                  child: Column(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.28),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.24),
                                    blurRadius: 44,
                                    offset: const Offset(0, 16),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.explore,
                                color: Colors.white,
                                size: 52,
                              ),
                            ),
                            const SizedBox(height: 22),
                            const Text(
                              'Navigation',
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.8,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '실내외 통합 내비게이션',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.62),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.16),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '앱 실행에 필요한 권한',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.92),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _PermissionRow(
                              icon: Icons.location_on,
                              text: '위치 — 실외 GPS 및 건물 입구 감지',
                            ),
                            const SizedBox(height: 7),
                            _PermissionRow(
                              icon: Icons.sensors,
                              text: '센서 — 가속도계·자이로 (PDR 측위)',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primary,
                            shadowColor: Colors.black.withValues(alpha: 0.18),
                            elevation: 6,
                          ),
                          onPressed: () {
                            Navigator.of(context).pushNamed(AppRoutes.outdoorMap);
                          },
                          child: const Text('시작하기'),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pushNamed(AppRoutes.debugApiHealth);
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white.withValues(alpha: 0.55),
                            ),
                            child: const Text('API 상태 확인 (dev)'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(
                                context,
                              ).pushNamed(AppRoutes.debugFloorMapPreview);
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white.withValues(alpha: 0.55),
                            ),
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
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white.withValues(alpha: 0.55),
                            ),
                            child: const Text('실내 지도 바로 보기 (dev)'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.85)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.80)),
          ),
        ),
      ],
    );
  }
}
