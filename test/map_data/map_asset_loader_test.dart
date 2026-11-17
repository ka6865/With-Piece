import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/map_data/map_asset_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('번들에서 두 애셋을 읽는다', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provinces = await container.read(provinceMapAssetProvider.future);
    final regions = await container.read(regionMapAssetProvider.future);
    expect(provinces.features.length, 17);
    expect(regions.features.length, 229);
  });
}
