"""SVG 실내 지도를 ETL 입력용 x/y 벡터 JSON으로 변환한다."""

from __future__ import annotations

import argparse
import json
import re
from math import hypot
from pathlib import Path
from xml.etree import ElementTree as ET


SVG_NS = "http://www.w3.org/2000/svg"
NS = {"svg": SVG_NS}
NUMBER = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"
PATH_TOKEN = re.compile(rf"[A-Za-z]|{NUMBER}")
TRANSLATE = re.compile(rf"translate\(\s*({NUMBER})[ ,]+({NUMBER})\s*\)")


def _point(x: float, y: float) -> dict[str, float]:
    return {"x": round(x, 6), "y": round(y, 6)}


def parse_path_subpaths(path_data: str) -> list[list[dict[str, float]]]:
    """직선 기반 SVG path를 끊어진 subpath별 x/y 점 목록으로 바꾼다."""
    tokens = PATH_TOKEN.findall(path_data)
    subpaths: list[list[dict[str, float]]] = []
    points: list[dict[str, float]] = []
    index = 0
    command: str | None = None
    x = y = 0.0
    start_x = start_y = 0.0

    def is_command(token: str) -> bool:
        return token.isalpha()

    while index < len(tokens):
        if is_command(tokens[index]):
            command = tokens[index]
            index += 1
        if command is None:
            raise ValueError("SVG path가 명령어 없이 좌표로 시작합니다.")

        upper = command.upper()
        relative = command.islower()
        if upper == "Z":
            x, y = start_x, start_y
            command = None
            continue
        if upper not in {"M", "L", "H", "V"}:
            raise ValueError(f"지원하지 않는 SVG path 명령어입니다: {command}")

        if upper in {"M", "L"}:
            if index + 1 >= len(tokens) or is_command(tokens[index]):
                raise ValueError(f"SVG path {command} 명령의 좌표가 부족합니다.")
            next_x = float(tokens[index])
            next_y = float(tokens[index + 1])
            index += 2
            if relative:
                next_x += x
                next_y += y
            x, y = next_x, next_y
            if upper == "M":
                if points:
                    subpaths.append(points)
                    points = []
                start_x, start_y = x, y
                command = "l" if relative else "L"
        else:
            if index >= len(tokens) or is_command(tokens[index]):
                raise ValueError(f"SVG path {command} 명령의 좌표가 부족합니다.")
            value = float(tokens[index])
            index += 1
            if upper == "H":
                x = x + value if relative else value
            else:
                y = y + value if relative else value

        current = _point(x, y)
        if not points or points[-1] != current:
            points.append(current)

    if points:
        subpaths.append(points)
    return subpaths


def parse_path_points(path_data: str) -> list[dict[str, float]]:
    """단일 subpath를 x/y 점 목록으로 바꾼다."""
    subpaths = parse_path_subpaths(path_data)
    if len(subpaths) != 1:
        raise ValueError(f"단일 path에 {len(subpaths)}개의 subpath가 있습니다.")
    return subpaths[0]


def polygon_centroid(points: list[dict[str, float]]) -> dict[str, float]:
    """닫힘 점이 생략된 단순 폴리곤의 면적 중심을 계산한다."""
    if len(points) < 3:
        raise ValueError("Polygon은 최소 3개 점이 필요합니다.")

    twice_area = 0.0
    centroid_x = 0.0
    centroid_y = 0.0
    for current, following in zip(points, points[1:] + points[:1]):
        cross = current["x"] * following["y"] - following["x"] * current["y"]
        twice_area += cross
        centroid_x += (current["x"] + following["x"]) * cross
        centroid_y += (current["y"] + following["y"]) * cross

    if abs(twice_area) < 1e-12:
        return _point(
            sum(point["x"] for point in points) / len(points),
            sum(point["y"] for point in points) / len(points),
        )
    return _point(centroid_x / (3 * twice_area), centroid_y / (3 * twice_area))


def _classes(element: ET.Element) -> set[str]:
    return set(element.get("class", "").split())


def _path_feature(
    element: ET.Element,
    *,
    kind: str,
    geometry_type: str = "Polygon",
) -> dict:
    subpaths = parse_path_subpaths(element.attrib["d"])
    if geometry_type == "Polygon":
        if len(subpaths) != 1:
            raise ValueError(f"{element.attrib['id']} Polygon에 subpath가 여러 개입니다.")
        coordinates: list | list[list] = subpaths[0]
    elif len(subpaths) == 1:
        coordinates = subpaths[0]
    else:
        geometry_type = "MultiLineString"
        coordinates = subpaths
    feature = {
        "id": element.attrib["id"],
        "kind": kind,
        "name": element.get("data-name"),
        "category": element.get("data-category"),
        "geometry": {"type": geometry_type, "coordinates": coordinates},
    }
    if geometry_type == "Polygon":
        feature["centroid"] = polygon_centroid(coordinates)
    return feature


def _path_feature_with_id(
    element: ET.Element,
    *,
    feature_id: str,
    kind: str,
    geometry_type: str = "Polygon",
) -> dict:
    """id가 없는 SVG 요소에도 안정적인 합성 ID를 부여한다."""
    element.attrib.setdefault("id", feature_id)
    return _path_feature(element, kind=kind, geometry_type=geometry_type)


def _gate_feature(group: ET.Element) -> dict:
    rect = group.find("svg:rect", NS)
    if rect is None:
        raise ValueError(f"{group.attrib['id']}에 rect가 없습니다.")
    x = float(rect.get("x", "0"))
    y = float(rect.get("y", "0"))
    width = float(rect.attrib["width"])
    height = float(rect.attrib["height"])
    coordinates = [
        _point(x, y),
        _point(x + width, y),
        _point(x + width, y + height),
        _point(x, y + height),
    ]
    return {
        "id": group.attrib["id"],
        "kind": "gate",
        "name": group.attrib["id"].removeprefix("gate-"),
        "category": None,
        "geometry": {"type": "Polygon", "coordinates": coordinates},
        "centroid": polygon_centroid(coordinates),
    }


def convert_svg_floor_map(
    svg_path: Path,
    *,
    building_id: str,
    floor_id: str,
) -> dict:
    """원본 SVG에서 렌더링에 필요한 의미 있는 벡터 feature를 추출한다."""
    root = ET.parse(svg_path).getroot()
    view_box = [float(value) for value in root.attrib["viewBox"].split()]
    if len(view_box) != 4:
        raise ValueError("SVG viewBox는 min_x min_y width height 네 값이어야 합니다.")
    min_x, min_y, width, height = view_box

    features: list[dict] = []
    footprint = root.find(".//svg:path[@id='building-footprint']", NS)
    if footprint is None:
        raise ValueError("building-footprint path를 찾을 수 없습니다.")
    features.append(_path_feature(footprint, kind="footprint"))

    for path in root.findall(".//svg:path", NS):
        classes = _classes(path)
        if "store" in classes:
            features.append(_path_feature(path, kind="store"))
        elif "amenity" in classes and path.get("id"):
            features.append(_path_feature(path, kind="amenity"))

    outer_wall = root.find(".//svg:path[@id='outer-wall']", NS)
    if outer_wall is not None:
        features.append(
            _path_feature(outer_wall, kind="wall", geometry_type="LineString")
        )

    architectural_walls = root.find(".//svg:g[@id='architectural-walls']", NS)
    if architectural_walls is not None:
        for index, wall in enumerate(architectural_walls.findall("svg:path", NS), 1):
            if wall is footprint:
                continue
            features.append(
                _path_feature_with_id(
                    wall,
                    feature_id=f"wall-{index:02d}",
                    kind="wall",
                    geometry_type="LineString",
                )
            )

    for gate in root.findall(".//svg:g", NS):
        if gate.get("id", "").startswith("gate-"):
            features.append(_gate_feature(gate))

    return {
        "schema_version": "1.0",
        "building_id": building_id,
        "floor_id": floor_id,
        "source": {"type": "svg", "file": svg_path.name},
        "coordinate_system": {
            "id": "svg_viewbox_px",
            "unit": "px",
            "origin": "top-left",
            "x_axis": "right",
            "y_axis": "down",
            "view_box": {
                "min_x": min_x,
                "min_y": min_y,
                "width": width,
                "height": height,
            },
        },
        "features": features,
    }


def _translated_point(group: ET.Element) -> dict[str, float]:
    match = TRANSLATE.fullmatch(group.get("transform", ""))
    if match is None:
        raise ValueError(f"{group.get('id', 'node')}의 translate 좌표를 읽을 수 없습니다.")
    return _point(float(match.group(1)), float(match.group(2)))


def _title(group: ET.Element) -> str | None:
    title = group.find("svg:title", NS)
    return title.text.strip() if title is not None and title.text else None


def _scale_point(point: dict[str, float], scale: float) -> dict[str, float]:
    return _point(point["x"] * scale, point["y"] * scale)


def _polygon_measurements(points: list[dict[str, float]]) -> tuple[float, float]:
    twice_area = 0.0
    perimeter = 0.0
    for current, following in zip(points, points[1:] + points[:1]):
        twice_area += current["x"] * following["y"] - following["x"] * current["y"]
        perimeter += hypot(
            following["x"] - current["x"],
            following["y"] - current["y"],
        )
    return round(abs(twice_area) / 2, 3), round(perimeter, 3)


def convert_svg_navigation_dataset(
    svg_path: Path,
    *,
    building_id: str,
    building_name: str,
    floor_id: str,
    floor_name: str,
    floor_level: int,
    scale_m_per_px: float,
) -> dict:
    """SVG의 data-node/data-from/data-to를 SQLite ETL 입력 JSON으로 변환한다."""
    if scale_m_per_px <= 0:
        raise ValueError("scale_m_per_px는 0보다 커야 합니다.")

    root = ET.parse(svg_path).getroot()
    footprint = root.find(".//svg:path[@id='building-footprint']", NS)
    if footprint is None:
        raise ValueError("building-footprint path를 찾을 수 없습니다.")

    source_footprint = parse_path_points(footprint.attrib["d"])
    local_footprint = [_scale_point(point, scale_m_per_px) for point in source_footprint]
    area_m2, perimeter_m = _polygon_measurements(local_footprint)

    node_groups = [
        group
        for group in root.findall(".//svg:g", NS)
        if group.get("data-node-id")
    ]
    nodes = []
    node_points: dict[str, dict[str, float]] = {}
    for group in node_groups:
        node_id = group.attrib["data-node-id"]
        source = _translated_point(group)
        local_m = _scale_point(source, scale_m_per_px)
        node_points[node_id] = local_m
        nodes.append(
            {
                "id": node_id,
                "type": group.get("data-type", "corridor"),
                "name": group.get("data-space") or _title(group),
                "position": {"source": source, "local_m": local_m, "wgs84": None},
            }
        )

    edges = []
    for edge in root.findall(".//svg:path", NS):
        if "graph-edge" not in _classes(edge):
            continue
        from_node = edge.get("data-from")
        to_node = edge.get("data-to")
        if not from_node or not to_node:
            continue
        if from_node not in node_points or to_node not in node_points:
            raise ValueError(f"{edge.get('id')}가 존재하지 않는 노드를 참조합니다.")
        geometry = [
            _scale_point(point, scale_m_per_px)
            for point in parse_path_points(edge.attrib["d"])
        ]
        length_m = round(
            sum(
                hypot(current["x"] - previous["x"], current["y"] - previous["y"])
                for previous, current in zip(geometry, geometry[1:])
            ),
            3,
        )
        edges.append(
            {
                "id": edge.get("id") or f"edge-{from_node}-{to_node}",
                "from": from_node,
                "to": to_node,
                "length_m": length_m,
                "bidirectional": edge.get("data-bidirectional", "true").lower() == "true",
                "geometry_local_m": geometry,
            }
        )

    stores = []
    seen_spaces: set[str] = set()
    pois = []
    for group in node_groups:
        node_id = group.attrib["data-node-id"]
        node_type = group.get("data-type", "corridor")
        space = group.get("data-space")
        local_m = node_points[node_id]
        if space and node_type in {"entrance", "zone-entrance"} and space not in seen_spaces:
            seen_spaces.add(space)
            stores.append(
                {
                    "id": f"space-{node_id.lower()}",
                    "name": space,
                    "centroid": {"local_m": local_m},
                    "entrance_local_m": local_m,
                    "entrance_node_id": node_id,
                    "polygon_local_m": None,
                }
            )
        elif space and node_type not in {"entrance", "zone-entrance"}:
            pois.append(
                {
                    "id": f"poi-{node_id.lower()}",
                    "type": node_type,
                    "name": space,
                    "position": {"local_m": local_m},
                    "linked_node_id": node_id,
                }
            )

    return {
        "meta": {
            "dataset": f"{building_id}-{floor_name.lower()}",
            "generated_by": "scripts/convert_svg_floor_map.py",
            "source_attribution": [svg_path.name],
            "coordinate_system": {
                "local_m": "SVG viewBox 좌상단 원점, x=오른쪽, y=아래",
                "scale_m_per_source_unit": scale_m_per_px,
                "scale_basis": "temporary_for_flutter_demo",
            },
        },
        "building": {
            "id": building_id,
            "name": building_name,
            "floor": {"id": floor_id, "name": floor_name, "level": floor_level},
            "footprint_local_m": local_footprint,
            "area_m2": area_m2,
            "perimeter_m": perimeter_m,
        },
        "nodes": nodes,
        "edges": edges,
        "stores": stores,
        "pois": pois,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("svg", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--building-id", required=True)
    parser.add_argument("--floor-id", required=True)
    parser.add_argument("--navigation-output", type=Path)
    parser.add_argument("--building-name", default="임시 테스트 센터")
    parser.add_argument("--floor-name", default="1F")
    parser.add_argument("--floor-level", type=int, default=1)
    parser.add_argument("--scale-m-per-px", type=float, default=0.05)
    args = parser.parse_args()

    data = convert_svg_floor_map(
        args.svg,
        building_id=args.building_id,
        floor_id=args.floor_id,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"변환 완료: {args.output} ({len(data['features'])} features)")

    if args.navigation_output:
        navigation_data = convert_svg_navigation_dataset(
            args.svg,
            building_id=args.building_id,
            building_name=args.building_name,
            floor_id=args.floor_id,
            floor_name=args.floor_name,
            floor_level=args.floor_level,
            scale_m_per_px=args.scale_m_per_px,
        )
        args.navigation_output.parent.mkdir(parents=True, exist_ok=True)
        args.navigation_output.write_text(
            json.dumps(navigation_data, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(
            f"길찾기 데이터 변환 완료: {args.navigation_output} "
            f"({len(navigation_data['nodes'])} nodes, {len(navigation_data['edges'])} edges)"
        )


if __name__ == "__main__":
    main()
