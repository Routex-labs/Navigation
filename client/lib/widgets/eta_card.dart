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

  /// 있으면 카드 우상단에 닫기(X) 버튼을 보여준다. 사용자가 길찾기로 직접
  /// 고른 경로를 취소할 때만 쓰고, 자동 안내(예: 건물 입구까지)에는 null.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 14, onClose != null ? 8 : 16, 14),
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
            if (onClose != null)
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 18, color: AppColors.muted),
              ),
          ],
        ),
      ),
    );
  }
}
