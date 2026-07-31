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

class MenuItem {
  const MenuItem({
    required this.name,
    required this.price,
    required this.description,
    required this.imageAsset,
  });

  final String name;
  final String price;
  final String? description;
  final String? imageAsset;

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
        name: json['name'] as String,
        price: json['price'] as String,
        description: json['description'] as String?,
        imageAsset: json['image_asset'] as String?,
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
