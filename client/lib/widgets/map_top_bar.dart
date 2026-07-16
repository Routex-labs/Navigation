import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 지도 화면(야외/실내) 공통 상단 바. 실내 모드에서만 햄버거 버튼이 보인다.
///
/// 검색창은 장소의 "일반 정보"만 보여주는 용도이고, 실제 경로 안내는
/// 오른쪽 길찾기 아이콘이 여는 별도 입력 시트를 통해서만 시작된다 —
/// 이 둘을 분리해야 검색이 곧바로 내비게이션을 시작하지 않는다는 기획을 지킬 수 있다.
class MapTopBar extends StatefulWidget {
  const MapTopBar({
    super.key,
    required this.showHamburger,
    required this.onHamburgerTap,
    required this.onSearch,
    required this.onDirectionsTap,
    this.hintText = '건물, 장소를 검색하세요',
  });

  final bool showHamburger;
  final VoidCallback onHamburgerTap;
  final ValueChanged<String> onSearch;
  final VoidCallback onDirectionsTap;
  final String hintText;

  @override
  State<MapTopBar> createState() => _MapTopBarState();
}

class _MapTopBarState extends State<MapTopBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
              if (widget.showHamburger)
                IconButton(
                  onPressed: widget.onHamburgerTap,
                  icon: const Icon(Icons.menu, color: AppColors.muted),
                  tooltip: '건물 선택',
                ),
              if (!widget.showHamburger) const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  onSubmitted: widget.onSearch,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    hintText: widget.hintText,
                    hintStyle: const TextStyle(fontSize: 14, color: AppColors.muted),
                    prefixIcon: widget.showHamburger
                        ? null
                        : const Icon(Icons.search, size: 18, color: AppColors.muted),
                  ),
                ),
              ),
              IconButton(
                onPressed: widget.onDirectionsTap,
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
