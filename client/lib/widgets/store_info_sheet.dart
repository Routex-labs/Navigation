import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 매장 정보 시트에서 사용자가 고를 수 있는 다음 동작.
enum StoreInfoAction { setOrigin, setDestination }

/// 실내 검색에서 매장을 고르면 뜨는 정보 시트. 길찾기 시트와 같은 형태로
/// 아래에서 올라온다. 매장 상세 정보(사진·설명 등)는 아직 백엔드에 없어
/// 비워두고, 우하단의 출발지/도착지 버튼으로 바로 길찾기 시트로 넘어갈 수
/// 있게만 한다.
class StoreInfoSheet extends StatelessWidget {
  const StoreInfoSheet({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  static Future<StoreInfoAction?> show(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    return showModalBottomSheet<StoreInfoAction>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StoreInfoSheet(title: title, subtitle: subtitle),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.42,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF3FF),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.storefront, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // 매장 상세 정보(사진·설명 등)는 아직 준비되지 않아 비워둔다.
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.bottomRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(StoreInfoAction.setOrigin),
                      child: const Text('출발'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(StoreInfoAction.setDestination),
                      child: const Text('도착'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
