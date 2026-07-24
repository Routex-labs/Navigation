import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 예상 도착 시간 카드 (design.md 공통 컴포넌트: EtaCard).
class EtaCard extends StatelessWidget {
  const EtaCard({
    super.key,
    required this.distanceMeters,
    required this.minutes,
    this.label = '목적지까지',
    this.onClose,
  });

  final double distanceMeters;
  final int minutes;
  final String label;

  /// 있으면 카드 오른쪽에 "안내 종료" 버튼을 보여준다. 사용자가 길찾기로
  /// 직접 고른 경로를 취소할 때만 쓰고, 자동 안내(예: 건물 입구까지)에는
  /// null이라 버튼이 사라진다.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 11, color: AppColors.muted),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                      children: [
                        TextSpan(text: '약 $minutes분 '),
                        TextSpan(
                          text: '/ ${distanceMeters.round()}m',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (onClose != null) ...[
              const SizedBox(width: 8),
              // "안내 종료"는 되돌리기 어려운 조작(경로/도착지 리셋)이므로
              // 색상은 부드럽되, 다른 카드 요소보다 명확히 눌러야 할 지점으로
              // 읽히도록 outlined 톤을 준다.
              TextButton(
                onPressed: onClose,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFD93025),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(color: Color(0x33D93025)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('안내 종료'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
