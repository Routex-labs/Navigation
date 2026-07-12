"""Sync official Dabeeo POIs and linked object polygons into floor JSON files.

Credentials are read from Hyundai's public floor-map page for the duration of
the request only. Tokens and credentials are never written to disk.
"""

from __future__ import annotations

import argparse
import base64
import json
from collections import defaultdict
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen


BASE = Path(__file__).resolve().parents[1] / "app" / "data" / "vector_maps" / "thehyundai-seoul"
PAGE_URL = (
    "https://www.ehyundai.com/mobile/branch/DP/floorMap.do"
    "?branchCd=B00140000&floorCd=B010B100"
)
TOKEN_URL = "https://oauth.dabeeomaps.com/oauth/token"
MAP_URL = "https://api.dabeeomaps.com/v2/map?t=JS"
USER_AGENT = "Navigation floor-data synchronizer/1.0"


class HiddenInputParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.values: dict[str, str] = {}

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag != "input":
            return
        attributes = dict(attrs)
        input_id = attributes.get("id")
        if input_id:
            self.values[input_id] = attributes.get("value") or ""


def read_url(request: Request) -> bytes:
    with urlopen(request, timeout=30) as response:
        return response.read()


def load_official_map(page_url: str) -> dict:
    page_request = Request(page_url, headers={"User-Agent": USER_AGENT})
    parser = HiddenInputParser()
    parser.feed(read_url(page_request).decode("utf-8"))
    client_id = parser.values.get("dabeeo_client_id")
    client_secret = parser.values.get("dabeeo_client_secret")
    if not client_id or not client_secret:
        raise RuntimeError("Dabeeo credentials were not found on the public floor-map page")

    basic = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode("ascii")
    token_request = Request(
        TOKEN_URL,
        data=urlencode({"grant_type": "client_credentials"}).encode(),
        headers={
            "Authorization": f"Basic {basic}",
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": USER_AGENT,
        },
        method="POST",
    )
    token_response = json.loads(read_url(token_request))
    access_token = token_response.get("access_token")
    if not access_token:
        raise RuntimeError("Dabeeo OAuth response did not contain an access token")

    map_request = Request(
        MAP_URL,
        headers={"Authorization": f"Bearer {access_token}", "User-Agent": USER_AGENT},
    )
    response = json.loads(read_url(map_request))
    if response.get("code") not in ("00", 200, "200") or not response.get("payload"):
        raise RuntimeError(f"Unexpected Dabeeo map response: {response.get('code')!r}")
    return response["payload"]


def language_text(values: list[dict] | None, lang: str) -> str | None:
    for value in values or []:
        if value.get("lang") == lang:
            return normalize_name(value.get("text"))
    return None


def normalize_name(value: str | None) -> str | None:
    if not value:
        return None
    normalized = " ".join(value.split())
    return normalized or None


def korean_metadata(poi: dict) -> dict:
    for metadata in poi.get("metadatas") or []:
        if metadata.get("lang") != "ko":
            continue
        for item in metadata.get("metadatas") or []:
            text = item.get("text")
            if not text:
                continue
            try:
                parsed = json.loads(text)
            except json.JSONDecodeError:
                continue
            if isinstance(parsed, dict) and ("map_brand_cd" in parsed or "tel" in parsed):
                return parsed
    return {}


def point(value: dict | None) -> dict[str, float]:
    value = value or {}
    return {
        key: round(float(value.get(key, 0.0)), 6)
        for key in ("x", "y", "z")
    }


def polygon_points(values: list[dict] | None) -> list[dict[str, float]]:
    return [
        {"x": round(float(value["x"]), 6), "y": round(float(value["y"]), 6)}
        for value in values or []
        if "x" in value and "y" in value
    ]


def build_official_floor(payload: dict, floor: dict) -> dict:
    pois: list[dict] = []
    poi_ids_by_object: dict[str, list[str]] = defaultdict(list)
    names_by_object: dict[str, list[str]] = defaultdict(list)

    for poi in floor.get("pois") or []:
        metadata = korean_metadata(poi)
        name_ko = language_text(poi.get("titleByLanguages"), "ko") or normalize_name(poi.get("title"))
        name_en = language_text(poi.get("titleByLanguages"), "en")
        record = {
            "id": poi["id"],
            "object_id": poi.get("objectId"),
            "name_ko": name_ko,
            "name_en": name_en,
            "category_code": poi.get("categoryCode"),
            "position": point(poi.get("position")),
            "phone": metadata.get("tel") or None,
            "map_brand_cd": metadata.get("map_brand_cd") or None,
        }
        pois.append(record)
        if record["object_id"]:
            poi_ids_by_object[record["object_id"]].append(record["id"])
            if name_ko and name_ko not in names_by_object[record["object_id"]]:
                names_by_object[record["object_id"]].append(name_ko)

    objects = []
    for item in floor.get("objects") or []:
        if item.get("id") not in poi_ids_by_object:
            continue
        coordinates = polygon_points(item.get("coordinates"))
        objects.append(
            {
                "id": item["id"],
                "attribute_code": item.get("attributeCode"),
                "passable": bool(item.get("passable")),
                "position": point(item.get("position")),
                "geometry": {"type": "Polygon", "coordinates": coordinates},
                "poi_ids": poi_ids_by_object[item["id"]],
                "names_ko": names_by_object[item["id"]],
            }
        )

    floor_name = language_text(floor.get("name"), "ko")
    return {
        "source": {
            "provider": "dabeeo",
            "page": PAGE_URL,
            "map_endpoint": MAP_URL,
            "map_version": payload.get("versionString"),
            "deployed_date": payload.get("deployedDate"),
            "credentials_persisted": False,
        },
        "coordinate_system": {
            "id": "dabeeo_map_xy",
            "unit": "provider_map_unit",
            "x_axis_direction": payload.get("xaxisDirection"),
            "y_axis_direction": payload.get("yaxisDirection"),
            "size": payload.get("size"),
        },
        "map_id": payload.get("id"),
        "floor_id": floor.get("id"),
        "floor_name": floor_name,
        "counts": {
            "pois": len(pois),
            "linked_objects": len(objects),
            "unlinked_pois": sum(not poi.get("object_id") for poi in pois),
        },
        "pois": pois,
        "objects": objects,
    }


def sync(page_url: str, write: bool) -> None:
    payload = load_official_map(page_url)
    seen_files: set[Path] = set()
    for floor in payload.get("floors") or []:
        floor_name = language_text(floor.get("name"), "ko")
        if not floor_name:
            continue
        path = BASE / f"{floor_name.lower()}.json"
        if not path.is_file():
            raise FileNotFoundError(f"No target JSON for official floor {floor_name}: {path}")
        data = json.loads(path.read_text(encoding="utf-8"))
        official_map = build_official_floor(payload, floor)
        manual_stores = data.pop("stores", None)
        if manual_stores:
            data["manual_label_candidates"] = manual_stores
        data["official_map"] = official_map
        data["extraction_status"] = "official_map_synced_manual_image_labels_untrusted"
        if write:
            path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        seen_files.add(path)
        counts = official_map["counts"]
        print(
            f"{floor_name}: pois={counts['pois']} linked_objects={counts['linked_objects']} "
            f"unlinked_pois={counts['unlinked_pois']}"
        )

    expected_files = set(BASE.glob("*.json"))
    if seen_files != expected_files:
        missing = ", ".join(path.name for path in sorted(expected_files - seen_files))
        raise RuntimeError(f"Official map did not contain every target floor: {missing}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--page-url", default=PAGE_URL)
    parser.add_argument("--write", action="store_true", help="update the floor JSON files")
    args = parser.parse_args()
    sync(args.page_url, args.write)


if __name__ == "__main__":
    main()
