#!/usr/bin/env python3
"""퍼즐 조각 229개의 인접 관계를 계산해 추천 기능용 애셋을 만든다.

설계 문서 16.2의 빈 조각 여행 추천이 이 데이터를 쓴다. 원본이 위상 데이터라
경계를 맞대는 조각은 같은 좌표를 공유한다. 따라서 선분 교차 계산 없이
정점 공유만으로 인접을 판정할 수 있다.

입력은 topo-simple을 역변환한 평면 JSON이다. 형식은
{"features": [{"code": ..., "name": ..., "polygons": [[[[lon, lat]]]]}]}

사용법:
  python3 build_adjacency.py <flat.json> [출력경로]
"""

import collections
import json
import re
import sys

MERGE_TARGETS = {
    "수원시", "성남시", "안양시", "안산시", "고양시", "용인시",
    "청주시", "천안시", "전주시", "포항시", "창원시",
}

# 정점 비교 정밀도. 소수점 4자리는 약 11m로, 위상 데이터의 공유 정점을
# 잡아내면서 부동소수 오차는 흡수한다.
COORD_PRECISION = 4

# 경계를 공유하지 않지만 육로로 이어진 조각 쌍. 연륙교 기준이며
# 배로만 갈 수 있는 옹진군(23320)과 울릉군(37430)은 의도적으로 제외한다.
# 창원시는 병합 조각이라 대표 구 코드를 접미사로 쓴 id를 갖는다(설계 문서 5.2).
BRIDGE_PAIRS = [
    ("21040", "21010", "영도구 - 부산 중구, 부산대교/영도대교"),
    ("23310", "31230", "강화군 - 김포시, 강화대교"),
    ("38090", "38-38111", "거제시 - 창원시, 거제대교"),
    ("36460", "36400", "완도군 - 해남군, 완도대교"),
    ("36470", "36400", "진도군 - 해남군, 진도대교"),
    ("38350", "38360", "남해군 - 하동군, 남해대교"),
]

EXPECTED_PIECES = 229
EXPECTED_SHARED_PAIRS = 584


def merged_city(name):
    """이름이 병합 대상 일반구면 모시 이름을 준다. 아니면 None."""
    matched = re.match(r"^(.+시)(.+구)$", name)
    if matched and matched.group(1) in MERGE_TARGETS:
        return matched.group(1)
    return None


def build_id_map(features):
    """조각 id를 확정한다.

    병합 조각 id는 시 이름이 아니라 대표 구 코드를 접미사로 쓴다(설계 문서 5.2).
    시 이름이 바뀌면 PK가 함께 바뀌는 문제를 피하기 위한 것이다. 대표 구는
    해당 시에서 코드가 가장 작은 구다. 시 전체를 봐야 최솟값을 알 수 있으므로
    피처를 한 번 훑어 대표를 정한 뒤 id를 만든다.
    """
    city_codes = collections.defaultdict(list)
    for feature in features:
        city = merged_city(feature["name"])
        if city:
            city_codes[city].append(feature["code"])

    city_ids = {}
    for city, codes in city_codes.items():
        city_ids[city] = codes[0][:2] + "-" + min(codes)

    id_map = {}
    names = {}
    for feature in features:
        code = feature["code"]
        city = merged_city(feature["name"])
        if city:
            id_map[code] = city_ids[city]
            names[city_ids[city]] = city
        else:
            id_map[code] = code
            names[code] = feature["name"]

    return id_map, names


def build(features):
    """정점 공유로 인접 집합을 만든다."""
    id_map, names = build_id_map(features)
    vertex_owners = collections.defaultdict(set)

    for feature in features:
        pid = id_map[feature["code"]]
        for polygon in feature["polygons"]:
            for ring in polygon:
                for lon, lat in ring:
                    key = (round(lon, COORD_PRECISION), round(lat, COORD_PRECISION))
                    vertex_owners[key].add(pid)

    adjacency = collections.defaultdict(set)
    for owners in vertex_owners.values():
        if len(owners) < 2:
            continue
        for a in owners:
            for b in owners:
                if a != b:
                    adjacency[a].add(b)

    return names, adjacency


def pair_count(adjacency):
    return sum(len(v) for v in adjacency.values()) // 2


def main(path, out_path=None):
    features = json.load(open(path, encoding="utf-8"))["features"]
    names, adjacency = build(features)

    if len(names) != EXPECTED_PIECES:
        print("경고: 조각 수가 %d다 (기대 %d)" % (len(names), EXPECTED_PIECES))

    shared = pair_count(adjacency)
    if shared != EXPECTED_SHARED_PAIRS:
        print("경고: 정점 공유 인접쌍이 %d다 (기대 %d)" % (shared, EXPECTED_SHARED_PAIRS))

    isolated_before = sorted(pid for pid in names if not adjacency[pid])
    print("정점 공유 인접쌍: %d" % shared)
    print("고립 조각: %s" % [names[pid] for pid in isolated_before])

    # 연륙교 보완. 양쪽 id가 실재하는지 확인해 오타를 잡는다.
    for a, b, reason in BRIDGE_PAIRS:
        missing = [x for x in (a, b) if x not in names]
        if missing:
            print("실패: 존재하지 않는 조각 id %s (%s)" % (missing, reason))
            return 1
        adjacency[a].add(b)
        adjacency[b].add(a)

    isolated_after = sorted(pid for pid in names if not adjacency[pid])
    print("보완 후 인접쌍: %d" % pair_count(adjacency))
    print("보완 후 고립: %s" % [names[pid] for pid in isolated_after])

    payload = {
        "version": 1,
        "adjacency": {pid: sorted(adjacency[pid]) for pid in sorted(names)},
        "isolated": isolated_after,
    }

    if out_path:
        with open(out_path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))
        print("저장: %s" % out_path)

    return 0


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        print(__doc__)
        raise SystemExit(2)
    raise SystemExit(main(sys.argv[1], sys.argv[2] if len(sys.argv) == 3 else None))
