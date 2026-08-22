import 'package:flutter/services.dart' show rootBundle;

import '../../../../core/api_config.dart';
import '../../../../domain/event/building_events.dart';
import '../../../../models/place/store_index_entry.dart';
import '../../../../service_locator.dart';

/// 오늘 열리는 행사 한 건과, 그 행사로 안내를 걸 매장. 매장을 못 찾으면
/// [entry]가 null이고 그 행사는 포스터까지만 보인다.
class TodayEvent {
  const TodayEvent(this.event, this.entry);

  final BuildingEvent event;
  final StoreIndexEntry? entry;
}

/// 매장 색인을 기다리는 시한. 색인은 안내를 걸기 위한 것이지 목록을 그리기 위한
/// 것이 아니라, 못 받으면 기다리지 않고 장소 문구만으로 목록을 낸다.
///
/// **시한이 없으면 예외가 아니라 멎는다** — 서버에 닿지 못하는 실기기에서 영영
/// 도는 스피너만 남았다.
const _indexTimeout = Duration(seconds: 6);

/// 오늘 열리는 행사를 **갈래 순서로** 읽고, 각 건에 매장을 붙인다.
///
/// 하단 줄·목록 시트·포스터가 **같은 순서의 같은 목록**을 써야 한다. 포스터는
/// 좌우로 밀며 목록 전체를 훑는 화면이라, 진입점마다 순서가 다르면 3번째 카드를
/// 눌러 놓고 다른 행사가 열린다.
///
/// [events]를 주면 그것을 쓰고, 없으면 에셋을 읽는다 — 지도 화면은 이미 한 번
/// 읽어 두므로 다시 읽을 이유가 없다. [diary]를 주면 그 쪽에서 온 것만 남는다.
Future<List<TodayEvent>> loadTodayEvents({
  BuildingEvents? events,
  EventDiary? diary,
}) async {
  final parsed =
      events ??
      parseBuildingEvents(
        await rootBundle.loadString('assets/mock/events.json'),
      );
  final open = diary == null
      ? parsed.openOnByDiary(todayKey())
      : parsed.openOn(todayKey(), diary: diary);

  // 매장 색인은 검색이 이미 받아 두는 것과 **같은 캐시**다(같은 건물이면 두 번째
  // 부터 즉시 온다). 실패하면 안내만 빠지고 목록은 그대로 뜬다.
  List<StoreIndexEntry>? index;
  try {
    index = await buildingRepository
        .getStoreIndex(demoBuildingId)
        .timeout(_indexTimeout);
  } on Object {
    index = null;
  }
  final byId = {for (final e in index ?? const <StoreIndexEntry>[]) e.id: e};
  return [for (final e in open) TodayEvent(e, byId[e.storeId])];
}
