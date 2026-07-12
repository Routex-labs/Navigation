"""Extract faithful store-area polygons from supplied Hyundai floor screenshots.

The floor-guide images use a solid ``#dcdcdc`` fill for store blocks.  This
script traces those connected regions into image-pixel polygons without
guessing a relationship between a label and a nearby shape.  A label-to-shape
match needs a manual review because Korean OCR is not available in this
workspace and a wrong match would be more harmful than an unnamed polygon.
"""

from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np


BASE = Path(__file__).resolve().parents[1] / "app" / "data" / "vector_maps" / "thehyundai-seoul"
SOURCE_IMAGES = BASE / "source_images"
RETAIL_FLOORS = ("2f", "3f", "4f", "5f", "6f", "b1", "b2")
PARKING_FLOORS = ("b3", "b4", "b5", "b6")
AREA_STYLES = {
    "store_area": {"fill_bgr": (220, 220, 220), "fill_rgb": "#dcdcdc", "kind": "store"},
    "highlighted_area": {"fill_bgr": (231, 211, 231), "fill_rgb": "#e7d3e7", "kind": "amenity"},
    "facility_area": {"fill_bgr": (164, 199, 115), "fill_rgb": "#73c7a4", "kind": "amenity"},
}
MIN_COMPONENT_AREA = 100


def polygon_from_component(labels: np.ndarray, label: int) -> list[dict[str, float]]:
    component = np.where(labels == label, 255, 0).astype(np.uint8)
    contours, _ = cv2.findContours(component, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    contour = max(contours, key=cv2.contourArea)
    # A small epsilon preserves the non-rectangular blocks without creating
    # noisy one-pixel stair steps along anti-aliased edges.
    simplified = cv2.approxPolyDP(contour, epsilon=1.5, closed=True)
    return [
        {"x": float(point[0][0]), "y": float(point[0][1])}
        for point in simplified
    ]


def centroid(points: list[dict[str, float]]) -> dict[str, float]:
    polygon = np.array([[point["x"], point["y"]] for point in points], dtype=np.float32)
    moments = cv2.moments(polygon)
    if moments["m00"]:
        return {
            "x": round(float(moments["m10"] / moments["m00"]), 3),
            "y": round(float(moments["m01"] / moments["m00"]), 3),
        }
    return {
        "x": round(float(polygon[:, 0].mean()), 3),
        "y": round(float(polygon[:, 1].mean()), 3),
    }


def extract_floor(floor: str, area_types: tuple[str, ...]) -> None:
    image_path = SOURCE_IMAGES / f"{floor}.png"
    image = cv2.imread(str(image_path), cv2.IMREAD_COLOR)
    if image is None:
        raise FileNotFoundError(image_path)

    features = []
    for area_type in area_types:
        style = AREA_STYLES[area_type]
        fill_bgr = style["fill_bgr"]
        fill_mask = cv2.inRange(image, fill_bgr, fill_bgr)
        count, labels, stats, _ = cv2.connectedComponentsWithStats(fill_mask, connectivity=8)
        for label in range(1, count):
            x, y, width, height, area = (int(value) for value in stats[label])
            if area < MIN_COMPONENT_AREA or width < 8 or height < 8:
                continue
            points = polygon_from_component(labels, label)
            if len(points) < 3:
                continue
            features.append(
                {
                    "id": f"{area_type.replace('_', '-')}-{floor}-{len(features) + 1:03d}",
                    "kind": style["kind"],
                    "name": None,
                    "category": f"unmatched_extracted_{area_type}",
                    "geometry": {"type": "Polygon", "coordinates": points},
                    "centroid": centroid(points),
                    "extraction": {
                        "method": "connected_component_fill_trace",
                        "fill_rgb": style["fill_rgb"],
                        "pixel_area": area,
                        "bounding_box": {"x": x, "y": y, "width": width, "height": height},
                        "label_mapping_status": "pending_manual_review",
                    },
                }
            )

    path = BASE / f"{floor}.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    image_bounds = [feature for feature in data.get("features", []) if feature["id"] == "image-bounds"]
    data["features"] = image_bounds + features
    data["extraction_status"] = "geometry_extracted_label_mapping_pending"
    data["geometry_extraction"] = {
        "method": "connected_component_fill_trace",
        "fill_rgb": [AREA_STYLES[area_type]["fill_rgb"] for area_type in area_types],
        "feature_count": len(features),
        "label_mapping": "pending_manual_review",
    }
    notes = [note for note in data.get("notes", []) if "screenshot regions" not in note]
    notes.append(
        "Area polygons were traced from exact-color screenshot regions. "
        "Their association with transcribed store names remains pending manual review."
    )
    data["notes"] = notes
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{floor}: {len(features)} polygons")


def main() -> None:
    for floor in RETAIL_FLOORS:
        extract_floor(floor, ("store_area", "highlighted_area", "facility_area"))
    for floor in PARKING_FLOORS:
        extract_floor(floor, ("facility_area",))


if __name__ == "__main__":
    main()
