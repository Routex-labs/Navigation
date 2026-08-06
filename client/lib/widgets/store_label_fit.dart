import 'dart:math';

import 'package:latlong2/latlong.dart';

import '../screens/outdoor_map/indoor_entry_zoom.dart';

/// 매장명 라벨을 **매장 폴리곤 크기에 맞춰** 재는 계산기.
///
/// ## 왜 필요한가
///
/// 라벨을 벡터 타일 심볼 레이어에 맡기던 동안 글자 크기는
/// `9px(z16) ~ 14px(z20)` 보간이었다. 그런데 도면 폴리곤은 월드 좌표라
/// **zoom 1레벨마다 화면에서 2배**가 된다. 즉 z16→z20에서 매장은 16배 커지는데
/// 글자는 1.55배만 커진다. 결과가 사용자가 본 두 증상 그대로다.
///
/// | zoom | 5m 매장 화면 폭 | 글자 | 4글자 이름 |
/// |---|---|---|---|
/// | z18 (기본 진입) | 21px | 11.5px | 약 46px — **박스의 2배** |
/// | z20 | 84px | 14px | 약 56px — 맞음 |
/// | z21 | 169px | 14px | 매장에 비해 **너무 작음** |
///
/// 게다가 매장 크기 자체가 1.9m(p10)~14m(p90)로 7배 벌어져 있어서, 모든 매장에
/// 같은 px을 주는 한 어떤 값을 골라도 한쪽은 넘치고 한쪽은 작다. 그래서
/// **매장마다 다른 크기**를 실어야 한다.
///
/// ## 어떻게 재는가
///
/// 글자 크기를 px이 아니라 **"1em이 실제 몇 미터인가"([kStoreLabelEmMetersProperty])**
/// 로 계산해 feature에 싣는다. 미터는 zoom과 무관한 값이라, 화면 px은
/// [storeLabelTextSizeExpression]이 zoom에서 한 번만 환산한다. 이렇게 두면
/// 글자가 도면과 **같은 배율로** 커지고 작아진다 — 첫 번째 증상이 여기서 사라진다.
///
/// 미터 값은 "이름을 줄바꿈했을 때 매장 박스 안에 들어가는 최대 크기"다
/// ([fitStoreLabel]). 작은 매장은 작은 값을, 큰 매장은 큰 값을 받는다 — 두 번째
/// 증상이 여기서 줄어든다.
///
/// ## 어디서 깨지는가 (알고 두는 한계)
///
///  - **하한에 걸린 매장은 여전히 넘친다.** 1.4m 박스에 8글자 이름을 넣으려면
///    z20에서도 5px가 필요한데, 그건 읽을 수 없다. [kStoreLabelMinPx]에서
///    멈추므로 그런 매장은 넘침이 남는다. 숨기지 않는 쪽을 택한 결과다.
///  - **지도를 돌리면 박스가 어긋난다.** 박스는 카메라 bearing 기준 화면
///    가로/세로로 잰다([storeLabelBoxMeters]). 길안내 중 heading을 따라 지도가
///    돌면 그 기준이 흔들려 실제보다 큰 글자를 허용할 수 있다. 도면을 훑어보는
///    기본 상태(건물 축에 맞춘 bearing)에서는 정확하다.
///  - **대분류 아이콘 폭은 예산에 넣지 않았다.** 아이콘은 글자 옆에 붙어
///    1.6em 남짓을 더 쓴다. 그것까지 넣으면 2글자 이름의 글자가 거의 절반으로
///    작아져서, 장식 하나 때문에 도면 전체가 읽기 힘들어진다. 아이콘은
///    `icon-optional`로 자리가 없으면 빠지게 두고 글자만 재는 쪽을 택했다.
///  - **폰트 실측이 아니라 추정폭이다.** 글리프는 타일 서버 폰트 스택이라
///    클라이언트에 없다. [storeLabelEmWidth]의 문자별 추정치를 쓴다.

/// 라벨 feature에 싣는 "1em = 몇 미터" 속성 이름.
const kStoreLabelEmMetersProperty = 'label_em_m';

/// 라벨 feature에 싣는 줄바꿈 폭(em) 속성 이름. `text-max-width`에 그대로 건다.
///
/// **이걸 같이 실어야 계산이 맞는다.** 크기만 정하고 줄바꿈 폭을 고정값(6em)으로
/// 두면, 2줄로 접힌다고 보고 잡은 크기가 실제로는 1줄로 펴져 계산의 두 배 폭이
/// 된다.
const kStoreLabelMaxWidthProperty = 'label_max_w';

/// 읽을 수 있는 하한(px). 박스에 맞추려면 이보다 작아야 하는 매장은 넘침을
/// 감수하고 이 크기로 그린다 — 라벨을 숨기는 대신 유지하기로 한 결정이다.
const kStoreLabelMinPx = 9.0;

/// 상한(px). 큰 매장에서 글자가 도면을 삼키지 않게 막는다.
///
/// 실데이터(더현대 1626개 매장)로 값을 재 봤다. 상한을 올릴수록 "글자가 매장에
/// 비해 작다"가 줄지만 z19 이상에서는 대부분이 어차피 상한에 붙어 있어 효과가
/// 금방 꺾인다 — 평균 글자폭/매장폭은 z19에서 16px 0.59 → 18px 0.63 →
/// 20px 0.66 → 24px 0.73이다. 반면 기본 화면인 z18에서는 상한을 16→18로만
/// 올려도 상한에 눌리는 매장이 191개 → 97개로 줄어 매장 크기 차이가 그대로
/// 드러난다. 그 지점이 18px이라 여기서 멈춘다(예전 고정 상한은 14px이었다).
const kStoreLabelMaxPx = 18.0;

/// MapLibre가 쓰는 줄 높이(em). shaping에서 `lineHeight = 1.2 * fontSize`다.
const kStoreLabelLineHeightEm = 1.2;

/// 몇 줄까지 접어 볼지. 3줄을 넘으면 이름 덩어리가 매장보다 세로로 길어져
/// 어느 폴리곤 것인지 알아보기 어려워진다.
const kStoreLabelMaxLines = 3;

/// 박스에서 실제로 글자에 내주는 비율. 테두리·헤일로와 이웃 폴리곤 사이 여백이다.
const kStoreLabelBoxPadding = 0.88;

/// [fitStoreLabel]의 결과.
class StoreLabelFit {
  const StoreLabelFit({
    required this.emMeters,
    required this.maxWidthEm,
    required this.lines,
  });

  /// 1em이 몇 미터인지. feature의 [kStoreLabelEmMetersProperty]로 나간다.
  final double emMeters;

  /// 가장 긴 줄의 폭(em). feature의 [kStoreLabelMaxWidthProperty]로 나간다.
  final double maxWidthEm;

  /// 이 폭으로 접었을 때 나오는 줄 수. 크기 계산의 세로 예산에 쓴 값이다.
  final int lines;
}

/// 문자 하나가 차지하는 폭(em) 추정치.
///
/// 타일 서버 폰트 스택(Noto Sans 계열)의 글리프가 클라이언트에 없어 실측할 수
/// 없다. 한글·한자는 전각(1.0em)이고 라틴은 그 절반 남짓이라는 성질만 쓴다.
/// 값이 조금 틀려도 결과는 "약간 크거나 작은 글자"지 깨진 배치가 아니다.
double _advanceEm(int rune) {
  if (rune == 0x20) return 0.28; // 공백
  if (_isFullWidth(rune)) return 1.0;
  if (rune >= 0x41 && rune <= 0x5A) return 0.70; // A-Z
  if (rune >= 0x30 && rune <= 0x39) return 0.57; // 0-9
  if (rune < 0x80) return 0.55; // 그 밖의 ASCII
  return 0.60;
}

bool _isFullWidth(int rune) =>
    (rune >= 0x1100 && rune <= 0x11FF) || // 한글 자모
    (rune >= 0x3000 && rune <= 0x303F) || // CJK 문장부호
    (rune >= 0x3040 && rune <= 0x30FF) || // 가나
    (rune >= 0x3130 && rune <= 0x318F) || // 호환 자모
    (rune >= 0x4E00 && rune <= 0x9FFF) || // 한자
    (rune >= 0xAC00 && rune <= 0xD7A3) || // 한글 음절
    (rune >= 0xFF00 && rune <= 0xFF60); // 전각

/// 글자 크기 1일 때 [text]가 차지하는 폭(em).
double storeLabelEmWidth(String text) {
  var sum = 0.0;
  for (final rune in text.runes) {
    sum += _advanceEm(rune);
  }
  return sum;
}

/// 줄바꿈이 가능한 최소 덩어리. 공백은 줄 끝에서 버려지므로 따로 표시한다.
class _Chunk {
  const _Chunk(this.widthEm, {required this.isSpace});
  final double widthEm;
  final bool isSpace;
}

/// [text]를 "더 쪼갤 수 없는 덩어리" 목록으로 나눈다.
///
/// MapLibre의 줄바꿈 규칙을 따라간다 — 공백에서 끊고, 전각 문자는 **글자
/// 사이에서도** 끊는다(한글 이름은 공백이 없어서 이 규칙이 없으면 아예 안 접힌다).
/// 라틴 단어는 통째로 한 덩어리다.
List<_Chunk> _chunks(String text) {
  final chunks = <_Chunk>[];
  var wordWidth = 0.0;

  void flushWord() {
    if (wordWidth > 0) {
      chunks.add(_Chunk(wordWidth, isSpace: false));
      wordWidth = 0;
    }
  }

  for (final rune in text.runes) {
    final width = _advanceEm(rune);
    if (rune == 0x20) {
      flushWord();
      chunks.add(_Chunk(width, isSpace: true));
    } else if (_isFullWidth(rune)) {
      flushWord();
      chunks.add(_Chunk(width, isSpace: false));
    } else {
      wordWidth += width;
    }
  }
  flushWord();
  return chunks;
}

/// [maxWidthEm]을 넘지 않게 탐욕적으로 접었을 때 각 줄의 폭(em).
///
/// 한 덩어리가 [maxWidthEm]보다 넓으면(긴 라틴 단어) 그 줄만 넘친다 — 쪼갤 수
/// 있는 지점이 없으므로 접는 대신 넘치는 것이 MapLibre의 동작이기도 하다.
List<double> storeLabelLineWidths(String text, double maxWidthEm) {
  final chunks = _chunks(text);
  final lines = <double>[];
  var current = 0.0;
  var pendingSpace = 0.0;

  for (final chunk in chunks) {
    if (chunk.isSpace) {
      // 줄 첫머리 공백은 버린다. 줄 안에서는 다음 덩어리와 함께 폭을 잰다 —
      // 그래야 "공백까지 넣으면 넘치는" 경우에 공백이 줄 끝에 남지 않는다.
      if (current > 0) pendingSpace += chunk.widthEm;
      continue;
    }
    final needed = pendingSpace + chunk.widthEm;
    if (current > 0 && current + needed > maxWidthEm + 1e-9) {
      lines.add(current);
      current = chunk.widthEm;
    } else {
      current += needed;
    }
    pendingSpace = 0;
  }
  if (current > 0) lines.add(current);
  if (lines.isEmpty) lines.add(0);
  return lines;
}

/// [name]이 `boxWidthM x boxHeightM` 박스 안에 들어가는 최대 글자 크기를 찾는다.
///
/// 줄 수를 1..[kStoreLabelMaxLines]로 바꿔 가며 각각의 최대 크기를 재고 가장 큰
/// 것을 고른다. 줄을 늘리면 가로 예산은 넉넉해지고 세로 예산은 빠듯해져서, 이름
/// 길이와 박스 비율에 따라 유리한 쪽이 갈린다 — 미리 정할 수 없으니 다 재본다.
///
/// 박스가 없는(폴리곤이 비어 있는) 매장은 `emMeters: 0`으로 돌려준다.
/// [storeLabelTextSizeExpression]의 하한이 받아 [kStoreLabelMinPx]로 그린다.
StoreLabelFit fitStoreLabel({
  required String name,
  required double boxWidthM,
  required double boxHeightM,
}) {
  final totalEm = storeLabelEmWidth(name);
  if (totalEm <= 0 ||
      !boxWidthM.isFinite ||
      !boxHeightM.isFinite ||
      boxWidthM <= 0 ||
      boxHeightM <= 0) {
    return StoreLabelFit(
      emMeters: 0,
      maxWidthEm: max(totalEm, 1),
      lines: 1,
    );
  }

  final usableWidth = boxWidthM * kStoreLabelBoxPadding;
  final usableHeight = boxHeightM * kStoreLabelBoxPadding;

  var best = const StoreLabelFit(emMeters: 0, maxWidthEm: 1, lines: 1);
  for (var target = 1; target <= kStoreLabelMaxLines; target++) {
    // 균등하게 나눈 폭을 목표로 접는다. MapLibre도 "전체 폭 / 줄 수"를 목표로
    // 잡으므로 같은 기준이다.
    final widths = storeLabelLineWidths(name, totalEm / target);
    final widest = widths.reduce(max);
    if (widest <= 0) continue;
    final emMeters = min(
      usableWidth / widest,
      usableHeight / (widths.length * kStoreLabelLineHeightEm),
    );
    if (emMeters > best.emMeters) {
      best = StoreLabelFit(
        emMeters: emMeters,
        // 실제로 나온 가장 긴 줄을 그대로 돌려준다. 이 값을 text-max-width로
        // 걸어야 MapLibre가 같은 모양으로 접는다.
        maxWidthEm: widest,
        lines: widths.length,
      );
    }
  }
  return best;
}

/// 매장 폴리곤이 **화면에서** 차지하는 가로/세로(m).
///
/// 라벨 글자는 화면 가로로 눕는다. 그래서 위경도 bbox가 아니라 카메라
/// [bearingDeg] 기준으로 돌린 좌표계에서 재야 한다 — 실내 지도는 건물 축을
/// 화면에 맞추려고 카메라를 돌려 두기 때문에, 안 돌리고 재면 비스듬한 매장의
/// 박스가 실제보다 크게 잡힌다.
///
/// 투영은 [FloorPlanView]의 카메라 계산과 같은 등방 평면 근사다(건물 규모
/// 수백 m에서는 오차가 무시할 수준).
({double widthM, double heightM}) storeLabelBoxMeters({
  required List<LatLng> polygon,
  required double bearingDeg,
}) {
  if (polygon.length < 3) return (widthM: 0, heightM: 0);

  var latSum = 0.0;
  for (final point in polygon) {
    latSum += point.latitude;
  }
  final meanLat = latSum / polygon.length;
  final cosLat = cos(meanLat * pi / 180);

  final rad = bearingDeg * pi / 180;
  final cosB = cos(rad);
  final sinB = sin(rad);

  var minX = double.infinity, maxX = double.negativeInfinity;
  var minY = double.infinity, maxY = double.negativeInfinity;
  for (final point in polygon) {
    final dx =
        (point.longitude - polygon.first.longitude) *
        cosLat *
        _metersPerDegreeLat;
    final dy = (point.latitude - polygon.first.latitude) * _metersPerDegreeLat;
    // bearing이 B인 카메라에서 화면 "위"는 나침반 B, "오른쪽"은 B+90이다
    // (FloorPlanView._fitBearingAndZoom과 같은 식).
    final rx = dx * cosB - dy * sinB;
    final ry = dx * sinB + dy * cosB;
    minX = min(minX, rx);
    maxX = max(maxX, rx);
    minY = min(minY, ry);
    maxY = max(maxY, ry);
  }
  return (widthM: maxX - minX, heightM: maxY - minY);
}

const _metersPerDegreeLat = 111320.0;

/// 라벨 심볼의 `text-size` 표현식. 미터로 실어 둔 크기를 zoom에서 px으로 바꾼다.
///
/// **zoom 보간을 최상위에 둬야 한다.** 스타일 스펙은 `["zoom"]`을 최상위
/// `interpolate`/`step`의 입력으로만 허용한다. `["*", ["get", ...], ["interpolate",
/// ["zoom"], ...]]`처럼 안쪽에 넣으면 네이티브가 표현식을 거부해 레이어가 조용히
/// 기본 크기로 떨어진다. 그래서 **stop 값 쪽**에 feature 계산을 넣는다.
///
/// stop을 zoom 1레벨 간격으로 촘촘히 두는 이유는 하한/상한 때문이다. 크기는
/// zoom마다 2배씩 늘어나는 지수 곡선인데, 여기에 clamp가 걸리면 더 이상 지수가
/// 아니다. 양 끝점만 두고 보간하면 clamp 구간에서 값이 어긋나므로, 레벨마다
/// clamp된 값을 직접 찍어 그 사이만 잇는다.
///
/// [latitude]는 픽셀당 미터가 위도에 따라 달라져서 필요하다(도면 하나 안에서는
/// 사실상 상수라 층 중심 위도 하나면 충분하다).
List<Object> storeLabelTextSizeExpression({
  required double latitude,
  double minPx = kStoreLabelMinPx,
  double maxPx = kStoreLabelMaxPx,
}) {
  // MapLibre의 zoom은 "세계가 512 논리 픽셀에 들어가는 zoom"이 0이다. 256px
  // 기준 상수(156543)를 쓰면 배율이 정확히 2배 어긋난다 —
  // [metersPerPixelAtZoom0Equator] 정의 위 주석에 실측 근거가 있다.
  final metersPerPixelZ0 =
      metersPerPixelAtZoom0Equator * cos(latitude * pi / 180);

  final stops = <Object>[];
  for (var zoom = _textSizeStopMinZoom; zoom <= _textSizeStopMaxZoom; zoom++) {
    final pixelsPerMeter = pow(2, zoom) / metersPerPixelZ0;
    stops.add(zoom.toDouble());
    stops.add(<Object>[
      'max',
      minPx,
      <Object>[
        'min',
        maxPx,
        <Object>[
          '*',
          <Object>['get', kStoreLabelEmMetersProperty],
          pixelsPerMeter,
        ],
      ],
    ]);
  }
  // 구간 사이는 base 2 지수 보간이다. clamp에 걸리지 않은 구간에서는 이웃 stop이
  // 정확히 2배씩이라 보간 결과가 참값과 일치한다.
  return <Object>[
    'interpolate',
    <Object>['exponential', 2],
    <Object>['zoom'],
    ...stops,
  ];
}

/// stop을 찍는 zoom 범위. 실내 타일이 사는 구간을 덮는다. 밖에서는 보간이 양
/// 끝값을 유지하는데, 그 값은 이미 하한/상한에 걸려 있어 문제가 없다.
const _textSizeStopMinZoom = 16;
const _textSizeStopMaxZoom = 22;
