#!/usr/bin/env python3
"""kostat 2018 시군구 GeoJSON에서 설계 문서의 확정값을 검증한다.

검증 항목은 조각 229개, 시도별 분모, 본토 bbox, 울릉/독도 인셋 분리다.
설계 문서 3장과 4장의 값이 실제 데이터에서 재현되는지 확인하는 용도다.
Flutter 쪽 전처리 스크립트(tool/build_map_assets.dart)를 구현할 때
같은 병합 규칙과 같은 bbox 계산을 적용해야 한다.

사용법:
  python3 verify_region_pieces.py <skorea-municipalities-2018-geo.json>
"""

import collections
import json
import re
import sys

# 일반구를 모시 단위로 합칠 대상. 창원시가 5조각으로 쪼개지는 것을 막는다.
MERGE_TARGETS = {
    "수원시", "성남시", "안양시", "안산시", "고양시", "용인시",
    "청주시", "천안시", "전주시", "포항시", "창원시",
}

PROVINCES = {
    "11": "서울", "21": "부산", "22": "대구", "23": "인천", "24": "광주",
    "25": "대전", "26": "울산", "29": "세종", "31": "경기", "32": "강원",
    "33": "충북", "34": "충남", "35": "전북", "36": "전남", "37": "경북",
    "38": "경남", "39": "제주",
}

EXPECTED = {
    "서울": 25, "부산": 16, "대구": 8, "인천": 10, "광주": 5,
    "대전": 5, "울산": 5, "세종": 1, "경기": 31, "강원": 18,
    "충북": 11, "충남": 15, "전북": 14, "전남": 22, "경북": 23,
    "경남": 18, "제주": 2,
}

# 설계 문서 4.3의 확정값. [서, 남, 동, 북]
# 앱이 실제로 쓰는 topo-simple 기준이다. 상세 GeoJSON은 단순화 전이라
# 꼭짓점이 더 많고 bbox가 약 0.0002도(20m 남짓) 넓게 나온다. 두 값을 각각 둔다.
EXPECTED_MAINLAND_BBOX = {
    "simple": (124.60972, 33.11252, 129.58443, 38.6136),
    "detailed": (124.60972, 33.11236, 129.58442, 38.61371),
}

ULLEUNG_CODE = "37430"

# 울릉도와 독도를 가르는 경도. 실제 간격은 130.94 ~ 131.86.
INSET_SPLIT_LON = 131.0

# 좌표 소수점 5자리(약 1m)까지 비교한다. 그보다 큰 차이는 데이터 교체 신호다.
BBOX_TOLERANCE = 1e-5


def iter_coords(geometry):
    """Polygon / MultiPolygon 모두에서 (lon, lat)을 흘려보낸다."""
    coords = geometry["coordinates"]
    polygons = coords if geometry["type"] == "MultiPolygon" else [coords]
    for polygon in polygons:
        for ring in polygon:
            for point in ring:
                yield point[0], point[1]


def bbox_of(features):
    lons = []
    lats = []
    for feature in features:
        for lon, lat in iter_coords(feature["geometry"]):
            lons.append(lon)
            lats.append(lat)
    return min(lons), min(lats), max(lons), max(lats)


def merged_city(name):
    """이름이 병합 대상 일반구면 모시 이름을 준다. 아니면 None."""
    matched = re.match(r"^(.+시)(.+구)$", name)
    if matched and matched.group(1) in MERGE_TARGETS:
        return matched.group(1)
    return None


def build_id_map(entries):
    """(code, name) 목록에서 조각 id를 확정한다.

    병합 조각 id는 `{시도2자리}-{대표구코드}`이고 대표 구는 해당 시에서 코드가
    가장 작은 구다(설계 문서 5.2). 시 전체를 봐야 최솟값을 알 수 있으므로
    한 번 훑어 대표를 정한 뒤 id를 만든다. 병합되지 않는 조각은 5자리 코드를
    그대로 쓴다.
    """
    city_codes = collections.defaultdict(list)
    for code, name in entries:
        city = merged_city(name)
        if city:
            city_codes[city].append(code)

    city_ids = {
        city: codes[0][:2] + "-" + min(codes) for city, codes in city_codes.items()
    }

    id_map = {}
    for code, name in entries:
        city = merged_city(name)
        id_map[code] = (city_ids[city], city) if city else (code, name)
    return id_map


def main(path):
    features = json.load(open(path, encoding="utf-8"))["features"]
    if len(features) != 250:
        print("경고: 원본 피처 수가 250이 아니다: %d" % len(features))

    entries = [(f["properties"]["code"], f["properties"]["name"]) for f in features]
    id_map = build_id_map(entries)

    pieces = collections.defaultdict(set)
    for code, _ in entries:
        pid, name = id_map[code]
        pieces[pid].add(name)

    failures = []

    if len(pieces) != 229:
        failures.append("조각 수가 229가 아니다: %d" % len(pieces))

    for pid, names in sorted(pieces.items()):
        if len(names) > 1:
            failures.append("id %s 에 이름이 여럿이다: %s" % (pid, sorted(names)))

    counts = collections.Counter(PROVINCES[pid[:2]] for pid in pieces)
    for province, expected in EXPECTED.items():
        actual = counts[province]
        if actual != expected:
            failures.append("%s 조각 수 불일치: 기대 %d, 실제 %d" % (province, expected, actual))

    # 본토 bbox는 울릉군을 제외하고 계산한다. 독도를 포함하면 동쪽이 131.87까지
    # 벌어져 본토가 화면 가로의 3분의 2로 줄어든다.
    mainland = [f for f in features if f["properties"]["code"] != ULLEUNG_CODE]
    actual_bbox = bbox_of(mainland)

    matched_variant = None
    for variant, expected_bbox in EXPECTED_MAINLAND_BBOX.items():
        if all(
            abs(actual - expected) <= BBOX_TOLERANCE
            for actual, expected in zip(actual_bbox, expected_bbox)
        ):
            matched_variant = variant
            break

    if matched_variant is None:
        failures.append(
            "본토 bbox가 알려진 값과 다르다: 실제 %s, 기대 %s"
            % (
                tuple(round(v, 5) for v in actual_bbox),
                EXPECTED_MAINLAND_BBOX,
            )
        )

    ulleung = [f for f in features if f["properties"]["code"] == ULLEUNG_CODE]
    if len(ulleung) != 1:
        failures.append("울릉군 피처가 1개가 아니다: %d" % len(ulleung))
    else:
        west_lons = [
            lon for lon, _ in iter_coords(ulleung[0]["geometry"]) if lon < INSET_SPLIT_LON
        ]
        east_lons = [
            lon for lon, _ in iter_coords(ulleung[0]["geometry"]) if lon >= INSET_SPLIT_LON
        ]
        if not west_lons or not east_lons:
            failures.append("울릉도/독도 분리 실패: 한쪽 그룹이 비었다")
        else:
            gap = min(east_lons) - max(west_lons)
            if gap < 0.5:
                failures.append("울릉도/독도 경도 간격이 좁다: %.4f" % gap)
            print(
                "울릉도 %.4f~%.4f / 독도 %.4f~%.4f (간격 %.4f)"
                % (min(west_lons), max(west_lons), min(east_lons), max(east_lons), gap)
            )

    # 이름 중복은 정상이다. 코드로만 조회해야 한다는 근거로 함께 출력한다.
    duplicated = sorted(
        name
        for name, n in collections.Counter(
            next(iter(names)) for names in pieces.values()
        ).items()
        if n > 1
    )

    print("조각 수: %d" % len(pieces))
    print("시도별: %s" % dict(sorted(counts.items())))
    print(
        "본토 bbox: %s (%s)"
        % (tuple(round(v, 5) for v in actual_bbox), matched_variant or "미확인")
    )
    print("중복 이름 (코드로만 조회해야 하는 근거): %s" % duplicated)

    if failures:
        for message in failures:
            print("실패: %s" % message)
        return 1
    print("검증 통과")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        raise SystemExit(2)
    raise SystemExit(main(sys.argv[1]))
