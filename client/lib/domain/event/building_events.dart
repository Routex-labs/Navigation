/// 건물에서 지금 열리는 행사(팝업·전시) 한 건과 그 목록을 거르는 규칙.
///
/// 원본은 더현대 서울 공식 사이트에서 받아 둔 스냅샷이고, 수집 경로와 실측은
/// `docs/client/thehyundai-event-source.md`가 단일 출처다. **자동 갱신이 없다** —
/// 파일에 적힌 [BuildingEvents.capturedOn] 이후로는 원본과 어긋날 수 있다.
library;

import 'dart:convert';

/// 행사 한 건.
class BuildingEvent {
  const BuildingEvent({
    required this.title,
    required this.start,
    required this.end,
    required this.place,
    this.floorName,
    this.storeId,
    this.image,
    this.details = const [],
  });

  final String title;

  /// `YYYY-MM-DD`. **문자열로 둔다** — 이 형식은 사전순이 곧 날짜순이라
  /// [DateTime]으로 바꿔야 할 이유가 비교에는 없다. 파싱을 하면 시간대가
  /// 끼어들어 "오늘"의 경계가 기기 설정에 따라 흔들린다.
  final String start;
  final String end;

  /// 원본이 적어 준 장소 문구(`지하2층 POP-UP@ICONIC`). 매칭이 실패해도 화면에는
  /// 이걸 그대로 보여 준다 — 좌표가 없다고 행사까지 감추면 사용자는 그 행사가
  /// 없는 줄 안다.
  final String place;

  final String? floorName;

  /// 안내를 걸 매장 id. null이면 장소 문구만 있고 지도로는 못 간다.
  final String? storeId;

  /// 대표 사진의 에셋 경로. 없으면 목록은 자리만 비운다 — 회색 상자를 채워 넣지
  /// 않는다. 사진이 없는 줄에 빈 액자를 그리면 "불러오지 못했다"로 읽힌다.
  final String? image;

  /// 포스터 아래로 이어지는 본문. 원본이 준 순서 그대로다 — 문단·소제목·특전·
  /// 유의사항이 섞여 오고, **순서 자체가 내용**이라 종류별로 묶지 않는다.
  final List<EventBlock> details;

  bool get navigable => storeId != null && (floorName?.isNotEmpty ?? false);

  /// [day](`YYYY-MM-DD`)에 열려 있는가. 시작·종료일을 **포함**한다.
  bool isOpenOn(String day) => start.compareTo(day) <= 0 && end.compareTo(day) >= 0;
}

/// 본문 한 덩어리. `t`가 종류를 정하고 나머지 칸은 종류마다 쓰는 것만 채운다.
///
/// **모르는 종류는 버리지 않고 담아 둔다** — 원본이 새 종류를 추가해도 파싱이
/// 통째로 실패하지 않아야 한다. 그릴 수 없는 것은 화면이 조용히 건너뛴다.
class EventBlock {
  const EventBlock({
    required this.kind,
    this.text,
    this.image,
    this.lines = const [],
    this.items = const [],
    this.rows = const [],
    this.url,
  });

  /// `h`(소제목) · `p`(문단) · `div`(구분선) · `img`(사진) · `prod`(구매 특전) ·
  /// `notice`(유의사항) · `rows`(표) · `link` · `tel`.
  final String kind;
  final String? text;
  final String? image;

  /// `prod`의 설명 줄. 첫 줄이 조건, 나머지가 내용이다.
  final List<String> lines;

  /// `notice`의 항목.
  final List<String> items;

  /// `rows`의 (라벨, 값) 쌍.
  final List<List<String>> rows;

  final String? url;

  factory EventBlock.fromJson(Map<String, dynamic> json) => EventBlock(
    kind: json['t'] as String? ?? '',
    text: json['text'] as String?,
    image: json['image'] as String?,
    lines: [for (final l in (json['lines'] as List? ?? const [])) l as String],
    items: [for (final l in (json['items'] as List? ?? const [])) l as String],
    rows: [
      for (final r in (json['rows'] as List? ?? const []))
        [for (final c in (r as List)) c as String],
    ],
    url: (json['url'] ?? json['number']) as String?,
  );
}

/// 파일 한 벌.
class BuildingEvents {
  const BuildingEvents({required this.capturedOn, required this.events});

  /// 원본을 받아 온 날(`YYYY-MM-DD`). 화면이 "언제 기준인지" 밝히는 데 쓴다.
  final String capturedOn;
  final List<BuildingEvent> events;

  /// [day]에 열려 있는 행사만, **먼저 끝나는 것부터**.
  ///
  /// 끝나는 순으로 세우는 이유는 목록 맨 위가 "곧 사라질 것"이어야 하기
  /// 때문이다. 시작순으로 두면 반년짜리 상설 전시가 늘 맨 위를 차지한다.
  /// 같은 날 끝나면 안내가 되는 것을 먼저 올린다.
  List<BuildingEvent> openOn(String day) {
    final open = events.where((e) => e.isOpenOn(day)).toList();
    open.sort((a, b) {
      final byEnd = a.end.compareTo(b.end);
      if (byEnd != 0) return byEnd;
      if (a.navigable != b.navigable) return a.navigable ? -1 : 1;
      return a.title.compareTo(b.title);
    });
    return open;
  }
}

/// 기기 로컬 날짜(`YYYY-MM-DD`). 행사 기간도 현지 날짜라 UTC로 재지 않는다.
///
/// 목록 시트와 상세 시트가 **같은 값을 써야 한다** — 자정 근처에서 갈리면 목록에는
/// 있는데 상세에는 배지가 없는 화면이 나온다.
String todayKey([DateTime? now]) {
  final at = now ?? DateTime.now();
  return '${at.year}-${at.month.toString().padLeft(2, '0')}'
      '-${at.day.toString().padLeft(2, '0')}';
}

/// `assets/mock/events.json`을 읽는다. 형식이 어긋나면 [FormatException].
///
/// **빈 목록을 조용히 돌려주지 않는다.** 이 파일은 사람이 손으로 넣은 스냅샷이라
/// 0건은 "행사가 없다"가 아니라 "파일이 깨졌다"에 가깝다. 호출자가 실패를 삼킬지는
/// 호출자가 정한다.
BuildingEvents parseBuildingEvents(String source) {
  final root = jsonDecode(source);
  if (root is! Map<String, dynamic>) {
    throw const FormatException('events.json의 최상위가 객체가 아니다');
  }
  final raw = root['events'];
  if (raw is! List || raw.isEmpty) {
    throw const FormatException('events.json에 events 배열이 없거나 비어 있다');
  }
  return BuildingEvents(
    capturedOn: root['_captured'] as String? ?? '',
    events: [
      for (final item in raw.cast<Map<String, dynamic>>())
        BuildingEvent(
          title: item['title'] as String,
          start: item['start'] as String,
          end: item['end'] as String,
          place: item['place'] as String? ?? '',
          floorName: item['floor'] as String?,
          storeId: item['storeId'] as String?,
          image: item['image'] as String?,
          details: [
            for (final block in (item['details'] as List? ?? const []))
              EventBlock.fromJson(block as Map<String, dynamic>),
          ],
        ),
    ],
  );
}
