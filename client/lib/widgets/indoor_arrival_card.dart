import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 실내 안내가 끝났음을 알리는 도착 카드.
///
/// 하단 배너([EtaCard])가 이미 "목적지에 도착했습니다" 한 줄을 말하지만,
/// 실기기에서는 그 줄이 **거의 읽히지 않았다.** 걷는 동안 계속 같은 자리에서
/// 문구만 바뀌던 띠라 눈이 이미 무시하고 있고, 도착 순간에도 화면에는 여전히
/// 경로선과 핀이 그려져 있어 "아직 가는 중"으로 보인다.
///
/// 그래서 도착만은 **자리와 크기를 바꾼다.** 지도 한가운데에 카드로 서고,
/// 사용자가 확인을 누를 때까지 남는다. 안내가 끝나는 자리이므로 이 카드의
/// 버튼이 곧 세션의 마침표다 — 누르면 목적지·경로·핀이 모두 정리된다.
///
/// 경로선은 이 카드가 뜨고 잠시 뒤 스스로 사라진다(`arrivalAutoClearDelay`).
/// 도착한 자리에서 지나온 선을 몇 초 더 보여 주는 것은 "여기까지 왔다"는
/// 확인이지만, 계속 남겨 두면 아직 갈 데가 있는 화면으로 읽힌다.
class IndoorArrivalCard extends StatelessWidget {
  const IndoorArrivalCard({
    super.key,
    required this.destinationName,
    required this.onConfirm,
    this.destinationFloor,
    this.onConfirmPointerDown,
  });

  final String destinationName;

  /// 층 라벨. 없으면 줄 자체를 그리지 않는다 — "· 도착"만 남은 줄은 정보가 아니다.
  final String? destinationFloor;

  final VoidCallback onConfirm;

  /// 버튼을 누른 지점. 지도(PlatformView)로 새어 나가는 탭을 상위가 막을 때 쓴다.
  final ValueChanged<Offset>? onConfirmPointerDown;

  @override
  Widget build(BuildContext context) {
    final floor = destinationFloor;
    return Material(
      color: AppColors.surface,
      elevation: AppElevation.overlay,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_rounded,
              size: 44,
              color: AppColors.primary,
            ),
            const SizedBox(height: 12),
            const Text(
              '도착했습니다',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              destinationName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            if (floor != null && floor.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                floor,
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ],
            const SizedBox(height: 16),
            Listener(
              onPointerDown: (event) =>
                  onConfirmPointerDown?.call(event.position),
              child: FilledButton(
                key: const Key('indoor-arrival-confirm'),
                onPressed: onConfirm,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(160, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('안내 종료'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
