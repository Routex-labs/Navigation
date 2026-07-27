import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 지도 화면(야외/실내) 공통 상단 바. 실내 모드에서만 햄버거 버튼이 보인다.
///
/// 검색창은 장소의 "일반 정보"만 보여주는 용도이고, 실제 경로 안내는
/// 오른쪽 길찾기 아이콘이 여는 별도 입력 시트를 통해서만 시작된다 —
/// 이 둘을 분리해야 검색이 곧바로 내비게이션을 시작하지 않는다는 기획을 지킬 수 있다.
///
/// **여기서 직접 입력받지 않는다.** 탭하면 [onSearchTap]이 아래에서 검색 시트를
/// 올리고, 입력과 결과 목록은 그 시트가 함께 보여준다. 예전처럼 상단 바에서
/// 곧장 검색하면 결과를 놓을 자리가 없어 스낵바로만 알리게 되고, 사용자에게는
/// "쳤는데 아무것도 안 나온다"로 보였다.
class MapTopBar extends StatelessWidget {
  const MapTopBar({
    super.key,
    required this.showHamburger,
    required this.onHamburgerTap,
    required this.onSearchTap,
    required this.onDirectionsTap,
    this.hintText = '건물, 장소를 검색하세요',
  });

  final bool showHamburger;
  final VoidCallback onHamburgerTap;

  /// 검색창을 탭했을 때. 상위가 검색 시트를 연다.
  final VoidCallback onSearchTap;
  final VoidCallback onDirectionsTap;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.15),
          child: Row(
            children: [
              if (showHamburger)
                IconButton(
                  onPressed: onHamburgerTap,
                  icon: const Icon(Icons.menu, color: AppColors.muted),
                  tooltip: '건물 선택',
                ),
              if (!showHamburger) const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: onSearchTap,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      children: [
                        if (!showHamburger) ...[
                          const Icon(
                            Icons.search,
                            size: 18,
                            color: AppColors.muted,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            hintText,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: onDirectionsTap,
                icon: const Icon(Icons.directions, color: AppColors.primary),
                tooltip: '길찾기',
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
