import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../../models/route/route_plan_mode.dart';

/// 지도 상단의 검색과 경로 계획을 Runtime Kit 패턴에 연결한다.
///
/// 검색·경로 상태와 후보 조회는 상위가 소유하고, 이 위젯은 공개 패턴에 값과
/// callback만 전달한다. 경로 위치를 고치는 동안에는 planner 아래 검색 줄 하나만
/// 추가하며, 확정 뒤에는 planner만 남긴다.
class MapTopBar extends StatelessWidget {
  const MapTopBar({
    super.key,
    required this.onMenuTap,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.searchActive,
    required this.onCancelSearch,
    required this.onDirectionsTap,
    this.routeMode = false,
    this.routeEditingField,
    this.originController,
    this.destinationController,
    this.originFocus,
    this.destinationFocus,
    this.onOriginChanged,
    this.onDestinationChanged,
    this.onOriginPressed,
    this.onDestinationPressed,
    this.onCancelRouteEditing,
    this.onClearRouteDraft,
    this.onSwapRouteEndpoints,
    this.canSwapRouteEndpoints = false,
    this.selectedTravelMode = RoutePlanMode.walk,
    this.availableTravelModes = const [RoutePlanMode.walk],
    this.onTravelModeSelected,
    this.hintText = '건물, 장소를 검색하세요',
  });

  final VoidCallback onMenuTap;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final bool searchActive;
  final VoidCallback onCancelSearch;
  final VoidCallback onDirectionsTap;
  final bool routeMode;
  final RoutePlanField? routeEditingField;
  final TextEditingController? originController;
  final TextEditingController? destinationController;
  final FocusNode? originFocus;
  final FocusNode? destinationFocus;
  final ValueChanged<String>? onOriginChanged;
  final ValueChanged<String>? onDestinationChanged;
  final VoidCallback? onOriginPressed;
  final VoidCallback? onDestinationPressed;
  final VoidCallback? onCancelRouteEditing;
  final VoidCallback? onClearRouteDraft;
  final VoidCallback? onSwapRouteEndpoints;
  final bool canSwapRouteEndpoints;
  final RoutePlanMode selectedTravelMode;
  final List<RoutePlanMode> availableTravelModes;
  final ValueChanged<RoutePlanMode>? onTravelModeSelected;
  final String hintText;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
    child:
        routeMode && originController != null && destinationController != null
        ? _routePlanner()
        : _searchBar(),
  );

  Widget _searchBar() => RoutexSearchBar(
    placeholder: hintText,
    controller: controller,
    focusNode: focusNode,
    onSearchPressed: focusNode.requestFocus,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    onClear: () {
      controller.clear();
      onChanged('');
    },
    leading: searchActive ? RoutexSearchLeading.back : RoutexSearchLeading.menu,
    onLeadingPressed: searchActive ? onCancelSearch : onMenuTap,
    onDirectionsPressed: onDirectionsTap,
  );

  Widget _routePlanner() {
    final planner = RoutexRoutePlanner(
      originLabel: originController!.text.trim().isEmpty
          ? '현재 위치'
          : originController!.text,
      destinationLabel: destinationController!.text.trim().isEmpty
          ? '도착지를 정해 주세요'
          : destinationController!.text,
      travelModes: [
        for (final mode in availableTravelModes)
          RoutexTravelModeOption(
            id: mode.name,
            label: mode.label,
            icon: mode.icon,
          ),
      ],
      selectedTravelModeId: selectedTravelMode.name,
      onTravelModeSelected: (id) {
        final mode = RoutePlanMode.values.firstWhere((item) => item.name == id);
        onTravelModeSelected?.call(mode);
      },
      onOriginPressed: () {
        originFocus?.requestFocus();
        onOriginPressed?.call();
      },
      onDestinationPressed: () {
        destinationFocus?.requestFocus();
        onDestinationPressed?.call();
      },
      onClose: onClearRouteDraft,
      onDestinationMore: canSwapRouteEndpoints ? onSwapRouteEndpoints : null,
    );
    final field = routeEditingField;
    if (field == null) {
      return KeyedSubtree(key: const Key('route-planner'), child: planner);
    }

    final editingOrigin = field == RoutePlanField.origin;
    final activeController = editingOrigin
        ? originController!
        : destinationController!;
    final activeFocus = editingOrigin ? originFocus : destinationFocus;
    final activeChanged = editingOrigin
        ? onOriginChanged
        : onDestinationChanged;
    final cancelEditing = onCancelRouteEditing ?? () => activeFocus?.unfocus();
    return RoutexStack(
      gap: RoutexStackGap.control,
      children: [
        KeyedSubtree(key: const Key('route-planner'), child: planner),
        KeyedSubtree(
          key: Key(
            editingOrigin ? 'route-draft-origin' : 'route-draft-destination',
          ),
          child: RoutexSearchBar(
            placeholder: editingOrigin ? '출발지를 입력하세요' : '도착지를 입력하세요',
            controller: activeController,
            focusNode: activeFocus,
            onSearchPressed: activeFocus?.requestFocus,
            onChanged: activeChanged,
            onSubmitted: activeChanged,
            onClear: () {
              activeController.clear();
              activeChanged?.call('');
            },
            leading: RoutexSearchLeading.back,
            onLeadingPressed: cancelEditing,
          ),
        ),
      ],
    );
  }
}
