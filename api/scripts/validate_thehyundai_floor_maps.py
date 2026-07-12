"""Validate The Hyundai Seoul floor-vector JSON against its source image.

Unreviewed label associations are warnings. Structural, coordinate, and
source-image mismatches are errors.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Iterable

from PIL import Image


BASE = Path(__file__).resolve().parents[1] / "app" / "data" / "vector_maps" / "thehyundai-seoul"
GEOMETRY_TYPES = {"Polygon", "LineString", "MultiLineString"}
KINDS = {"footprint", "store", "amenity", "wall", "gate"}


def iter_points(coordinates: object) -> Iterable[dict]:
    if isinstance(coordinates, dict):
        if "x" in coordinates and "y" in coordinates:
            yield coordinates
        return
    if isinstance(coordinates, list):
        for item in coordinates:
            yield from iter_points(item)


def validate_file(path: Path) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    data = json.loads(path.read_text(encoding="utf-8"))
    prefix = path.name

    required = ("schema_version", "building_id", "floor_id", "source", "coordinate_system", "features")
    for key in required:
        if key not in data:
            errors.append(f"{prefix}: missing top-level key {key}")

    coordinate_system = data.get("coordinate_system", {})
    view_box = coordinate_system.get("view_box", {})
    width = float(view_box.get("width", 0))
    height = float(view_box.get("height", 0))
    if coordinate_system.get("origin") != "top-left" or width <= 0 or height <= 0:
        errors.append(f"{prefix}: invalid image-pixel coordinate system")

    source_file = data.get("source", {}).get("file")
    if not source_file:
        errors.append(f"{prefix}: source.file is missing")
    else:
        image_path = BASE / source_file
        if image_path.suffix.lower() == ".png" and not image_path.is_file():
            errors.append(f"{prefix}: source image not found: {source_file}")
        elif not image_path.is_file():
            warnings.append(f"{prefix}: external source artifact is not bundled: {source_file}")
        elif image_path.suffix.lower() == ".png":
            with Image.open(image_path) as image:
                if (image.width, image.height) != (int(width), int(height)):
                    errors.append(
                        f"{prefix}: view_box {int(width)}x{int(height)} != image {image.width}x{image.height}"
                    )

    seen_ids: set[str] = set()
    extracted_count = 0
    for index, feature in enumerate(data.get("features", [])):
        label = f"{prefix}: features[{index}]"
        feature_id = feature.get("id")
        if not feature_id:
            errors.append(f"{label} has no id")
        elif feature_id in seen_ids:
            errors.append(f"{label} duplicates id {feature_id}")
        else:
            seen_ids.add(feature_id)

        if feature.get("kind") not in KINDS:
            errors.append(f"{label} has invalid kind {feature.get('kind')!r}")
        geometry = feature.get("geometry", {})
        if geometry.get("type") not in GEOMETRY_TYPES:
            errors.append(f"{label} has invalid geometry type {geometry.get('type')!r}")
        points = list(iter_points(geometry.get("coordinates")))
        if not points:
            errors.append(f"{label} has no coordinates")
        for point in points:
            x, y = point.get("x"), point.get("y")
            if not isinstance(x, (int, float)) or not isinstance(y, (int, float)):
                errors.append(f"{label} has a non-numeric point")
                break
            if not (0 <= x <= width and 0 <= y <= height):
                errors.append(f"{label} point ({x}, {y}) is outside the view_box")
                break

        if feature.get("extraction"):
            extracted_count += 1
            if feature["extraction"].get("label_mapping_status") != "pending_manual_review":
                warnings.append(f"{label} extraction is not marked pending_manual_review")

    declared_count = data.get("geometry_extraction", {}).get("feature_count")
    if declared_count is not None and declared_count != extracted_count:
        errors.append(f"{prefix}: declared feature_count {declared_count} != extracted {extracted_count}")

    official_map = data.get("official_map")
    if official_map:
        official_size = official_map.get("coordinate_system", {}).get("size", {})
        official_width = float(official_size.get("width", 0))
        official_height = float(official_size.get("height", 0))
        official_pois = official_map.get("pois", [])
        official_objects = official_map.get("objects", [])
        counts = official_map.get("counts", {})
        if official_map.get("source", {}).get("credentials_persisted") is not False:
            errors.append(f"{prefix}: official map must not persist credentials")
        if counts.get("pois") != len(official_pois):
            errors.append(f"{prefix}: official POI count does not match payload")
        if counts.get("linked_objects") != len(official_objects):
            errors.append(f"{prefix}: official linked-object count does not match payload")
        poi_ids = [poi.get("id") for poi in official_pois]
        if len(poi_ids) != len(set(poi_ids)):
            errors.append(f"{prefix}: official POI IDs are not unique")
        object_ids = {item.get("id") for item in official_objects}
        if len(object_ids) != len(official_objects):
            errors.append(f"{prefix}: official object IDs are not unique")
        for poi in official_pois:
            position = poi.get("position", {})
            for field in ("name_ko", "name_en"):
                name = poi.get(field)
                if name and ("\n" in name or "\r" in name or "\t" in name):
                    errors.append(f"{prefix}: official POI {poi.get('id')} has unnormalized {field}")
            if not (0 <= position.get("x", -1) <= official_width and 0 <= position.get("y", -1) <= official_height):
                errors.append(f"{prefix}: official POI {poi.get('id')} is outside map bounds")
            object_id = poi.get("object_id")
            if object_id and object_id not in object_ids:
                errors.append(f"{prefix}: official POI {poi.get('id')} references a missing object")
        for item in official_objects:
            for position in iter_points(item.get("geometry", {}).get("coordinates")):
                if not (0 <= position.get("x", -1) <= official_width and 0 <= position.get("y", -1) <= official_height):
                    errors.append(f"{prefix}: official object {item.get('id')} is outside map bounds")
                    break

    stores = data.get("stores", [])
    names = [store.get("name") for store in stores]
    if any(not name for name in names):
        errors.append(f"{prefix}: store list contains an empty name")
    if len(names) != len(set(names)):
        warnings.append(f"{prefix}: store list contains duplicate names")
    pending = sum(
        store.get("geometry") is None or store.get("label_status") == "pending_manual_review"
        for store in stores
    )
    if pending:
        warnings.append(f"{prefix}: {pending} labels still need text/geometry review")

    return errors, warnings


def main() -> int:
    all_errors: list[str] = []
    all_warnings: list[str] = []
    paths = sorted(BASE.glob("*.json"))
    for path in paths:
        errors, warnings = validate_file(path)
        all_errors.extend(errors)
        all_warnings.extend(warnings)
        print(f"{path.name}: errors={len(errors)}, warnings={len(warnings)}")

    for warning in all_warnings:
        print(f"WARNING: {warning}")
    for error in all_errors:
        print(f"ERROR: {error}", file=sys.stderr)
    print(f"validated={len(paths)}, errors={len(all_errors)}, warnings={len(all_warnings)}")
    return 1 if all_errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
