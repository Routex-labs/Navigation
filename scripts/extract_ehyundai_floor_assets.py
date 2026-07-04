#!/usr/bin/env python3
"""Capture public floor-map assets from the Hyundai Department Store mobile page."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlsplit

try:
    from playwright.sync_api import Page, Response, TimeoutError as PlaywrightTimeoutError, sync_playwright
except ImportError as exc:  # pragma: no cover - exercised before dependencies exist
    raise SystemExit(
        "필수 Python 패키지 playwright가 없습니다. 먼저 `pip install -r requirements.txt`와 "
        "`playwright install chromium`을 실행하세요. "
        f"원인: {exc}"
    ) from exc


DEFAULT_URL = (
    "https://www.ehyundai.com/mobile/branch/DP/floorMap.do"
    "?branchCd=B00140000&floorCd=B0100100&lang=&poi-id=&floor-id=FL-soem999bnha10599"
)
DEFAULT_OUTPUT_DIR = Path("output/floor_assets")

RESOURCE_EXTENSIONS = {"png", "jpg", "jpeg", "webp", "svg", "json", "geojson"}
RESOURCE_KEYWORDS = ("floor", "map", "poi", "route", "tile", "indoor")

MOBILE_USER_AGENT = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
)


def now_utc() -> str:
    return datetime.now(timezone.utc).isoformat()


def content_type_without_params(content_type: str) -> str:
    return content_type.split(";", 1)[0].strip().lower()


def url_extension(url: str) -> str:
    path = unquote(urlsplit(url).path)
    suffix = Path(path).suffix.lower().lstrip(".")
    if suffix and re.fullmatch(r"[a-z0-9]{1,8}", suffix):
        return suffix
    return ""


def has_resource_keyword(text: str) -> bool:
    lower_text = text.lower()
    for keyword in RESOURCE_KEYWORDS:
        if keyword == "poi":
            if re.search(r"(?<![a-z0-9])poi(?:marker|[-_./]|$)", lower_text):
                return True
            continue
        if keyword in lower_text:
            return True
    return False


def should_capture(url: str, content_type: str) -> bool:
    parsed = urlsplit(url)
    keyword_text = unquote(parsed.path).lower()
    extension = url_extension(url)
    normalized_content_type = content_type_without_params(content_type)

    if extension in RESOURCE_EXTENSIONS:
        return True
    if normalized_content_type in {
        "application/json",
        "application/geo+json",
        "image/svg+xml",
    }:
        return True
    return has_resource_keyword(keyword_text)


def extension_from_content_type(content_type: str) -> str:
    normalized = content_type_without_params(content_type)
    mapping = {
        "image/png": "png",
        "image/jpeg": "jpg",
        "image/webp": "webp",
        "image/svg+xml": "svg",
        "application/json": "json",
        "application/geo+json": "geojson",
        "text/json": "json",
        "text/html": "html",
        "text/css": "css",
        "application/javascript": "js",
        "text/javascript": "js",
    }
    return mapping.get(normalized, "")


def choose_extension(url: str, content_type: str, body: bytes) -> str:
    extension = url_extension(url)
    if extension in RESOURCE_EXTENSIONS or extension in {"js", "css", "html", "txt", "xml"}:
        return extension

    from_type = extension_from_content_type(content_type)
    if from_type:
        return from_type

    stripped = body.lstrip()
    if stripped.startswith((b"{", b"[")):
        return "json"
    if stripped.startswith(b"<svg"):
        return "svg"
    return "bin"


def resource_category(extension: str, content_type: str) -> str:
    normalized = content_type_without_params(content_type)
    if extension in {"png", "jpg", "jpeg", "webp", "svg"} or normalized.startswith("image/"):
        return "images"
    if extension in {"json", "geojson"} or normalized in {"application/json", "application/geo+json", "text/json"}:
        return "json"
    return "resources"


def write_resource_body(path: Path, body: bytes, category: str) -> int:
    if category == "json":
        try:
            parsed = json.loads(body.decode("utf-8"))
        except UnicodeDecodeError:
            parsed = json.loads(body.decode("utf-8-sig"))
        path.write_text(json.dumps(parsed, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return path.stat().st_size

    path.write_bytes(body)
    return len(body)


def safe_asset_filename(url: str, extension: str) -> str:
    parsed = urlsplit(url)
    raw_name = unquote(Path(parsed.path).name) or parsed.netloc or "resource"
    stem = Path(raw_name).stem or "resource"
    safe_stem = re.sub(r"[^A-Za-z0-9._-]+", "_", stem).strip("._-") or "resource"
    safe_stem = safe_stem[:80]
    digest = hashlib.sha256(url.encode("utf-8")).hexdigest()[:12]
    return f"{safe_stem}-{digest}.{extension}"


class ResourceCapture:
    def __init__(self, output_dir: Path) -> None:
        self.output_dir = output_dir
        self.images_dir = output_dir / "images"
        self.json_dir = output_dir / "json"
        self.resources_dir = output_dir / "resources"
        self.network_responses: list[dict[str, Any]] = []
        self.resources: list[dict[str, Any]] = []
        self._pending: list[tuple[Response, dict[str, Any]]] = []
        self._saved_urls: set[str] = set()

    def prepare_dirs(self) -> None:
        self.images_dir.mkdir(parents=True, exist_ok=True)
        self.json_dir.mkdir(parents=True, exist_ok=True)
        self.resources_dir.mkdir(parents=True, exist_ok=True)

    def on_response(self, response: Response) -> None:
        headers = response.headers
        content_type = headers.get("content-type", "")
        record = {
            "sequence": len(self.network_responses) + 1,
            "url": response.url,
            "status": response.status,
            "content_type": content_type,
            "method": response.request.method,
            "resource_type": response.request.resource_type,
        }
        self.network_responses.append(record)

        if should_capture(response.url, content_type):
            self._pending.append((response, record))

    def save_pending(self) -> None:
        pending = self._pending
        self._pending = []

        for response, record in pending:
            url = response.url
            if url in self._saved_urls:
                continue

            content_type = record.get("content_type", "")
            base_entry = {
                "url": url,
                "content_type": content_type,
                "status": record.get("status"),
                "resource_type": record.get("resource_type"),
                "size_bytes": 0,
                "saved_path": None,
            }

            try:
                body = response.body()
            except Exception as exc:  # noqa: BLE001 - record extraction failure per response
                entry = dict(base_entry)
                entry["error"] = f"{type(exc).__name__}: {exc}"
                self.resources.append(entry)
                continue

            extension = choose_extension(url, content_type, body)
            category = resource_category(extension, content_type)
            target_dir = {
                "images": self.images_dir,
                "json": self.json_dir,
                "resources": self.resources_dir,
            }[category]
            target_dir.mkdir(parents=True, exist_ok=True)
            saved_path = target_dir / safe_asset_filename(url, extension)
            size_bytes = write_resource_body(saved_path, body, category)
            self._saved_urls.add(url)

            entry = dict(base_entry)
            entry.update(
                {
                    "category": category,
                    "size_bytes": size_bytes,
                    "saved_path": str(saved_path.resolve()),
                }
            )
            self.resources.append(entry)

    def write_network_log(self) -> Path:
        network_log = self.output_dir / "network_responses.json"
        network_log.write_text(
            json.dumps(self.network_responses, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        return network_log


def load_page(page: Page, url: str) -> None:
    try:
        page.goto(url, wait_until="domcontentloaded", timeout=60_000)
    except PlaywrightTimeoutError as exc:
        raise RuntimeError(f"페이지 로딩 시간이 초과되었습니다: {url}") from exc

    try:
        page.wait_for_load_state("networkidle", timeout=20_000)
    except PlaywrightTimeoutError:
        print("networkidle 대기 시간이 초과되었습니다. 현재까지 로드된 공개 리소스로 계속 진행합니다.")

    page.wait_for_timeout(3_000)


def screenshot_page(page: Page, output_path: Path, full_page: bool = True) -> str:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(output_path), full_page=full_page)
    return str(output_path.resolve())


def click_zoom_in(page: Page, max_clicks: int = 4) -> int:
    selectors = [
        'button[aria-label*="확대"]',
        'a[aria-label*="확대"]',
        'button[title*="확대"]',
        'a[title*="확대"]',
        'button:has-text("확대")',
        'a:has-text("확대")',
        'button:has-text("+")',
        'a:has-text("+")',
        '[role="button"]:has-text("+")',
        ".zoom-in",
        ".zoomIn",
        '[class*="zoom"][class*="in"]',
        '[id*="zoom"][id*="in"]',
    ]

    clicks = 0
    for _ in range(max_clicks):
        clicked_this_round = False
        for selector in selectors:
            try:
                locator = page.locator(selector)
                count = min(locator.count(), 10)
                for index in range(count):
                    candidate = locator.nth(index)
                    if candidate.is_visible(timeout=500):
                        candidate.click(timeout=1_500)
                        page.wait_for_timeout(500)
                        clicks += 1
                        clicked_this_round = True
                        break
                if clicked_this_round:
                    break
            except Exception:
                continue
        if not clicked_this_round:
            break
    return clicks


def save_largest_map_element_screenshot(page: Page, output_path: Path) -> tuple[str | None, str | None]:
    selectors = [
        "#map",
        ".map",
        '[id*="map" i]',
        '[class*="map" i]',
        '[id*="floor" i]',
        '[class*="floor" i]',
        '[id*="indoor" i]',
        '[class*="indoor" i]',
        "canvas",
        "svg",
        'img[src*="floor" i]',
        'img[src*="map" i]',
    ]

    best_locator = None
    best_area = 0.0
    best_selector = None

    for selector in selectors:
        try:
            locator = page.locator(selector)
            count = min(locator.count(), 50)
            for index in range(count):
                candidate = locator.nth(index)
                if not candidate.is_visible(timeout=500):
                    continue
                box = candidate.bounding_box()
                if not box:
                    continue
                area = float(box["width"]) * float(box["height"])
                if box["width"] >= 150 and box["height"] >= 150 and area > best_area:
                    best_locator = candidate
                    best_area = area
                    best_selector = selector
        except Exception:
            continue

    if best_locator is None:
        return None, None

    output_path.parent.mkdir(parents=True, exist_ok=True)
    best_locator.screenshot(path=str(output_path))
    return str(output_path.resolve()), best_selector


def extract_ehyundai_floor_assets(
    url: str = DEFAULT_URL,
    output_dir: str | Path = DEFAULT_OUTPUT_DIR,
    headless: bool = True,
) -> dict[str, Any]:
    output_base = Path(output_dir)
    output_base.mkdir(parents=True, exist_ok=True)

    capture = ResourceCapture(output_base)
    capture.prepare_dirs()

    screenshots: dict[str, str] = {}
    notes: list[str] = []
    zoom_clicks = 0
    map_selector: str | None = None

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=headless)
        try:
            context = browser.new_context(
                viewport={"width": 1440, "height": 1800},
                user_agent=MOBILE_USER_AGENT,
                ignore_https_errors=True,
            )
            page = context.new_page()
            page.on("response", capture.on_response)
            load_page(page, url)
            capture.save_pending()

            screenshots["page_screenshot"] = screenshot_page(page, output_base / "page_screenshot.png", full_page=True)
            element_path, map_selector = save_largest_map_element_screenshot(
                page,
                output_base / "map_element_screenshot.png",
            )
            if element_path:
                screenshots["map_element_screenshot"] = element_path
            else:
                notes.append("도면 컨테이너 후보 요소를 찾지 못해 element screenshot은 저장하지 않았습니다.")
            capture.save_pending()
            context.close()

            highres_context = browser.new_context(
                viewport={"width": 2500, "height": 3500},
                device_scale_factor=2,
                user_agent=MOBILE_USER_AGENT,
                ignore_https_errors=True,
            )
            highres_page = highres_context.new_page()
            highres_page.on("response", capture.on_response)
            load_page(highres_page, url)
            zoom_clicks = click_zoom_in(highres_page, max_clicks=4)
            if zoom_clicks:
                notes.append(f"확대 버튼 후보를 {zoom_clicks}회 클릭한 뒤 고해상도 캡처했습니다.")
                highres_page.wait_for_timeout(1_000)
            else:
                notes.append("확대 버튼 후보를 찾지 못해 기본 확대 상태로 고해상도 캡처했습니다.")
            screenshots["highres_screenshot"] = screenshot_page(
                highres_page,
                output_base / "highres_screenshot.png",
                full_page=True,
            )
            capture.save_pending()
            highres_context.close()
        finally:
            browser.close()

    network_log = capture.write_network_log()
    manifest = {
        "source_url": url,
        "captured_at": now_utc(),
        "output_dir": str(output_base.resolve()),
        "network_response_count": len(capture.network_responses),
        "network_log": str(network_log.resolve()),
        "screenshots": screenshots,
        "map_element_selector": map_selector,
        "zoom_clicks": zoom_clicks,
        "resources": capture.resources,
        "notes": notes,
    }

    manifest_path = output_base / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Network responses: {len(capture.network_responses)}")
    print(f"Saved resources: {sum(1 for item in capture.resources if item.get('saved_path'))}")
    print(f"Manifest 저장: {manifest_path.resolve()}")
    return manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="현대백화점 모바일 층별 안내도 페이지 리소스를 추출합니다.")
    parser.add_argument("--url", default=DEFAULT_URL, help="층별 안내도 URL")
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR), help="리소스 저장 디렉토리")
    parser.add_argument("--headed", action="store_true", help="브라우저를 화면에 표시합니다.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        extract_ehyundai_floor_assets(url=args.url, output_dir=args.output_dir, headless=not args.headed)
        return 0
    except Exception as exc:  # noqa: BLE001 - CLI should print clear root cause
        print(f"오류: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
