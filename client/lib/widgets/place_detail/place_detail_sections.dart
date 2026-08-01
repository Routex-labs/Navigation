import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'korean_line_break.dart';

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
///
/// 흰 시트 위에 흰 카드를 얹으면 테두리가 구분하는 대상이 없어 상자만 늘어난다.
/// 소개는 본문 문단 그대로 두고 여백으로만 앞뒤와 떨어뜨린다.
class PlaceSummarySection extends StatelessWidget {
  const PlaceSummarySection({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    keepWordsWhole(text),
    style: const TextStyle(fontSize: 14.5, height: 1.5, color: AppColors.text),
  );
}

/// 위치 안내처럼 라벨과 값이 한 쌍인 섹션.
///
/// 카드 대신 구분선만 쓴다. 같은 라벨-값 형태인 `PlaceBusinessInfoSection`과
/// 리듬을 맞춰 시트가 카드의 나열로 보이지 않게 한다.
class PlaceKeyValueSection extends StatelessWidget {
  const PlaceKeyValueSection({super.key, required this.items});

  final List<PlaceKeyValue> items;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var index = 0; index < items.length; index++) ...[
        if (index > 0) const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: _KeyValueRow(item: items[index]),
        ),
      ],
    ],
  );
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.item});

  final PlaceKeyValue item;

  // 라벨을 값 위 캡션으로 둔다 — `PlaceBusinessInfoSection`과 같은 이유이자 같은
  // 리듬이다.
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        item.label,
        style: const TextStyle(fontSize: 12, color: AppColors.muted),
      ),
      const SizedBox(height: 3),
      Text(
        keepWordsWhole(item.value),
        style: const TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.text),
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
  Widget build(BuildContext context) => _TintedBlock(
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
              Text(
                keepWordsWhole(text),
                style: const TextStyle(fontSize: 13, color: AppColors.text),
              ),
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
    return _TintedBlock(
      child: Row(
        children: [
          const Icon(Icons.map_outlined, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
          ),
          const Icon(Icons.chevron_right, size: 20, color: AppColors.muted),
        ],
      ),
    );
  }
}

/// 배경색으로만 구분하는 블록. 공지·지도 바로가기처럼 "본문이 아니라 하나의
/// 덩어리"인 것에만 쓴다. 테두리는 두지 않는다 — 배경색만으로 이미 구분된다.
class _TintedBlock extends StatelessWidget {
  const _TintedBlock({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.blue50,
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
}
