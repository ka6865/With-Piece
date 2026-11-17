import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'map_asset.dart';

final provinceMapAssetProvider = FutureProvider<MapAsset>((ref) async {
  final source = await rootBundle.loadString('assets/map/provinces_v1.json');
  return MapAsset.parse(source);
});

final regionMapAssetProvider = FutureProvider<MapAsset>((ref) async {
  final source = await rootBundle.loadString('assets/map/regions_v1.json');
  return MapAsset.parse(source);
});
