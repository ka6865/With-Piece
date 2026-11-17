# 지도 원본

`tool/build_map_assets.dart`의 입력이다. 앱은 이 파일을 읽지 않고 산출물
`assets/map/regions_v1.json`, `assets/map/provinces_v1.json`만 읽는다.

| 파일 | 원본 URL | SHA-256 |
| --- | --- | --- |
| `skorea-municipalities-2018-topo-simple.json` | https://raw.githubusercontent.com/southkorea/southkorea-maps/master/kostat/2018/json/skorea-municipalities-2018-topo-simple.json | `f27afa0240e1a93f5befdc65ef9ea9e1d95584edf7173740391e8812a7896a9c` |
| `skorea-provinces-2018-topo-simple.json` | https://raw.githubusercontent.com/southkorea/southkorea-maps/master/kostat/2018/json/skorea-provinces-2018-topo-simple.json | `af3999094b7ca9ef291d666a7ae6317454775c82a0ff5d3f470498b2265fbf6b` |

지역 코드는 kostat 2018 체계다. 시도 2자리, 시군구 5자리이며 법정동 코드와 다르다
(부산 `21`, 울산 `26`). 속성 키는 `code`, `name`, `name_eng`, `base_year`다.

원본을 갱신하면 `dart run tool/build_map_assets.dart`로 산출물을 다시 만들고,
`test/tool/build_map_assets_test.dart`의 확정값이 바뀌는지 먼저 확인한다.
