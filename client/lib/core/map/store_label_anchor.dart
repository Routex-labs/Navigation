/// 한 폴리곤에 매장이 여러 개 붙어 있을 때 **라벨을 위아래 칸으로 나누는** 계산기.
///
/// 원본 도면은 한 폴리곤에 매장을 여러 개 붙이고(더현대 서울 기준 31개 자리에
/// 91개 매장) 그 매장들의 `centroid`가 완전히 같아서, 앵커를 centroid 그대로 쓰면
/// MapLibre 충돌 처리가 하나만 남긴다 — 나머지는 존재하는데 누를 수 없다.
///
/// 폴리곤이 화면에서 차지하는 세로를 매장 수로 나눠 한 칸에 하나씩 놓는다.
/// **순서는 원본 핀이 정한다**(핀을 화면 세로축에 투영). 위치는 우리가 정하고
/// 순서는 원본을 따르는 것이라 원본 지도와 위아래가 뒤집히지 않는다.
///
/// POI 핀으로 옮기는 것만으로 왜 부족한지와, 구현 전에 정한 검증 기준 표는
/// `docs/client/map-style-rules.md`.
library;

import 'dart:math';

import 'package:latlong2/latlong.dart';

import '../../models/floor_plan.dart';
import './store_label_fit.dart';

/// 라벨 feature에 "이 자리를 여럿이 나눠 쓴다"고 표시하는 속성 키.
///
/// 화면이 이 값으로 **충돌을 무시하고 항상 그리는 레이어**를 갈라낸다. 칸을
/// 나눠 놓아도 MapLibre 충돌 처리는 아이콘 크기(px 고정)까지 함께 재기 때문에,
/// 축척에 따라 여전히 한쪽을 지운다 — 그러면 이름은 하나만 보이는데 탭 판정은
/// 둘로 갈려 "보이는 이름과 열리는 매장이 다른" 상태가 된다. 같은 자리에 둘이
/// 있다는 사실 자체가 사용자에게 필요한 정보이므로, 이 자리만은 겹쳐서라도 둘
/// 다 그린다.
const String kStoreLabelSharedProperty = 'shared';

/// 폴리곤이 없어 칸 높이를 잴 수 없을 때 쓰는 간격(m). 시설처럼 점만 있는
/// 매장이 겹친 경우다.
const double kStoreLabelStackGapM = 2.5;

/// 위도 1도의 미터 길이(구면 근사). 실내 한 층 범위에서는 이 근사로 충분하다.
const double _metersPerLatDegree = 111320.0;

/// 같은 자리로 볼 좌표 반올림 자릿수. 6자리는 약 0.1m로, 원본이 같은 값을
/// 복사해 넣은 경우만 묶이고 실제로 다른 매장이 우연히 묶이지는 않는다.
const int _anchorPrecision = 6;

/// 매장 id → 라벨 앵커.
///
/// [bearingDeg]는 카메라가 건물 축에 맞추려고 돌아간 각도다. 칸을 "화면 세로"로
/// 쌓으려면 이 각도가 필요하다 — 지도가 돌아간 상태에서 위도 축으로 쌓으면
/// 화면에서는 비스듬히 어긋난다.
Map<String, LatLng> resolveStoreLabelAnchors({
  required List<StorePolygon> stores,
  required double bearingDeg,
  double fallbackGapM = kStoreLabelStackGapM,
}) {
  final anchors = <String, LatLng>{};
  final byCentroid = <String, List<StorePolygon>>{};
  for (final store in stores) {
    byCentroid.putIfAbsent(_key(store.centroid), () => []).add(store);
  }

  for (final group in byCentroid.values) {
    if (group.length == 1) {
      anchors[group.first.id] = group.first.centroid;
      continue;
    }

    final centroid = group.first.centroid;
    final box = storeLabelBoxMeters(
      polygon: group.first.polygon,
      bearingDeg: bearingDeg,
    );
    // 칸 높이. 폴리곤이 없으면(점만 있는 시설) 잴 수 없으므로 고정 간격을 쓴다.
    final slotM = box.heightM > 0 ? box.heightM / group.length : fallbackGapM;

    // 위에서 아래로 놓을 순서. 원본 핀을 화면 세로축에 투영해 큰 값(위쪽)이
    // 먼저 오게 한다. 핀이 없는 매장은 0으로 두고, 동률은 id로 가른다 —
    // 그래야 호출마다 같은 그림이 나온다.
    final ordered = [...group]
      ..sort((a, b) {
        final byScreen = _screenUpM(
          b.entrance,
          centroid,
          bearingDeg,
        ).compareTo(_screenUpM(a.entrance, centroid, bearingDeg));
        return byScreen != 0 ? byScreen : a.id.compareTo(b.id);
      });

    for (var i = 0; i < ordered.length; i++) {
      final offsetM = ((ordered.length - 1) / 2 - i) * slotM;
      anchors[ordered[i].id] = _offsetAlongScreenUp(
        centroid,
        offsetM,
        bearingDeg,
      );
    }
  }

  return anchors;
}

/// 매장 id → **그 자리를 몇 개 매장이 나눠 쓰는가**.
///
/// 앵커만 나눠서는 부족하다. 라벨 글자 크기는 폴리곤 박스에 맞춰 정해지는데
/// ([store_label_fit.dart]) 한 폴리곤에 매장이 둘이면 **각자 폴리곤 전체 크기의
/// 글자를 요구해** 칸을 넘어 서로를 밀어낸다. 호출부가 이 수로 박스 세로를
/// 나눠야 [resolveStoreLabelAnchors]가 만든 칸과 글자 크기가 맞물린다.
Map<String, int> storeLabelShareCounts(List<StorePolygon> stores) {
  final counts = <String, int>{};
  for (final store in stores) {
    final key = _key(store.centroid);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return {for (final store in stores) store.id: counts[_key(store.centroid)]!};
}

/// centroid를 공유하는 매장 그룹(2곳 이상). 묶음 매장([aggregateStoreIds])은
/// 호출자가 미리 빼고 넘긴다.
///
/// 그룹 안 순서는 원본 핀을 화면 세로축에 투영해 위→아래로 고정한다 —
/// 「첫 매장 외 N」의 "첫"이 호출마다 바뀌지 않게 하기 위해서다. 핀이 없으면
/// id 순이다.
List<List<StorePolygon>> sharedStoreGroups(
  List<StorePolygon> stores, {
  required double bearingDeg,
}) {
  final byCentroid = <String, List<StorePolygon>>{};
  for (final store in stores) {
    byCentroid.putIfAbsent(_key(store.centroid), () => []).add(store);
  }
  final groups = <List<StorePolygon>>[];
  for (final group in byCentroid.values) {
    if (group.length < 2) continue;
    final centroid = group.first.centroid;
    group.sort((a, b) {
      final byScreen = _screenUpM(
        b.entrance,
        centroid,
        bearingDeg,
      ).compareTo(_screenUpM(a.entrance, centroid, bearingDeg));
      return byScreen != 0 ? byScreen : a.id.compareTo(b.id);
    });
    groups.add(group);
  }
  return groups;
}

/// 세 곳 이상 그룹을 접는 묶음 라벨 문구. 백엔드 타일(`tiling._cluster_labels`)
/// 과 같은 형식이어야 두 화면이 같은 자리에 같은 문구를 적는다.
String clusterLabelText(List<StorePolygon> group) =>
    '${group.first.name} 외 ${group.length - 1}';

/// 이름이 **같은 층 다른 매장 이름 2개 이상을 이어 붙인** "묶음 매장" id.
///
/// 원본(다비오)은 구역 폴리곤에 그 안 매장들의 이름을 전부 이어 붙인 항목을
/// 함께 둔다 — 「마사비스 리치몬드 과자점 은비스브레드 니드쿠키앤베이커리」류.
/// 구성 매장들이 각자 폴리곤·라벨을 갖고 있으므로 묶음은 지도에서 매장으로
/// 취급하지 않는다(라벨 없음·탭 대상 아님). 백엔드 타일이 같은 규칙으로
/// 라벨을 이미 빼고 내려보내며(`tiling._aggregate_store_ids`), 클라이언트는
/// 탭 판정과 GeoJSON 라벨에서 같은 판정을 쓴다.
///
/// 공백을 지우고 비교하는 이유: 원본 표기가 흔들린다 — 묶음에는 「세띠엠므」,
/// 구성 매장에는 「세띠 엠므」로 적혀 있다. 2개 이상을 요구하는 이유는
/// 「뉴발란스 키즈」(「뉴발란스」 포함)처럼 다른 매장 이름을 하나만 품는
/// 정상 매장을 오인하지 않기 위해서다.
Set<String> aggregateStoreIds(List<StorePolygon> stores) {
  String squash(String name) => name.replaceAll(RegExp(r'\s+'), '');
  final squashedById = {
    for (final store in stores) store.id: squash(store.name),
  };
  final result = <String>{};
  for (final store in stores) {
    final mine = squashedById[store.id]!;
    if (mine.length < 4) continue;
    final contained = <String>{};
    for (final other in stores) {
      if (other.id == store.id) continue;
      final name = squashedById[other.id]!;
      if (name.length >= 2 && name != mine && mine.contains(name)) {
        contained.add(name);
      }
    }
    if (contained.length >= 2) result.add(store.id);
  }
  return result;
}

String _key(LatLng point) =>
    '${point.latitude.toStringAsFixed(_anchorPrecision)},'
    '${point.longitude.toStringAsFixed(_anchorPrecision)}';

/// [point]가 [origin]에서 화면 위쪽으로 얼마나 떨어져 있는가(m). 없으면 0.
double _screenUpM(LatLng? point, LatLng origin, double bearingDeg) {
  if (point == null) return 0;
  final bearingRad = bearingDeg * pi / 180;
  final north = (point.latitude - origin.latitude) * _metersPerLatDegree;
  final east =
      (point.longitude - origin.longitude) *
      _metersPerLatDegree *
      cos(origin.latitude * pi / 180);
  return north * cos(bearingRad) + east * sin(bearingRad);
}

/// [base]에서 화면 위쪽으로 [meters]만큼 옮긴 점. 카메라 [bearingDeg]가
/// 가리키는 방향이 곧 화면 위쪽이다.
LatLng _offsetAlongScreenUp(LatLng base, double meters, double bearingDeg) {
  final bearingRad = bearingDeg * pi / 180;
  final north = meters * cos(bearingRad);
  final east = meters * sin(bearingRad);
  final cosLat = cos(base.latitude * pi / 180);
  final dLat = north / _metersPerLatDegree;
  // 적도에서 멀어질수록 경도 1도가 짧아진다. cosLat이 0에 가까운 극지방은
  // 실내 도면이 존재하지 않는 범위라 방어하지 않는다.
  final dLng = east / (_metersPerLatDegree * cosLat);
  return LatLng(base.latitude + dLat, base.longitude + dLng);
}
