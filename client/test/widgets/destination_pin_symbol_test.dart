import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/core/map_fonts.dart';
import 'package:navigation_client/widgets/destination_pin.dart';

/// 도착 핀 심볼 레이어 규칙을 못 박는다.
///
/// 이 테스트가 있는 이유: 실내 화면과 야외 오버레이가 각자 같은 심볼 정의를
/// 베껴 들고 있었고, **두 곳 모두 `text-font`를 빠뜨렸다.** 생략하면 MapLibre
/// 스펙 기본값(Open Sans / Arial Unicode MS)을 요청하는데 백엔드는
/// `Pretendard Regular` 하나만 서빙하므로 글리프를 받지 못한다. 실기기에서 확인한
/// 증상은 **핀 도형은 그려지고 "도착" 글씨만 빠지는 것**이다 — 아이콘 비트맵은
/// 글리프와 무관해서 빨간 핀만 덩그러니 남는다. 웹은 CJK를 시스템 폰트로 로컬
/// 렌더해서 멀쩡해 보이므로 Chrome 확인만으로는 절대 잡을 수 없다.
void main() {
  final props = destinationPinSymbolProps(
    imageName: 'test-pin',
    iconSizeZ16: 0.18,
    iconSizeZ20: 0.38,
  ).toJson();

  group('destinationPinSymbolProps', () {
    test('백엔드가 실제로 서빙하는 fontstack을 명시한다', () {
      // 값까지 확인한다. 이름이 backend/resources/fonts/ 아래 디렉터리와
      // 정확히 같아야 하며, 하나라도 어긋나면 같은 증상이 그대로 돌아온다.
      expect(props['text-font'], [mapFontStackRegular]);
      expect(mapFontStackRegular, 'Pretendard Regular');
    });

    test('글씨는 캔버스가 아니라 심볼 textField로 얹는다', () {
      // 캔버스에 구우면 웹 CanvasKit에서 한글이 두부로 뭉개진다
      // (destination_pin.dart 상단 주석).
      expect(props['text-field'], '도착');
      expect(props['text-color'], kPinTextColor);
    });

    test('핀 바닥이 실제 좌표에 오도록 iconAnchor는 bottom이다', () {
      // top이나 center가 되면 핀이 도착 지점 위/가운데에 떠서 어디를 가리키는지
      // 어긋난다.
      expect(props['icon-anchor'], 'bottom');
    });

    test('textSize는 iconSize에서 고정 비율로 유도한다', () {
      // 손으로 적으면 zoom을 따라 둘이 따로 놀아 글씨가 머리 원을 벗어난다.
      expect(props['icon-size'], [
        'interpolate',
        ['linear'],
        ['zoom'],
        16,
        0.18,
        20,
        0.38,
      ]);
      expect(props['text-size'], [
        'interpolate',
        ['linear'],
        ['zoom'],
        16,
        0.18 / kPinIconToTextRatio,
        20,
        0.38 / kPinIconToTextRatio,
      ]);
    });

    test('핀과 글씨는 겹쳐도 항상 보인다', () {
      // 매장 라벨과 충돌한다고 도착 핀이 숨으면, 정작 목적지가 화면에서 사라진다.
      expect(props['icon-allow-overlap'], isTrue);
      expect(props['text-allow-overlap'], isTrue);
    });

    test('화면마다 다른 것은 등록 키와 크기뿐이다', () {
      // 웹 addImage는 같은 이름이 이미 있으면 새 비트맵을 버린다. 화면별로
      // 다른 키를 쓸 수 있어야 한다.
      final indoor = destinationPinSymbolProps(
        imageName: 'marker-destination-pin-v2',
        iconSizeZ16: 0.115,
        iconSizeZ20: 0.25,
      ).toJson();

      expect(indoor['icon-image'], 'marker-destination-pin-v2');
      expect(props['icon-image'], 'test-pin');
      // 나머지 규칙은 두 화면이 같아야 한다.
      expect(indoor['text-font'], props['text-font']);
      expect(indoor['icon-anchor'], props['icon-anchor']);
      expect(indoor['text-field'], props['text-field']);
    });
  });
}
