import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';
import 'sheet_grab_handle.dart';

import 'map_overlay_guard.dart';

/// 길찾기 시트에서 고를 수 있는 출발지/도착지 후보. 야외 모드에서는 [Building],
/// 실내 모드에서는 [PoiSearchResult]를 이 공통 형태로 변환해 검색·선택
/// 로직을 하나의 시트 위젯으로 공유한다.
class DirectionsCandidate {
  const DirectionsCandidate({
    required this.title,
    required this.subtitle,
    required this.point,
    this.nodeId,
    this.floor,
    this.buildingId,
  });

  final String title;
  final String subtitle;
  final LatLng point;

  /// 실내 경로탐색(다익스트라)에 필요한 노드 ID. 야외 후보에는 없다.
  final String? nodeId;

  /// 실내 후보가 속한 층. 야외 후보에는 없다.
  final String? floor;

  /// 이 후보가 **건물 그 자체**일 때 그 건물 id. 건물 안의 매장이면 null이다.
  ///
  /// 좌표만으로는 둘을 구분할 수 없어서 따로 둔다. 구분이 필요한 이유는 건물이
  /// **목적지 하나로 끝나지 않기 때문**이다 — 사용자가 "더현대"를 골랐을 때
  /// 원하는 것이 건물 앞인지 그 안의 매장인지는 고른 것만 보고 알 수 없어서,
  /// 호출자가 이 값을 보고 되묻는 시트를 띄운다(`MapShellScreen._openDirections`).
  ///
  /// 목록의 아이콘도 이 값으로 갈린다. 건물과 매장이 같은 핀으로 보이면 무엇이
  /// 건물인지 읽을 방법이 없다.
  final String? buildingId;
}

/// "지도에서 선택"으로 정할 대상. 출발지·도착지 양쪽 모두 지도에서 고를 수
/// 있으므로, 어느 칸을 채우려는 것인지 호출자에게 알려야 한다. bool 하나로는
/// 표현할 수 없어 열거형으로 둔다.
enum DirectionsMapPickTarget { origin, destination }

/// 길찾기 시트가 닫힐 때 돌려주는 결과. [origin]이 null이면 "현재 위치"를
/// 출발지로 쓴다는 뜻이다.
class DirectionsResult {
  /// 도착지까지 정해져서 바로 경로를 그릴 수 있는 경우.
  const DirectionsResult({
    this.origin,
    required DirectionsCandidate this.destination,
  }) : pickOnMap = null;

  /// 도착지 칸에서 "지도에서 선택"을 누른 경우. 도착지는 아직 없고, 호출자가
  /// 지도에서 매장을 고르는 모드로 넘어가야 한다. 출발지는 시트에서 정한 값을
  /// 그대로 이어받는다.
  const DirectionsResult.pickDestinationOnMap({this.origin})
    : destination = null,
      pickOnMap = DirectionsMapPickTarget.destination;

  /// 출발지 칸에서 "지도에서 선택"을 누른 경우. 대칭으로, 출발지는 아직 없고
  /// **이미 고른 도착지를 되돌려준다** — 안 돌려주면 지도에서 출발지를 찍은
  /// 순간 도착지가 사라져 사용자가 처음부터 다시 입력하게 된다.
  const DirectionsResult.pickOriginOnMap({this.destination})
    : origin = null,
      pickOnMap = DirectionsMapPickTarget.origin;

  final DirectionsCandidate? origin;

  /// [pickOnMap]이 [DirectionsMapPickTarget.destination]이면 null이다.
  /// 그 경우 도착지는 지도 탭으로 정해진다.
  final DirectionsCandidate? destination;

  /// null이 아니면 시트는 "이 칸을 지도에서 고르겠다"는 의사만 전달한 것이다.
  final DirectionsMapPickTarget? pickOnMap;
}

enum _ActiveField { origin, destination }

/// [DirectionsSheet]가 부모(MapShellScreen)에 검색을 위임할 때 쓰는 콜백.
///
/// 길찾기 검색은 **항상 건물 전체**를 뒤진다. 예전에는 현재 층으로 좁히고
/// "전체 층에서 찾기" 토글로 넓히게 했는데, 길찾기는 원래 다른 층으로 가려고
/// 여는 기능이라 기본값이 반대였다 — 찾는 매장이 대부분 다른 층에 있어서
/// 사용자가 매번 토글을 켜야 결과가 나왔다.
typedef DirectionsSearchCallback =
    Future<List<DirectionsCandidate>> Function(String query);

/// "출발지 → 도착지" 입력 바텀시트. 두 입력 모두 탭하면 그 아래 검색 결과
/// 목록이 그 필드 기준으로 바뀐다. 출발지 목록의 맨 위에는 "현재 위치"가
/// 항상 고정으로 있어, 별도로 고르지 않으면 출발지는 현재 위치로 간주된다.
class DirectionsSheet extends StatefulWidget {
  const DirectionsSheet({
    super.key,
    required this.originLabel,
    required this.search,
    this.initialOrigin,
    this.initialDestination,
    this.focusOrigin = false,
  });

  /// 출발지를 따로 고르지 않았을 때 보여줄 문구("현재 위치").
  final String originLabel;
  final DirectionsSearchCallback search;

  /// 매장 정보 시트의 "출발지로 설정"에서 넘어올 때처럼, 출발지가 이미
  /// 정해진 채로 시트를 열 때 채워둔다.
  final DirectionsCandidate? initialOrigin;

  /// 매장 정보 시트의 "도착지로 설정"에서 넘어올 때처럼, 도착지가 이미
  /// 정해진 채로 시트를 열 때 채워둔다. 검색창에 그 이름을 미리 채우고
  /// 검색 결과 목록에서 그대로 골라도 되고, 다른 검색어로 바꿔도 된다.
  final DirectionsCandidate? initialDestination;

  /// 출발지 칸을 활성으로 열지. 상단 초안 바의 **출발 행**을 눌러 들어올 때 켠다 —
  /// 출발지를 바꾸려고 누른 것이므로 커서와 후보 목록이 그 칸에 맞아야 한다.
  /// 기본은 false로, 도착지를 고르는 기존 흐름이 그대로 유지된다.
  final bool focusOrigin;

  static Future<DirectionsResult?> show(
    BuildContext context, {
    required String originLabel,
    required DirectionsSearchCallback search,
    DirectionsCandidate? initialOrigin,
    DirectionsCandidate? initialDestination,
    bool focusOrigin = false,
  }) {
    return showModalBottomSheet<DirectionsResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => MapOverlayGuard(
        child: DirectionsSheet(
          originLabel: originLabel,
          search: search,
          initialOrigin: initialOrigin,
          initialDestination: initialDestination,
          focusOrigin: focusOrigin,
        ),
      ),
    );
  }

  @override
  State<DirectionsSheet> createState() => _DirectionsSheetState();
}

/// 검색창 바로 아래 줄. 목적지를 이름으로 찾지 않고 지도에서 직접 누르고 싶은
/// 사용자를 위한 지름길이다.
///
/// 이 줄이 필요한 이유: 지도에서 매장을 눌러 "출발지로 설정"하면 이 시트가
/// 곧바로 열리는데, 그 사용자는 방금 지도를 보고 있었으므로 나머지 한 쪽도
/// 지도에서 고르려 한다. 그런데 시트가 지도를 덮고 있어 시트를 닫는 방법밖에
/// 없었고, 닫으면 방금 지정한 값이 어디로 갔는지 알 수 없었다.
///
/// **출발지·도착지 양쪽에 똑같이 필요하다.** 지금 활성인 칸이 어느 쪽이냐에
/// 따라 [target]만 달라지고 자리와 생김새는 같다 — 두 칸의 조작 방법이 다르면
/// 사용자는 한쪽에만 있는 기능을 없는 것으로 여긴다.
class _PickOnMapTile extends StatelessWidget {
  const _PickOnMapTile({required this.target, required this.onTap});

  final DirectionsMapPickTarget target;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isOrigin = target == DirectionsMapPickTarget.origin;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          onTap: onTap,
          dense: true,
          leading: const Icon(
            Icons.touch_app_outlined,
            size: 20,
            color: AppColors.primary,
          ),
          title: const Text(
            '지도에서 선택',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          // 제목은 같아도 부제는 갈라야 한다. 출발지 칸에서 눌렀는데 "도착지로
          // 지정합니다"라고 적혀 있으면 사용자는 잘못 눌렀다고 판단해 되돌린다.
          subtitle: Text(
            isOrigin ? '지도에서 매장을 눌러 출발지로 지정합니다' : '지도에서 매장을 눌러 도착지로 지정합니다',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          trailing: const Icon(
            Icons.chevron_right,
            size: 18,
            color: AppColors.muted,
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _DirectionsSheetState extends State<DirectionsSheet> {
  late final _originController = TextEditingController(
    text: widget.initialOrigin?.title ?? widget.originLabel,
  );
  late final _destinationController = TextEditingController(
    text: widget.initialDestination?.title ?? '',
  );
  final _originFocusNode = FocusNode();
  final _destinationFocusNode = FocusNode();

  DirectionsCandidate? _selectedOrigin;
  DirectionsCandidate? _selectedDestination;
  late _ActiveField _activeField;
  List<DirectionsCandidate> _results = [];
  bool _loading = false;

  int _searchSeq = 0;

  @override
  void initState() {
    super.initState();
    _selectedOrigin = widget.initialOrigin;
    _selectedDestination = widget.initialDestination;
    if (widget.focusOrigin) {
      // 출발 행을 눌러 열렸다. 후보 목록도 출발지 기준(맨 위 "현재 위치" 고정 행)
      // 이어야 한다. 명시적 출발지가 없으면 칸에 적힌 "현재 위치"는 값이 아니라
      // 안내문이므로 지운다 — 그대로 두면 사용자가 먼저 지워야 하고, 검색어로도
      // 쓰여서 결과가 비어 버린다([_onOriginTap]과 같은 규칙).
      _activeField = _ActiveField.origin;
      if (widget.initialOrigin == null) _originController.clear();
      _search(_originController.text);
      return;
    }
    _activeField = _ActiveField.destination;
    _search(_destinationController.text);
  }

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    _originFocusNode.dispose();
    _destinationFocusNode.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    // 여러 검색이 겹쳐 뜰 수 있어(빠른 타이핑 등) 마지막 요청 결과만 반영하도록
    // 시퀀스로 스테일 응답을 버린다.
    final seq = ++_searchSeq;
    setState(() => _loading = true);
    final results = await widget.search(query);
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  /// 출발지 입력창을 처음 탭해 활성화할 때만 호출된다. 아직 명시적 출발지가
  /// 없을 때(=필드에 "현재 위치" placeholder만 있음)는 지워서 사용자가 바로
  /// 검색어를 칠 수 있게 하고, 지도에서 "출발지로 설정"으로 매장이 이미 채워진
  /// 경우처럼 실제 출발지가 있을 때는 그대로 남겨 사용자가 다시 입력하지 않아도
  /// 되게 한다(입력을 바꾸고 싶으면 그때 직접 지우거나 덮어쓰면 된다).
  /// 이미 출발지 입력 중일 때(커서 위치만 바꾸는 탭 등)는 타이핑한 내용을
  /// 지우면 안 되므로 다시 호출하지 않는다.
  void _onOriginTap() {
    if (_activeField == _ActiveField.origin) return;
    final hasExplicitOrigin = _selectedOrigin != null;
    setState(() {
      _activeField = _ActiveField.origin;
      if (!hasExplicitOrigin) _originController.clear();
    });
    _search(hasExplicitOrigin ? _originController.text : '');
  }

  void _onOriginChanged(String query) {
    setState(() => _activeField = _ActiveField.origin);
    _search(query);
  }

  void _onDestinationChanged(String query) {
    setState(() => _activeField = _ActiveField.destination);
    _search(query);
  }

  void _selectCurrentLocationAsOrigin() {
    setState(() {
      _selectedOrigin = null;
      _originController.text = widget.originLabel;
      _activeField = _ActiveField.destination;
    });
    _afterOriginPicked();
  }

  void _selectCandidate(DirectionsCandidate candidate) {
    if (_activeField == _ActiveField.origin) {
      setState(() {
        _selectedOrigin = candidate;
        _originController.text = candidate.title;
        _activeField = _ActiveField.destination;
      });
      _afterOriginPicked();
      return;
    }
    _selectedDestination = candidate;
    Navigator.of(
      context,
    ).pop(DirectionsResult(origin: _selectedOrigin, destination: candidate));
  }

  /// "지도에서 선택" — 도착지를 검색으로 찾지 않고 지도에서 직접 누르겠다는 뜻.
  ///
  /// 시트가 지도를 덮고 있는 동안에는 매장을 누를 수 없으므로 여기서 닫고,
  /// 실제 선택은 호출자(MapShellScreen)가 지도 위에서 이어받는다. 지금까지 고른
  /// 출발지는 함께 돌려줘서 사용자가 다시 입력하지 않게 한다.
  void _pickDestinationOnMap() {
    Navigator.of(
      context,
    ).pop(DirectionsResult.pickDestinationOnMap(origin: _selectedOrigin));
  }

  /// "지도에서 선택" — 출발지 쪽. 도착지 쪽과 대칭이며, 이번에는 **이미 고른
  /// 도착지**를 돌려준다. 안 돌려주면 지도에서 출발지를 찍는 순간 도착지가
  /// 사라져, 방금까지 채워두었던 칸을 다시 입력하게 된다.
  void _pickOriginOnMap() {
    Navigator.of(
      context,
    ).pop(DirectionsResult.pickOriginOnMap(destination: _selectedDestination));
  }

  /// 출발지를 고른 뒤 호출한다. 도착지가 이미 정해져 있으면(예: "도착지로
  /// 설정"에서 넘어와 미리 채워진 경우) 다시 도착지를 고르게 하지 않고
  /// 바로 시트를 닫아 길찾기 경로를 보여준다. 아직 도착지가 없으면 기존처럼
  /// 도착지 입력으로 포커스만 넘긴다.
  void _afterOriginPicked() {
    final destination = _selectedDestination;
    if (destination != null) {
      Navigator.of(context).pop(
        DirectionsResult(origin: _selectedOrigin, destination: destination),
      );
      return;
    }
    _destinationFocusNode.requestFocus();
    _search(_destinationController.text);
  }

  @override
  Widget build(BuildContext context) {
    final isOriginActive = _activeField == _ActiveField.origin;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 이 시트는 헤더(제목·입력창)가 스크롤 밖에 있어서 손잡이를 끌면
              // 크기 조절이 아니라 시트 자체가 끌린다(끌어서 닫기). 표시의
              // 의미는 같으므로 다른 시트와 같은 자리에 같은 모양으로 둔다.
              const SheetGrabHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '길찾기',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _originController,
                      focusNode: _originFocusNode,
                      autofocus: widget.focusOrigin,
                      onTap: _onOriginTap,
                      onChanged: _onOriginChanged,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(
                          Icons.my_location,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        hintText: '출발지를 입력하세요',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _destinationController,
                      focusNode: _destinationFocusNode,
                      autofocus: !widget.focusOrigin,
                      onTap: () => setState(
                        () => _activeField = _ActiveField.destination,
                      ),
                      onChanged: _onDestinationChanged,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(
                          Icons.place_outlined,
                          size: 20,
                          color: AppColors.dest,
                        ),
                        hintText: '도착지를 입력하세요',
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // 검색창 바로 아래. 지금 활성인 칸을 지도에서 채운다 — 출발지
              // 칸이면 출발지를, 도착지 칸이면 도착지를 고르는 모드로 넘어간다.
              _PickOnMapTile(
                target: isOriginActive
                    ? DirectionsMapPickTarget.origin
                    : DirectionsMapPickTarget.destination,
                onTap: isOriginActive
                    ? _pickOriginOnMap
                    : _pickDestinationOnMap,
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : (_results.isEmpty && !isOriginActive)
                    ? const Center(
                        child: Text(
                          '검색 결과가 없습니다',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _results.length + (isOriginActive ? 1 : 0),
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (isOriginActive && index == 0) {
                            return ListTile(
                              leading: const Icon(
                                Icons.my_location,
                                color: AppColors.primary,
                              ),
                              title: const Text(
                                '현재 위치',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              onTap: _selectCurrentLocationAsOrigin,
                            );
                          }
                          final candidate =
                              _results[index - (isOriginActive ? 1 : 0)];
                          return ListTile(
                            // 건물과 건물 안 매장을 아이콘으로 가른다. 같은
                            // 핀으로 두면 목록에서 무엇이 건물인지 읽을
                            // 방법이 없다.
                            leading: Icon(
                              candidate.buildingId == null
                                  ? Icons.place
                                  : Icons.apartment_outlined,
                              color: AppColors.primary,
                            ),
                            title: Text(
                              candidate.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(candidate.subtitle),
                            onTap: () => _selectCandidate(candidate),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
