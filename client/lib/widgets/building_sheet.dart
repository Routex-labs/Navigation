import 'package:flutter/material.dart';

import '../models/building.dart';
import '../theme/app_theme.dart';
import 'map_overlay_guard.dart';
import 'sheet_grab_handle.dart';
import 'sheet_header.dart';

/// 건물 시트에서 사용자가 고른 다음 행동.
enum BuildingAction {
  /// 건물 안으로 들어가 **매장을 직접 고른다.** 지도를 건물로 확대하고 실내
  /// 오버레이를 켠 뒤, 사용자가 누른 매장이 도착지가 된다.
  pickStore,

  /// **건물까지만** 안내한다. 어느 매장에 갈지 아직 정하지 않았거나, 일단
  /// 건물 앞까지만 가면 되는 경우다.
  setDestination,

  setOrigin,

  /// 건물까지 대중교통으로 간다.
  transit,
}

/// 실내 도면을 가진 **우리 건물** 한 채의 시트.
///
/// [OutdoorPoiSheet]와 나눠 둔 이유는 **할 수 있는 일이 하나 더 있기**
/// 때문이다. 야외 POI는 좌표뿐이라 거기까지 걸어가는 것으로 끝나지만, 이
/// 건물은 층·매장·통행 그래프를 우리가 갖고 있어서 "건물 안 어느 매장까지"를
/// 이어서 안내할 수 있다. 한 시트에 합치면 그 버튼이 대부분의 POI에서 눌러도
/// 아무 일이 없는 죽은 버튼이 된다.
///
/// ## 왜 두 갈래로 묻나
///
/// 사용자가 검색창에 "더현대"를 친 순간의 의도는 두 가지로 갈린다.
///
/// - **건물이 목적지다.** "일단 그 앞까지 가자" — 도착/대중교통이 답이다.
/// - **건물은 경유지다.** 실제 목적지는 그 안의 매장인데 이름이 기억나지
///   않거나, 가서 고르려는 것이다 — 이때 건물 좌표로 안내를 끝내 버리면
///   정문 앞에서 안내가 끊기고 사용자는 검색을 처음부터 다시 한다.
///
/// 검색어만 보고는 어느 쪽인지 알 수 없다. 그래서 추측하지 않고 묻는다.
class BuildingSheet extends StatefulWidget {
  const BuildingSheet({
    super.key,
    required this.building,
    required this.onCloseAll,
    this.transitEnabled = true,
    this.routingEnabled = true,
  });

  final Building building;
  final VoidCallback onCloseAll;

  /// TMAP 키가 없어 대중교통을 쓸 수 없으면 false. 버튼을 아예 감춘다.
  final bool transitEnabled;

  /// 건물을 가리킬 야외 좌표를 하나도 못 구했으면 false
  /// ([Building.outdoorAnchor]도 null인 경우). 출발·도착·대중교통은 전부 그
  /// 좌표가 있어야 성립하므로 함께 감추고, **매장 선택만 남긴다** — 도면은
  /// 벡터 타일로 이미 떠 있으므로 건물 안 안내는 그대로 된다.
  final bool routingEnabled;

  static Future<BuildingAction?> show(
    BuildContext context, {
    required Building building,
    required VoidCallback onCloseAll,
    bool transitEnabled = true,
    bool routingEnabled = true,
  }) {
    return showModalBottomSheet<BuildingAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // 다른 시트와 같은 이유로 barrier를 깔지 않는다 — 시트가 열리며 지도가
      // 그 건물로 이동하는데, 확인하러 온 그 건물이 어두워지면 안 된다.
      barrierColor: Colors.transparent,
      builder: (context) => MapOverlayGuard(
        child: BuildingSheet(
          building: building,
          onCloseAll: onCloseAll,
          transitEnabled: transitEnabled,
          routingEnabled: routingEnabled,
        ),
      ),
    );
  }

  @override
  State<BuildingSheet> createState() => _BuildingSheetState();
}

class _BuildingSheetState extends State<BuildingSheet> {
  /// 뒤로/X로 닫았는지, barrier 탭으로 닫았는지 구분한다(다른 시트와 동일 규칙).
  bool _intentionalPop = false;

  void _markIntentional() => _intentionalPop = true;

  void _pop(BuildingAction action) {
    _markIntentional();
    Navigator.of(context).pop(action);
  }

  @override
  Widget build(BuildContext context) {
    final building = widget.building;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_intentionalPop) widget.onCloseAll();
      },
      child: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        behavior: HitTestBehavior.opaque,
        child: DraggableScrollableSheet(
          // 야외 POI 시트(0.42)보다 높게 연다. 여기에는 액션 줄이 하나 더 있어서
          // (매장 고르기 + 출발·도착·대중교통), 같은 높이로 열면 좁은 화면에서
          // 아래 줄이 화면 밖으로 밀린다 — 두 갈래를 묻는 시트인데 한 갈래가
          // 안 보이면 묻지 않은 것과 같다.
          initialChildSize: 0.55,
          minChildSize: 0.32,
          maxChildSize: 0.9,
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
                      child: _BuildingCore(building: building),
                    ),
                    // 매장 선택을 **위에, 한 줄 통째로** 둔다. 아래 출발/도착과
                    // 같은 줄에 끼우면 "건물까지"와 "건물 안까지"가 같은 무게로
                    // 보이는데, 실내 도면을 가진 건물에서 사용자가 실제로 원하는
                    // 것은 대개 안쪽이다.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: _PickStoreButton(
                        onPressed: () => _pop(BuildingAction.pickStore),
                      ),
                    ),
                    if (widget.routingEnabled)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                        child: _BuildingActions(
                          transitEnabled: widget.transitEnabled,
                          onOrigin: () => _pop(BuildingAction.setOrigin),
                          onDestination: () =>
                              _pop(BuildingAction.setDestination),
                          onTransit: () => _pop(BuildingAction.transit),
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Text(
                        '출발·도착은 건물 입구 기준이며, 건물 밖 이동은 TMAP 지도로 안내합니다.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                          height: 1.45,
                        ),
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

class _BuildingCore extends StatelessWidget {
  const _BuildingCore({required this.building});

  final Building building;

  @override
  Widget build(BuildContext context) {
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
            Icons.apartment_outlined,
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
                building.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '건물 · ${building.floors.length}개 층',
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 4),
              const Text(
                '건물 안 길안내 가능',
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

/// "건물 안에서 매장 고르기". 눌렀을 때 무엇이 일어나는지를 버튼 아래 한 줄로
/// 미리 알린다 — 지도가 갑자기 건물 도면으로 바뀌는 동작이라, 예고 없이 하면
/// 사용자는 화면이 엉뚱한 데로 갔다고 읽는다.
class _PickStoreButton extends StatelessWidget {
  const _PickStoreButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: const ValueKey('building-pick-store'),
          onPressed: onPressed,
          icon: const Icon(Icons.storefront_outlined, size: 19),
          label: const Text('건물 안에서 매장 고르기'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            textStyle: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        '지도를 이 건물로 옮기고 도면을 펴요. 매장을 누르면 그곳이 도착지가 됩니다.',
        style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.4),
      ),
    ],
  );
}

/// 출발·도착·대중교통 한 줄. 야외 POI 시트(`outdoor_poi_sheet.dart`)와 자리·
/// 모양·문구를 그대로 맞춘다 — 같은 조작이 시트마다 다른 자리에 있으면 사용자는
/// 매번 다시 찾는다. 여기서의 "도착"이 **건물 입구까지**라는 사실은 시트 맨
/// 아래 한 줄이 밝힌다.
class _BuildingActions extends StatelessWidget {
  const _BuildingActions({
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
    key: const ValueKey('building-actions'),
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
        key: const ValueKey('building-set-destination'),
        onPressed: onDestination,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.blue50,
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        ),
        child: const Text('도착'),
      ),
      if (transitEnabled) ...[
        const SizedBox(width: 8),
        OutlinedButton.icon(
          key: const ValueKey('building-transit'),
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
