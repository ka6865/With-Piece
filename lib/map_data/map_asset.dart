import 'dart:convert';

// 전처리 산출물(tool/build_map_assets.dart)의 불변 모델. 형상 구조는
// 폴리곤 목록 → 링 목록(첫 링 외곽, 나머지 구멍) → 점 목록이다.
class MapAsset {
  const MapAsset({
    required this.version,
    required this.mainlandBbox,
    required this.insets,
    required this.features,
  });

  static const supportedVersion = 1;

  final int version;
  final GeoBbox mainlandBbox;
  final List<MapInset> insets;
  final List<MapFeature> features;

  factory MapAsset.parse(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    final version = json['version'];
    if (version != supportedVersion) {
      throw FormatException('지원하지 않는 지도 애셋 버전: $version');
    }
    return MapAsset(
      version: supportedVersion,
      mainlandBbox: GeoBbox._fromJson(json['mainlandBbox'] as List),
      insets: [
        for (final inset
            in (json['insets'] as List).cast<Map<String, dynamic>>())
          MapInset(
            id: inset['id'] as String,
            regionId: inset['regionId'] as String,
            bbox: GeoBbox._fromJson(inset['bbox'] as List),
            polygonIndexes: (inset['polygonIndexes'] as List).cast<int>(),
          ),
      ],
      features: [
        for (final feature
            in (json['features'] as List).cast<Map<String, dynamic>>())
          MapFeature(
            id: feature['id'] as String,
            name: feature['name'] as String,
            parentId: feature['parentId'] as String?,
            polygons: [
              for (final polygon in feature['polygons'] as List)
                [
                  for (final ring in polygon as List)
                    [
                      for (final point in ring as List)
                        GeoPoint(
                          (point[0] as num).toDouble(),
                          (point[1] as num).toDouble(),
                        ),
                    ],
                ],
            ],
          ),
      ],
    );
  }

  // 지역 이름은 유일하지 않으므로 조회는 코드로만 한다
  MapFeature? byId(String id) {
    for (final feature in features) {
      if (feature.id == id) return feature;
    }
    return null;
  }

  // 진행률 분모. 시군구 애셋에서만 의미가 있다
  Map<String, int> pieceCountByProvince() {
    final counts = <String, int>{};
    for (final feature in features) {
      final parentId = feature.parentId;
      if (parentId != null) counts[parentId] = (counts[parentId] ?? 0) + 1;
    }
    return counts;
  }
}

class MapFeature {
  const MapFeature({
    required this.id,
    required this.name,
    required this.parentId,
    required this.polygons,
  });

  final String id;
  final String name;
  final String? parentId;
  final List<List<List<GeoPoint>>> polygons;

  int get pointCount =>
      polygons.expand((p) => p).fold(0, (n, r) => n + r.length);
}

class MapInset {
  const MapInset({
    required this.id,
    required this.regionId,
    required this.bbox,
    required this.polygonIndexes,
  });

  final String id;
  final String regionId;
  final GeoBbox bbox;
  final List<int> polygonIndexes;
}

class GeoPoint {
  const GeoPoint(this.lon, this.lat);

  final double lon;
  final double lat;
}

// [서, 남, 동, 북]
class GeoBbox {
  const GeoBbox(this.west, this.south, this.east, this.north);

  factory GeoBbox._fromJson(List<dynamic> values) {
    if (values.length != 4) throw FormatException('bbox는 값 4개여야 한다: $values');
    final v = values.cast<num>();
    return GeoBbox(
      v[0].toDouble(),
      v[1].toDouble(),
      v[2].toDouble(),
      v[3].toDouble(),
    );
  }

  final double west, south, east, north;
}
