import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 상세 API의 `keyValue` 항목을 렌더러에 넘길 때 쓰는 작은 표시 모델.
///
/// 네트워크 모델을 위젯 트리에 그대로 퍼뜨리지 않는다. 시트는 API 모델의
/// `KeyValueItem`을 이 타입으로 한 번 변환하고, 이 폴더의 위젯은 표시만 맡는다.
class PlaceKeyValue {
  const PlaceKeyValue({required this.label, required this.value});

  final String label;
  final String value;
}

/// 한 줄 소개 섹션.
class PlaceSummarySection extends StatelessWidget {
  const PlaceSummarySection({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => _SectionCard(
    child: Text(
      text,
      style: const TextStyle(fontSize: 14, height: 1.45, color: AppColors.text),
    ),
  );
}

/// 위치 안내처럼 라벨과 값이 한 쌍인 섹션.
class PlaceKeyValueSection extends StatelessWidget {
  const PlaceKeyValueSection({super.key, required this.items});

  final List<PlaceKeyValue> items;

  @override
  Widget build(BuildContext context) => _SectionCard(
    child: Column(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          _KeyValueRow(item: items[index]),
          if (index != items.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1),
            ),
        ],
      ],
    ),
  );
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.item});

  final PlaceKeyValue item;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 72,
        child: Text(
          item.label,
          style: const TextStyle(fontSize: 13, color: AppColors.muted),
        ),
      ),
      Expanded(
        child: Text(
          item.value,
          style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.text),
        ),
      ),
    ],
  );
}

/// 특징 chip 묶음.
class PlaceTagsSection extends StatelessWidget {
  const PlaceTagsSection({super.key, required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final tag in tags)
        Chip(
          label: Text(tag),
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
          backgroundColor: AppColors.blue50,
          side: const BorderSide(color: AppColors.blue100),
          visualDensity: VisualDensity.compact,
        ),
    ],
  );
}

/// 기간이 명시된 안내. 서버 검증기가 만료된 notice를 막기 때문에 여기서는
/// 날짜를 판단하지 않고 API가 준 문자열을 그대로 표시한다.
class PlaceNoticeSection extends StatelessWidget {
  const PlaceNoticeSection({super.key, required this.text, this.until});

  final String text;
  final String? until;

  @override
  Widget build(BuildContext context) => _SectionCard(
    color: AppColors.blue50,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.campaign_outlined, size: 19, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: const TextStyle(fontSize: 13, color: AppColors.text)),
              if (until != null) ...[
                const SizedBox(height: 4),
                Text(
                  '$until까지',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

/// MapLibre 미리보기는 첫 프레임에 별도 지도·타일 요청을 만들기 때문에 이 Wave에서
/// 넣지 않는다. 이 섹션은 위치가 있다는 사실만 가볍게 알려 주고, 실제 지도 이동은
/// 기존 지도 화면과 후속 상호작용에 맡긴다.
class PlaceMapSection extends StatelessWidget {
  const PlaceMapSection({super.key, this.floorLabel});

  final String? floorLabel;

  @override
  Widget build(BuildContext context) {
    final label = floorLabel == null || floorLabel!.isEmpty
        ? '지도에서 위치 확인'
        : '${floorLabel!} 위치';
    return _SectionCard(
      color: AppColors.blue50,
      child: Row(
        children: [
          const Icon(Icons.map_outlined, color: AppColors.primary),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child, this.color = AppColors.surface});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.blue100),
    ),
    child: child,
  );
}
