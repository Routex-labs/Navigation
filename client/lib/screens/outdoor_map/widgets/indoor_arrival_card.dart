import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// 실내 안내가 끝났음을 알리는 도착 카드.
///
/// [EtaCard]가 이미 같은 문구를 말하지만 실기기에서 **거의 읽히지 않았다** — 걷는
/// 동안 문구만 바뀌던 띠라 눈이 무시하고, 경로선과 핀이 남아 "아직 가는 중"으로
/// 보인다. 그래서 도착만은 **자리와 크기를 바꿔** 지도 한가운데에 세우고, 이 카드의
/// 버튼이 곧 세션의 마침표가 된다.
///
/// 경로선은 잠시 뒤 스스로 사라진다 — 남겨 두면 아직 갈 데가 있는 화면으로 읽힌다.
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
    // **띡 하고 나타나지 않는다.** 도착은 한 번뿐인 사건이라 등장 자체가 신호다.
    // 아주 살짝 커지며 떠오르게 해서 "방금 생긴 것"으로 읽히게 한다 — 길이는
    // 짧게 둔다(도착을 확인하려는 손을 기다리게 하면 안 된다).
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - t)),
          child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
        ),
      ),
      child: _card(),
    );
  }

  Widget _card() {
    final floor = destinationFloor;
    return ConstrainedBox(
      // 매장 이름이 길어도 카드가 화면 끝까지 늘어나지 않게 한다.
      constraints: const BoxConstraints(maxWidth: 320),
      child: Material(
        color: AppColors.surface,
        elevation: AppElevation.overlay,
        shadowColor: Colors.black.withValues(alpha: 0.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AppColors.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 체크는 아이콘 하나가 아니라 **원 안에** 둔다. 카드에서 제일 먼저
              // 눈이 닿는 자리라, 면이 있어야 "끝났다"가 한눈에 온다.
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 32,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              // **매장 이름이 제목이다.** "도착했습니다"를 크게 쓰던 시절에는
              // 정작 어디에 도착했는지가 두 번째 줄로 밀려, 카드를 다 읽어야
              // 알 수 있었다.
              Text(
                destinationName,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                floor == null || floor.isEmpty ? '도착했습니다' : '$floor · 도착했습니다',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 20),
              Listener(
                onPointerDown: (event) =>
                    onConfirmPointerDown?.call(event.position),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('indoor-arrival-confirm'),
                    onPressed: onConfirm,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(23),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('안내 종료'),
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
