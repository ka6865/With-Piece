// kostat 2018 TopoJSON을 앱 전용 지도 애셋으로 변환한다.
// 산출물 스키마와 값의 기준은 tools/build_map_assets_ref.py다.
import 'dart:convert';
import 'dart:io';

enum AssetKind { region, province }

const mergeCities = <String>{
  '수원시',
  '성남시',
  '안양시',
  '안산시',
  '고양시',
  '용인시',
  '청주시',
  '천안시',
  '전주시',
  '포항시',
  '창원시',
};
const ulleungRegionId = '37430';
const gyeongbukProvinceId = '37';
const insetLonSplit = 131.0;
// 시도 애셋의 경북에는 본토 폴리곤이 섞여 있어 이 경도 이상만 섬 후보로 본다
const islandMinLon = 130.0;

typedef Ring = List<List<double>>;
typedef Polygon = List<Ring>;

class BuiltInset {
  BuiltInset(this.id, this.regionId, this.bbox, this.polygonIndexes);

  final String id;
  final String regionId;
  final List<double> bbox;
  final List<int> polygonIndexes;

  Map<String, Object> toJson() => {
    'id': id,
    'regionId': regionId,
    'bbox': bbox,
    'polygonIndexes': polygonIndexes,
  };
}

class BuiltFeature {
  BuiltFeature(this.id, this.parentId, this.name);

  final String id;
  final String? parentId;
  final String name;
  final List<Polygon> polygons = [];

  Map<String, Object> toJson() => {
    'id': id,
    'parentId': ?parentId,
    'name': name,
    'polygons': polygons,
  };
}

class BuiltAsset {
  BuiltAsset(this.mainlandBbox, this.insets, this.features);

  final List<double> mainlandBbox;
  final List<BuiltInset> insets;
  final List<BuiltFeature> features;

  int get pointCount => features.fold(
    0,
    (sum, f) =>
        sum + f.polygons.expand((p) => p).fold(0, (s, r) => s + r.length),
  );

  String toJsonString() => jsonEncode({
    'version': 1,
    'mainlandBbox': mainlandBbox,
    'insets': insets,
    'features': features,
  });
}

extension Rounded5 on List<double> {
  List<double> get rounded5 => map(round5).toList();
}

// Python round(x, 5)와 같은 값을 내도록 이진값을 십진 5자리로 반올림한다
double round5(double value) => double.parse(value.toStringAsFixed(5));

Map<String, dynamic> readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

String? mergedCityOf(String name) {
  final match = RegExp(r'^(.+시)(.+구)$').firstMatch(name);
  if (match == null) return null;
  final city = match.group(1)!;
  return mergeCities.contains(city) ? city : null;
}

List<List<List<double>>> decodeArcs(Map<String, dynamic> topo) {
  final transform = topo['transform'] as Map<String, dynamic>;
  final scale = (transform['scale'] as List).cast<num>();
  final translate = (transform['translate'] as List).cast<num>();
  return [
    for (final arc in topo['arcs'] as List)
      () {
        var x = 0;
        var y = 0;
        return [
          for (final delta in arc as List)
            [
              ((x += delta[0] as int) * scale[0] + translate[0]).toDouble(),
              ((y += delta[1] as int) * scale[1] + translate[1]).toDouble(),
            ],
        ];
      }(),
  ];
}

Ring assembleRing(List<List<List<double>>> arcs, List<dynamic> indexes) {
  final points = <List<double>>[];
  for (final raw in indexes) {
    final index = raw as int;
    final arc = index < 0
        ? arcs[~index].reversed.toList(growable: false)
        : arcs[index];
    points.addAll(points.isEmpty ? arc : arc.skip(1));
  }
  if (points.isNotEmpty &&
      (points.first[0] != points.last[0] ||
          points.first[1] != points.last[1])) {
    points.add(points.first);
  }
  return points;
}

List<double> bboxOf(Iterable<Polygon> polygons) {
  final points = polygons.expand((p) => p).expand((r) => r);
  return [
    points.map((p) => p[0]).reduce((a, b) => a < b ? a : b),
    points.map((p) => p[1]).reduce((a, b) => a < b ? a : b),
    points.map((p) => p[0]).reduce((a, b) => a > b ? a : b),
    points.map((p) => p[1]).reduce((a, b) => a > b ? a : b),
  ];
}

double maxLonOf(Polygon polygon) =>
    polygon.expand((r) => r).map((p) => p[0]).reduce((a, b) => a > b ? a : b);

BuiltAsset buildMapAsset(Map<String, dynamic> topo, {required AssetKind kind}) {
  final arcs = decodeArcs(topo);
  final objects = topo['objects'] as Map<String, dynamic>;
  final geometries =
      (objects.values.first as Map<String, dynamic>)['geometries'] as List;

  final raw = [
    for (final g in geometries.cast<Map<String, dynamic>>())
      (
        code: g['properties']['code'] as String,
        name: g['properties']['name'] as String,
        // Polygon을 단일 원소 MultiPolygon으로 승격해 런타임 분기를 없앤다
        polygons: [
          for (final poly
              in g['type'] == 'Polygon' ? [g['arcs']] : g['arcs'] as List)
            [for (final r in poly as List) assembleRing(arcs, r as List)],
        ],
      ),
  ];

  final cityCodes = <String, List<String>>{};
  if (kind == AssetKind.region) {
    for (final f in raw) {
      final city = mergedCityOf(f.name);
      if (city != null) cityCodes.putIfAbsent(city, () => []).add(f.code);
    }
  }
  final cityIds = {
    for (final MapEntry(key: city, value: codes) in cityCodes.entries)
      city: '${codes.first.substring(0, 2)}-${(codes.toList()..sort()).first}',
  };

  final merged = <String, BuiltFeature>{};
  for (final f in raw) {
    final city = cityCodes.isEmpty ? null : mergedCityOf(f.name);
    final id = city != null ? cityIds[city]! : f.code;
    merged
        .putIfAbsent(
          id,
          () => BuiltFeature(
            id,
            kind == AssetKind.region ? id.substring(0, 2) : null,
            city ?? f.name,
          ),
        )
        .polygons
        .addAll(f.polygons);
  }

  final islandId = kind == AssetKind.region
      ? ulleungRegionId
      : gyeongbukProvinceId;
  final islandPolygons = merged[islandId]!.polygons;
  final ulleung = <int>[];
  final dokdo = <int>[];
  for (var i = 0; i < islandPolygons.length; i++) {
    final maxLon = maxLonOf(islandPolygons[i]);
    if (maxLon >= insetLonSplit) {
      dokdo.add(i);
    } else if (kind == AssetKind.region || maxLon >= islandMinLon) {
      ulleung.add(i);
    }
  }
  if (ulleung.isEmpty || dokdo.isEmpty) {
    throw StateError('울릉도·독도 폴리곤을 찾지 못했다: $ulleung, $dokdo');
  }

  final insetIndexes = {...ulleung, ...dokdo};
  final mainlandBbox = bboxOf([
    for (final f in merged.values)
      if (f.id != islandId)
        ...f.polygons
      else if (kind == AssetKind.province)
        for (var i = 0; i < f.polygons.length; i++)
          if (!insetIndexes.contains(i)) f.polygons[i],
  ]).rounded5;
  final insets = [
    BuiltInset(
      'ulleung',
      islandId,
      bboxOf(ulleung.map((i) => islandPolygons[i])).rounded5,
      ulleung,
    ),
    BuiltInset(
      'dokdo',
      islandId,
      bboxOf(dokdo.map((i) => islandPolygons[i])).rounded5,
      dokdo,
    ),
  ];

  // 17자리 부동소수 전개를 5자리(약 1.1m)로 줄여 애셋 크기를 절반으로 만든다
  for (final f in merged.values) {
    for (final polygon in f.polygons) {
      for (final ring in polygon) {
        for (var i = 0; i < ring.length; i++) {
          ring[i] = [round5(ring[i][0]), round5(ring[i][1])];
        }
      }
    }
  }

  return BuiltAsset(mainlandBbox, insets, merged.values.toList());
}

void writeAsset({
  required String source,
  required String output,
  required AssetKind kind,
}) {
  final asset = buildMapAsset(readJson(source), kind: kind);
  File(output).writeAsStringSync(asset.toJsonString());
  stdout.writeln('$output: 조각 ${asset.features.length}, 점 ${asset.pointCount}');
}

void main() {
  writeAsset(
    source: 'tool/map_source/skorea-municipalities-2018-topo-simple.json',
    output: 'assets/map/regions_v1.json',
    kind: AssetKind.region,
  );
  writeAsset(
    source: 'tool/map_source/skorea-provinces-2018-topo-simple.json',
    output: 'assets/map/provinces_v1.json',
    kind: AssetKind.province,
  );
}
