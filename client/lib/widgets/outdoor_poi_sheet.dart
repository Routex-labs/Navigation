import 'package:flutter/material.dart';

import '../models/outdoor_poi.dart';
import '../theme/app_theme.dart';
import 'map_overlay_guard.dart';
import 'sheet_grab_handle.dart';
import 'sheet_header.dart';
import 'transit_style.dart';

/// 야외 장소 시트에서 사용자가 고른 다음 행동.
enum OutdoorPoiAction {
  setOrigin,
  setDestination,

  /// 여기까지 **대중교통**으로 가는 경로를 본다. 도보 안내와 따로 두는 이유는
  /// 건물 밖 장소는 걸어서 30분 넘는 거리도 흔하기 때문이다 — 매장 시트에는
  /// 없던 선택지다.
  transit,
}

/// TMAP POI 검색 결과 한 건의 상세 시트.
///
/// 매장 시트([PlaceDetailSheet])와 나눠 둔 이유는 **가진 정보가 다르기**
/// 때문이다. 이쪽에는 층·노드·사진·메뉴가 없고 대신 주소·전화·직선 거리가
/// 있으며, 대중교통이라는 선택지가 하나 더 붙는다. 한 시트에 합치면 절반이
/// 늘 비어 있는 화면이 된다.
class OutdoorPoiSheet extends StatefulWidget {
  const OutdoorPoiSheet({
    super.key,
    required this.poi,
    required this.onCloseAll,
    this.transitEnabled = true,
  });

  final OutdoorPoi poi;
  final VoidCallback onCloseAll;

  /// TMAP 키가 없어 대중교통을 쓸 수 없으면 false. 버튼을 아예 감춘다 —
  /// 눌러서 "쓸 수 없습니다"를 보는 것보다 없는 편이 낫다.
  final bool transitEnabled;

  static Future<OutdoorPoiAction?> show(
    BuildContext context, {
    required OutdoorPoi poi,
    required VoidCallback onCloseAll,
    bool transitEnabled = true,
  }) {
    return showModalBottomSheet<OutdoorPoiAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // 매장 시트와 같은 이유로 barrier를 깔지 않는다 — 시트가 열리며 지도가
      // 그 장소로 이동하는데, 확인하러 온 그 지점이 어두워지면 안 된다.
      barrierColor: Colors.transparent,
      builder: (context) => MapOverlayGuard(
        child: OutdoorPoiSheet(
          poi: poi,
          onCloseAll: onCloseAll,
          transitEnabled: transitEnabled,
        ),
      ),
    );
  }

  @override
  State<OutdoorPoiSheet> createState() => _OutdoorPoiSheetState();
}

class _OutdoorPoiSheetState extends State<OutdoorPoiSheet> {
  /// 뒤로/X로 닫았는지, barrier 탭으로 닫았는지 구분한다(매장 시트와 동일 규칙).
  bool _intentionalPop = false;

  void _markIntentional() => _intentionalPop = true;

  void _pop(OutdoorPoiAction action) {
    _markIntentional();
    Navigator.of(context).pop(action);
  }

  @override
  Widget build(BuildContext context) {
    final poi = widget.poi;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_intentionalPop) widget.onCloseAll();
      },
      child: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        behavior: HitTestBehavior.opaque,
        child: DraggableScrollableSheet(
          initialChildSize: 0.42,
          minChildSize: 0.28,
          maxChildSize: 0.8,
          expand: false,
          builder: (context, scrollController) => GestureDetector(
            onTap: () {},
            behavior: HitTestBehavior.opaque,
            child: Material(
              color: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                controller: scrollController,
                padding: EdgeInsets.only(
                  bottom: 20 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SheetGrabHandle(),
                    SheetHeader(
                      onCloseAll: widget.onCloseAll,
                      onIntentionalPop: _markIntentional,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                      child: _PoiCore(poi: poi),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: _PoiActions(
                        transitEnabled: widget.transitEnabled,
                        onOrigin: () => _pop(OutdoorPoiAction.setOrigin),
                        onDestination: () =>
                            _pop(OutdoorPoiAction.setDestination),
                        onTransit: () => _pop(OutdoorPoiAction.transit),
                      ),
                    ),
                    if (poi.address != null || poi.telNo != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                        child: _PoiFacts(poi: poi),
                      ),
                    // 이 데이터가 우리 건물 DB가 아니라 외부 지도에서 왔다는 사실을
                    // 밝힌다. 매장 상세와 정보의 깊이가 다른 이유가 여기 있고,
                    // 실제와 다를 때 사용자가 어디를 의심할지도 알 수 있다.
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 18, 20, 0),
                      child: Text(
                        '지도 데이터 제공: TMAP',
                        style: TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PoiCore extends StatelessWidget {
  const _PoiCore({required this.poi});

  final OutdoorPoi poi;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = [
      if (poi.category != null) poi.category!,
      if (poi.distanceMeters != null)
        '약 ${formatTransitDistance(poi.distanceMeters!)}',
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.blue50,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.storefront_outlined,
            size: 24,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                poi.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              if (subtitleParts.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitleParts.join(' · '),
                  style: const TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ],
              const SizedBox(height: 4),
              const Text(
                '건물 밖 장소',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 주소·전화처럼 "이 지점이 맞는지" 확인하는 데 쓰는 줄.
class _PoiFacts extends StatelessWidget {
  const _PoiFacts({required this.poi});

  final OutdoorPoi poi;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (poi.address != null)
          _FactRow(icon: Icons.place_outlined, text: poi.address!),
        if (poi.telNo != null) ...[
          const SizedBox(height: 10),
          _FactRow(icon: Icons.call_outlined, text: poi.telNo!),
        ],
      ],
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 17, color: AppColors.muted),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(fontSize: 13.5, color: AppColors.text),
        ),
      ),
    ],
  );
}

/// 출발·도착·대중교통 한 줄. 매장 시트의 출발/도착 쌍과 자리·모양을 맞추고
/// 대중교통만 오른쪽에 덧붙인다 — 두 시트에서 같은 조작이 다른 자리에 있으면
/// 사용자는 매번 다시 찾는다.
class _PoiActions extends StatelessWidget {
  const _PoiActions({
    required this.onOrigin,
    required this.onDestination,
    required this.onTransit,
    required this.transitEnabled,
  });

  final VoidCallback onOrigin;
  final VoidCallback onDestination;
  final VoidCallback onTransit;
  final bool transitEnabled;

  @override
  Widget build(BuildContext context) => Row(
    key: const ValueKey('outdoor-poi-actions'),
    children: [
      FilledButton(
        onPressed: onOrigin,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.blue50,
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        ),
        child: const Text('출발'),
      ),
      const SizedBox(width: 8),
      FilledButton(
        onPressed: onDestination,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        ),
        child: const Text('도착'),
      ),
      if (transitEnabled) ...[
        const SizedBox(width: 8),
        OutlinedButton.icon(
          key: const ValueKey('outdoor-poi-transit'),
          onPressed: onTransit,
          icon: const Icon(Icons.directions_transit_rounded, size: 18),
          label: const Text('대중교통'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.blue200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ],
  );
}
