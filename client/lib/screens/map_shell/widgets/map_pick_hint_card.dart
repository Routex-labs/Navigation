import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../models/directions_candidate.dart';

/// "지도에서 선택"을 누른 뒤 지도 위에 뜨는 안내.
///
/// 시트가 닫힌 자리에 아무 표시도 없으면, 사용자는 방금 누른 버튼이 먹지 않은
/// 것으로 본다. 지금 무엇을 눌러야 하는지와 반대쪽 칸이 무엇으로 잡혀 있는지를
/// 함께 보여주고, 마음이 바뀌면 그 자리에서 취소할 수 있게 한다.
class MapPickHintCard extends StatelessWidget {
  const MapPickHintCard({
    super.key,
    required this.target,
    required this.counterpartLabel,
    required this.onCancel,
  });

  /// 지금 지도에서 고르는 중인 칸.
  final DirectionsMapPickTarget target;

  /// 반대쪽 칸에 잡혀 있는 것. 아직 없으면 null이며, 그때는 줄 자체를 그리지
  /// 않는다 — "도착: " 뒤가 비어 있으면 값을 못 읽은 것처럼 보인다.
  final String? counterpartLabel;

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final isOrigin = target == DirectionsMapPickTarget.origin;
    final counterpart = counterpartLabel;
    // 색을 지정하지 않는다 — 테마 카드(surface + hairline)가 앱의 카드 문법이고,
    // 파란 면(blue50)을 깔면 이 카드만 EtaCard·검색 패널과 다른 톤이 된다.
    // 포인트는 아이콘의 primary 하나로 충분하다.
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            const Icon(
              Icons.touch_app_outlined,
              color: AppColors.primary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 복도도 고를 수 있게 된 뒤로 "매장을 눌러주세요"는 틀린
                  // 안내가 됐다. 안내가 매장만 말하면 복도를 눌러도 된다는 걸
                  // 아무도 모르고, 매장이 없는 자리를 눌러 본 사용자는 앱이
                  // 반응하지 않는다고 읽는다.
                  Text(
                    isOrigin
                        ? '출발지로 지정할 매장이나 복도를 지도에서 눌러주세요'
                        : '도착지로 지정할 매장이나 복도를 지도에서 눌러주세요',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  if (counterpart != null)
                    Text(
                      isOrigin ? '도착: $counterpart' : '출발: $counterpart',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: '지도에서 선택 취소',
              onPressed: onCancel,
              icon: const Icon(Icons.close, size: 18, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
