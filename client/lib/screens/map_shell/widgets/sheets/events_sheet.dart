import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:routex_design_system/routex_design_system.dart';

import '../../../../service_locator.dart';
import '../../../../core/api_config.dart';
import '../../../../domain/event/building_events.dart';
import 'event_poster_view.dart';
import '../../../../models/place/store_index_entry.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/map_overlay_guard.dart';
import '../../../../widgets/map_pass_through_sheet_route.dart';
import '../../../../widgets/sheet_header.dart';

/// 오늘 이 건물에서 열리는 행사 목록. 한 줄을 누르면 그 매장의
/// [StoreIndexEntry]로 pop해서, 호출자가 **검색 후보를 고른 것과 같은 경로**로
/// 상세와 안내를 잇는다.
///
/// 원본과 수집 방법은 `docs/client/thehyundai-event-source.md`.
class EventsSheet extends StatefulWidget {
  const EventsSheet({super.key, required this.onCloseAll});

  final VoidCallback onCloseAll;

  static Future<StoreIndexEntry?> show(
    BuildContext context, {
    required VoidCallback onCloseAll,
  }) {
    // 카테고리 목록 시트와 **같은 라우트**다 — 뒤 지도를 얼리지 않으려는 이유가
    // 같다([MapPassThroughSheetRoute]).
    final navigator = Navigator.of(context);
    return navigator.push<StoreIndexEntry>(
      MapPassThroughSheetRoute<StoreIndexEntry>(
        capturedThemes: InheritedTheme.capture(
          from: context,
          to: navigator.context,
        ),
        isScrollControlled: true,
        isDismissible: true,
        backgroundColor: Colors.transparent,
        builder: (context) =>
            MapOverlayGuard(child: EventsSheet(onCloseAll: onCloseAll)),
      ),
    );
  }

  @override
  State<EventsSheet> createState() => _EventsSheetState();
}

/// 행사 한 줄과 그 줄이 열 매장을 한 쌍으로 묶는다. 매장을 못 찾으면 [entry]가
/// null이고 줄은 눌리지 않는다.
class _Row {
  const _Row(this.event, this.entry);
  final BuildingEvent event;
  final StoreIndexEntry? entry;
}

/// 매장 색인을 기다리는 시한. 색인은 안내를 걸기 위한 것이지 목록을 그리기 위한
/// 것이 아니라, 못 받으면 기다리지 않고 장소 문구만으로 목록을 낸다.
const _indexTimeout = Duration(seconds: 6);

class _EventsSheetState extends State<EventsSheet> {
  late final Future<List<_Row>> _rowsFuture = _load();
  bool _intentionalPop = false;

  void _markIntentional() => _intentionalPop = true;

  /// 오늘 날짜(`YYYY-MM-DD`). 기기 로컬 시각을 쓴다 — 행사 기간도 현지 날짜다.
  static String _today() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  Future<List<_Row>> _load() async {
    final source = await rootBundle.loadString('assets/mock/events.json');
    final open = parseBuildingEvents(source).openOn(_today());
    // 매장 색인은 검색이 이미 받아 두는 것과 **같은 캐시**다(같은 건물이면 두 번째
    // 부터 즉시 온다). 실패하면 안내만 빠지고 목록은 그대로 뜬다.
    //
    // **시한을 건다.** 목록 자체는 에셋만으로 그릴 수 있는데 색인을 시한 없이
    // 기다리면, 서버에 닿지 못하는 상황에서 예외가 아니라 **멎는다** — 그때
    // 화면에는 영영 도는 스피너만 남는다(실기기에서 실제로 그랬다).
    List<StoreIndexEntry>? index;
    try {
      index = await buildingRepository
          .getStoreIndex(demoBuildingId)
          .timeout(_indexTimeout);
    } on Object {
      index = null;
    }
    final byId = {for (final e in index ?? const <StoreIndexEntry>[]) e.id: e};
    return [for (final e in open) _Row(e, byId[e.storeId])];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_intentionalPop) widget.onCloseAll();
      },
      child: DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => GestureDetector(
          onTap: () {},
          behavior: HitTestBehavior.opaque,
          child: RoutexBottomSheet(
            contentInset: RoutexBottomSheetContentInset.content,
            child: FutureBuilder<List<_Row>>(
              future: _rowsFuture,
              builder: (context, snapshot) => CustomScrollView(
                controller: scrollController,
                slivers: [
                  const SliverToBoxAdapter(child: RoutexSheetHandle()),
                  SliverToBoxAdapter(
                    child: SheetHeader(
                      title: '오늘의 이벤트',
                      onCloseAll: widget.onCloseAll,
                      onIntentionalPop: _markIntentional,
                    ),
                  ),
                  ..._body(snapshot),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(AsyncSnapshot<List<_Row>> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    final rows = snapshot.data ?? const <_Row>[];
    if (rows.isEmpty || snapshot.hasError) {
      // 파일이 깨진 경우와 오늘 열리는 것이 없는 경우를 **가르지 않는다** —
      // 사용자가 할 일이 어느 쪽이든 같고(다음에 다시 보기), 굳이 가르면
      // "파일이 깨졌어요"라는, 사용자가 손쓸 수 없는 문구가 화면에 남는다.
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40, horizontal: 16),
            child: Text(
              '오늘 열리는 이벤트가 없어요.',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ),
        ),
      ];
    }
    return [
      SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, i) => _tile(rows[i]),
      ),
    ];
  }

  /// 행사 한 줄. **[RoutexListCell]을 쓰지 않는다** — 그 셀은 leading이
  /// `IconData`뿐이라 사진이 못 들어가는데, 이 목록은 사진이 요점이다(어디를
  /// 갈지 정하는 데 글자보다 사진이 빠르다). 대신 색·간격은 셀과 맞춘다.
  Widget _tile(_Row row) {
    final event = row.event;
    final navigable = row.entry != null;
    return InkWell(
      key: Key('event-${event.title}'),
      // **못 가는 줄도 눌린다.** 포스터는 좌표 없이도 볼 값이 있고, 안내
      // 버튼만 그 화면에서 잠긴다. 목록에서 막으면 사진을 아예 못 본다.
      onTap: () => unawaited(_openPoster(row)),
      child: Opacity(
        // 못 가는 줄은 흐리게 둔다. 감추지는 않는다 — 장소 문구는 읽을 값이 있다.
        opacity: navigable ? 1 : 0.55,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _thumbnail(event),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (event.place.isNotEmpty) event.place,
                        _period(event),
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 대표 사진 64×64. 사진이 없거나 못 읽으면 **아이콘으로 떨어진다** — 에셋이
  /// 빠져도 목록 한 줄이 통째로 깨지지는 않아야 한다.
  /// 포스터를 연다. **좌우로 미는 대상은 목록 전체**라, 사용자가 목록으로
  /// 돌아가지 않고도 오늘 뭘 하는지 다 훑을 수 있다(공식 모바일 웹과 같다).
  ///
  /// 포스터에서 안내를 고르면 **그때 고른 행사**로 시트를 닫는다 — 밀어서 다른
  /// 행사를 보다가 눌렀는데 처음 줄로 안내되면 안 된다.
  Future<void> _openPoster(_Row row) async {
    final rows = await _rowsFuture;
    if (!mounted) return;
    final start = rows.indexOf(row);
    final picked = await EventPosterView.show(
      context,
      events: [for (final r in rows) r.event],
      initialIndex: start < 0 ? 0 : start,
      navigable: [for (final r in rows) r.entry != null],
    );
    if (!mounted || picked == null) return;
    _markIntentional();
    Navigator.of(context).pop(rows[picked].entry);
  }

  Widget _thumbnail(BuildingEvent event) {
    const size = 64.0;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.muted.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        Icons.local_activity_outlined,
        size: 22,
        color: AppColors.muted,
      ),
    );
    final path = event.image;
    if (path == null || path.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset(
        path,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }

  /// `08.26까지`. 시작일은 적지 않는다 — 이미 열려 있는 행사만 목록에 있으므로
  /// 사용자가 정할 것은 "언제까지 갈 수 있나" 하나다.
  String _period(BuildingEvent event) {
    final end = event.end.split('-');
    return end.length == 3 ? '${end[1]}.${end[2]}까지' : event.end;
  }
}
