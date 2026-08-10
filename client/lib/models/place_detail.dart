/// 매장·건물 상세 API(`/buildings/{buildingId}/places/{placeId}`)의 응답 모델.
///
/// 서버가 새 섹션을 추가해도 구버전 앱의 길찾기 흐름이 깨지지 않도록, 알 수
/// 없는 섹션 type은 [fromJson] 단계에서 버린다.
enum PlaceKind { building, store, facility, excluded }

class PlaceDetail {
  const PlaceDetail({
    required this.kind,
    required this.id,
    required this.name,
    required this.subtitle,
    required this.category,
    required this.subcategory,
    required this.location,
    required this.actions,
    required this.sections,
    required this.provenance,
  });

  final PlaceKind kind;
  final String id;
  final String name;
  final String subtitle;
  final String? category;
  final String? subcategory;
  final PlaceLocation location;
  final List<PlaceAction> actions;
  final List<PlaceDetailSection> sections;
  final PlaceProvenance provenance;

  factory PlaceDetail.fromJson(Map<String, dynamic> json) {
    final rawSections = json['sections'];
    final sections = rawSections is List
        ? rawSections
            .whereType<Map<String, dynamic>>()
            .map(PlaceDetailSection.fromJson)
            .whereType<PlaceDetailSection>()
            .toList(growable: false)
        : const <PlaceDetailSection>[];
    final rawActions = json['actions'];

    return PlaceDetail(
      kind: PlaceKind.values.byName(json['kind'] as String),
      id: json['id'] as String,
      name: json['name'] as String,
      subtitle: json['subtitle'] as String,
      category: json['category'] as String?,
      subcategory: json['subcategory'] as String?,
      location: PlaceLocation.fromJson(json['location'] as Map<String, dynamic>),
      actions: rawActions is List
          ? rawActions
              .whereType<Map<String, dynamic>>()
              .map(PlaceAction.fromJson)
              .toList(growable: false)
          : const <PlaceAction>[],
      sections: sections,
      provenance:
          PlaceProvenance.fromJson(json['provenance'] as Map<String, dynamic>),
    );
  }
}

class PlaceLocation {
  const PlaceLocation({
    required this.buildingId,
    required this.floorLabel,
    required this.positionLocalM,
    required this.entranceNodeId,
  });

  final String buildingId;
  final String? floorLabel;
  final PlacePoint? positionLocalM;
  final String? entranceNodeId;

  factory PlaceLocation.fromJson(Map<String, dynamic> json) => PlaceLocation(
        buildingId: json['building_id'] as String,
        floorLabel: json['floor_label'] as String?,
        // Dart 3 pattern matching을 지원하지 않는 Flutter SDK에서도 동작하도록
        // 전통적인 타입 검사로 파싱한다.
        positionLocalM: json['position_local_m'] is Map<String, dynamic>
            ? PlacePoint.fromJson(json['position_local_m'] as Map<String, dynamic>)
            : null,
        entranceNodeId: json['entrance_node_id'] as String?,
      );
}

class PlacePoint {
  const PlacePoint({required this.x, required this.y});

  final double x;
  final double y;

  factory PlacePoint.fromJson(Map<String, dynamic> json) => PlacePoint(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
      );
}

class PlaceAction {
  const PlaceAction({required this.type, required this.label});

  final String type;
  final String label;

  factory PlaceAction.fromJson(Map<String, dynamic> json) => PlaceAction(
        type: json['type'] as String,
        label: json['label'] as String,
      );
}

class PlaceProvenance {
  const PlaceProvenance({required this.source, required this.updatedAt});

  final String source;
  final String? updatedAt;

  factory PlaceProvenance.fromJson(Map<String, dynamic> json) => PlaceProvenance(
        source: json['source'] as String,
        updatedAt: json['updated_at'] as String?,
      );
}

sealed class PlaceDetailSection {
  const PlaceDetailSection();

  static PlaceDetailSection? fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      'summary' => SummarySection(text: json['text'] as String),
      'hero' => HeroSection.fromJson(json),
      'keyValue' => KeyValueSection.fromJson(json),
      'tags' => TagsSection.fromJson(json),
      'notice' => NoticeSection.fromJson(json),
      'map' => MapSection.fromJson(json),
      'menu' => MenuSection.fromJson(json),
      'businessInfo' => BusinessInfoSection.fromJson(json),
      'demoInfo' => DemoInfoSection.fromJson(json),
      'links' => LinksSection.fromJson(json),
      _ => null,
    };
  }
}

class SummarySection extends PlaceDetailSection {
  const SummarySection({required this.text});

  final String text;
}

class HeroSection extends PlaceDetailSection {
  const HeroSection({required this.items});

  final List<HeroItem> items;

  factory HeroSection.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return HeroSection(
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(HeroItem.fromJson)
              .toList(growable: false)
          : const <HeroItem>[],
    );
  }
}

class HeroItem {
  const HeroItem({required this.localAsset});

  final String localAsset;

  factory HeroItem.fromJson(Map<String, dynamic> json) =>
      HeroItem(localAsset: json['local_asset'] as String);
}

class KeyValueSection extends PlaceDetailSection {
  const KeyValueSection({required this.items});

  final List<KeyValueItem> items;

  factory KeyValueSection.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return KeyValueSection(
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(KeyValueItem.fromJson)
              .toList(growable: false)
          : const <KeyValueItem>[],
    );
  }
}

class KeyValueItem {
  const KeyValueItem({required this.label, required this.value});

  final String label;
  final String value;

  factory KeyValueItem.fromJson(Map<String, dynamic> json) => KeyValueItem(
        label: json['label'] as String,
        value: json['value'] as String,
      );
}

class TagsSection extends PlaceDetailSection {
  const TagsSection({required this.tags});

  final List<String> tags;

  factory TagsSection.fromJson(Map<String, dynamic> json) => TagsSection(
        tags: (json['tags'] as List?)?.whereType<String>().toList(growable: false) ??
            const <String>[],
      );
}

class NoticeSection extends PlaceDetailSection {
  const NoticeSection({required this.text, required this.until});

  final String text;
  final String? until;

  factory NoticeSection.fromJson(Map<String, dynamic> json) => NoticeSection(
        text: json['text'] as String,
        until: json['until'] as String?,
      );
}

class MapSection extends PlaceDetailSection {
  const MapSection({required this.polygonLocalM});

  final List<PlacePoint> polygonLocalM;

  factory MapSection.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['polygon_local_m'];
    return MapSection(
      polygonLocalM: rawPoints is List
          ? rawPoints
              .whereType<Map<String, dynamic>>()
              .map(PlacePoint.fromJson)
              .toList(growable: false)
          : const <PlacePoint>[],
    );
  }
}

class MenuSection extends PlaceDetailSection {
  const MenuSection({required this.items});

  final List<MenuItem> items;

  factory MenuSection.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return MenuSection(
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(MenuItem.fromJson)
              .toList(growable: false)
          : const <MenuItem>[],
    );
  }
}

/// 메뉴 한 건. 이름과 사진만 반드시 있고 나머지는 전부 없을 수 있다.
///
/// 가격이 선택인 이유는 출처마다 가진 것이 다르기 때문이다 — 스타벅스 코리아 공식
/// 사이트는 가격을 공개하지 않는 대신 용량·칼로리·카페인을 주고, 푸드에는 영양정보가
/// 아예 없다. 서버는 없는 값을 빈 문자열로 채워 보내지 않고 키 자체를 뺀다(계약 4-2
/// 규칙 1). 그래서 여기서도 `''`가 아니라 `null`이며, 무엇이 비었는지에 따라 카드가
/// 무엇을 보여줄지는 위젯이 정한다.
class MenuItem {
  const MenuItem({
    required this.name,
    required this.imageAsset,
    this.category,
    this.nameEn,
    this.description,
    this.price,
    this.volume,
    this.calories,
    this.caffeine,
  });

  final String name;
  final String? imageAsset;

  /// 화면의 메뉴 탭. 탭 순서는 서버가 보낸 등장 순서다(계약 4-2 규칙 3).
  final String? category;
  final String? nameEn;
  final String? description;
  final String? price;
  final String? volume;
  final String? calories;
  final String? caffeine;

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
        name: json['name'] as String,
        imageAsset: json['image_asset'] as String?,
        category: json['category'] as String?,
        nameEn: json['name_en'] as String?,
        description: json['description'] as String?,
        price: json['price'] as String?,
        volume: json['volume'] as String?,
        calories: json['calories'] as String?,
        caffeine: json['caffeine'] as String?,
      );
}

class BusinessInfoSection extends PlaceDetailSection {
  const BusinessInfoSection({required this.items});

  final List<BusinessInfoItem> items;

  factory BusinessInfoSection.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return BusinessInfoSection(
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(BusinessInfoItem.fromJson)
              .toList(growable: false)
          : const <BusinessInfoItem>[],
    );
  }
}

class BusinessInfoItem {
  const BusinessInfoItem({required this.label, required this.value});

  final String label;
  final String value;

  factory BusinessInfoItem.fromJson(Map<String, dynamic> json) =>
      BusinessInfoItem(
        label: json['label'] as String,
        value: json['value'] as String,
      );
}

/// 공식 채널 링크. 누르면 외부 브라우저로 열린다.
///
/// 값이 사람이 읽는 문장이 아니라 **주소**라 다른 섹션과 성격이 다르다. 낡으면 거짓이
/// 되는 것이 아니라 아예 열리지 않는다.
class LinksSection extends PlaceDetailSection {
  const LinksSection({required this.items});

  final List<PlaceLink> items;

  factory LinksSection.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return LinksSection(
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(PlaceLink.fromJson)
              .toList(growable: false)
          : const <PlaceLink>[],
    );
  }
}

class PlaceLink {
  const PlaceLink({required this.label, required this.url});

  final String label;
  final String url;

  factory PlaceLink.fromJson(Map<String, dynamic> json) => PlaceLink(
        label: json['label'] as String,
        url: json['url'] as String,
      );
}

/// 소개 영상 촬영용 매장에만 붙는 운영 정보다.
///
/// [BusinessInfoSection]과 모양이 거의 같은데 섹션을 나눈 이유는 **다루는 값의 수명이
/// 다르기** 때문이다. 이쪽에는 영업시간·대표번호처럼 시간이 지나면 저절로 거짓이 되는
/// 값이 들어오고, 서버가 항목마다 확인일을 필수로 받아 함께 내려보낸다. 화면이 그
/// 확인일을 보여 줄 수 있어야 해서 별도 타입으로 둔다.
class DemoInfoSection extends PlaceDetailSection {
  const DemoInfoSection({required this.items});

  final List<DemoInfoItem> items;

  factory DemoInfoSection.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return DemoInfoSection(
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(DemoInfoItem.fromJson)
              .toList(growable: false)
          : const <DemoInfoItem>[],
    );
  }
}

class DemoInfoItem {
  const DemoInfoItem({
    required this.label,
    required this.value,
    required this.confirmedAt,
  });

  final String label;
  final String value;
  final String confirmedAt;

  // `source`는 받아 두고 화면에 그리지 않는다. 다시 열어 볼 수 있는 주소는 데이터를
  // 고치는 사람에게 필요한 것이고, 사용자에게 필요한 것은 "언제 확인한 값인가"다
  // (설계 7-A-3).
  factory DemoInfoItem.fromJson(Map<String, dynamic> json) => DemoInfoItem(
        label: json['label'] as String,
        value: json['value'] as String,
        confirmedAt: json['confirmed_at'] as String,
      );
}
