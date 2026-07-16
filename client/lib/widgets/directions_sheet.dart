import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';

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
  });

  final String title;
  final String subtitle;
  final LatLng point;

  /// 실내 경로탐색(다익스트라)에 필요한 노드 ID. 야외 후보에는 없다.
  final String? nodeId;

  /// 실내 후보가 속한 층. 야외 후보에는 없다.
  final String? floor;
}

/// 길찾기 시트가 닫힐 때 돌려주는 결과. [origin]이 null이면 "현재 위치"를
/// 출발지로 쓴다는 뜻이다.
class DirectionsResult {
  const DirectionsResult({this.origin, required this.destination});

  final DirectionsCandidate? origin;
  final DirectionsCandidate destination;
}

enum _ActiveField { origin, destination }

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
  });

  /// 출발지를 따로 고르지 않았을 때 보여줄 문구("현재 위치").
  final String originLabel;
  final Future<List<DirectionsCandidate>> Function(String query) search;

  /// 매장 정보 시트의 "출발지로 설정"에서 넘어올 때처럼, 출발지가 이미
  /// 정해진 채로 시트를 열 때 채워둔다.
  final DirectionsCandidate? initialOrigin;

  /// 매장 정보 시트의 "도착지로 설정"에서 넘어올 때처럼, 도착지가 이미
  /// 정해진 채로 시트를 열 때 채워둔다. 검색창에 그 이름을 미리 채우고
  /// 검색 결과 목록에서 그대로 골라도 되고, 다른 검색어로 바꿔도 된다.
  final DirectionsCandidate? initialDestination;

  static Future<DirectionsResult?> show(
    BuildContext context, {
    required String originLabel,
    required Future<List<DirectionsCandidate>> Function(String query) search,
    DirectionsCandidate? initialOrigin,
    DirectionsCandidate? initialDestination,
  }) {
    return showModalBottomSheet<DirectionsResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DirectionsSheet(
        originLabel: originLabel,
        search: search,
        initialOrigin: initialOrigin,
        initialDestination: initialDestination,
      ),
    );
  }

  @override
  State<DirectionsSheet> createState() => _DirectionsSheetState();
}

class _DirectionsSheetState extends State<DirectionsSheet> {
  late final _originController = TextEditingController(
    text: widget.initialOrigin?.title ?? widget.originLabel,
  );
  late final _destinationController = TextEditingController(
    text: widget.initialDestination?.title ?? '',
  );
  final _destinationFocusNode = FocusNode();

  DirectionsCandidate? _selectedOrigin;
  DirectionsCandidate? _selectedDestination;
  _ActiveField _activeField = _ActiveField.destination;
  List<DirectionsCandidate> _results = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _selectedOrigin = widget.initialOrigin;
    _selectedDestination = widget.initialDestination;
    _search(_destinationController.text);
  }

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    _destinationFocusNode.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    final results = await widget.search(query);
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  /// 출발지 입력창을 처음 탭해 활성화할 때만 호출된다. 기본 문구("현재
  /// 위치"/미리 채워진 매장명)를 지우고 전체 목록을 보여준다 — 이미
  /// 출발지 입력 중일 때(커서 위치만 바꾸는 탭 등)는 타이핑한 내용을
  /// 지우면 안 되므로 다시 호출하지 않는다.
  void _onOriginTap() {
    if (_activeField == _ActiveField.origin) return;
    setState(() {
      _activeField = _ActiveField.origin;
      _originController.clear();
    });
    _search('');
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

  /// 출발지를 고른 뒤 호출한다. 도착지가 이미 정해져 있으면(예: "도착지로
  /// 설정"에서 넘어와 미리 채워진 경우) 다시 도착지를 고르게 하지 않고
  /// 바로 시트를 닫아 길찾기 경로를 보여준다. 아직 도착지가 없으면 기존처럼
  /// 도착지 입력으로 포커스만 넘긴다.
  void _afterOriginPicked() {
    final destination = _selectedDestination;
    if (destination != null) {
      Navigator.of(
        context,
      ).pop(DirectionsResult(origin: _selectedOrigin, destination: destination));
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '길찾기',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _originController,
                      onTap: _onOriginTap,
                      onChanged: _onOriginChanged,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.my_location, size: 18, color: AppColors.primary),
                        hintText: '출발지를 입력하세요',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _destinationController,
                      focusNode: _destinationFocusNode,
                      autofocus: true,
                      onTap: () => setState(() => _activeField = _ActiveField.destination),
                      onChanged: _onDestinationChanged,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.place_outlined, size: 20, color: AppColors.dest),
                        hintText: '도착지를 입력하세요',
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : (_results.isEmpty && !isOriginActive)
                        ? const Center(
                            child: Text('검색 결과가 없습니다', style: TextStyle(color: AppColors.muted)),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: _results.length + (isOriginActive ? 1 : 0),
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              if (isOriginActive && index == 0) {
                                return ListTile(
                                  leading: const Icon(Icons.my_location, color: AppColors.primary),
                                  title: const Text(
                                    '현재 위치',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                  ),
                                  onTap: _selectCurrentLocationAsOrigin,
                                );
                              }
                              final candidate = _results[index - (isOriginActive ? 1 : 0)];
                              return ListTile(
                                leading: const Icon(Icons.place, color: AppColors.primary),
                                title: Text(
                                  candidate.title,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
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
