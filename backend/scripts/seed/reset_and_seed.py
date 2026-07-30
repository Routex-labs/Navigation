# 개발 DB를 초기화하고 더현대 서울 Studio 데이터를 적재하는 CLI.
# 적재 범위는 studio_adapter.STUDIO_DIR에 있는 층 전부다
# (현재 resources/studio/thehyundai-seoul-dabeeo의 B6~6F 12개 층).
# 층 목록은 studio_adapter가 디렉토리에서 찾는다.
# 실행 방법 (backend/ 디렉토리에서):
#   python -m scripts.seed.reset_and_seed

from __future__ import annotations

import json
from datetime import UTC, datetime
from pathlib import Path

from app.core.config import API_ROOT
from app.core.database import SessionLocal
from app.graph import integrity as graph_integrity
from scripts.seed.reset_database import reset_database
from scripts.seed.studio_adapter import seed_studio

# 시드 검증 결과·그래프 통계 artifact. data/는 .gitignore라 커밋되지 않는다.
# 시드가 무엇을 넣었는지(건물·층·노드·간선 수)와 남은 경고(고립 컴포넌트 등)를
# 한 파일로 남겨, 재시드할 때마다 무결성 상태를 확인·비교할 수 있게 한다.
SEED_REPORT_PATH = API_ROOT / "data" / "seed_graph_report.json"


# 시드된 그래프를 다시 읽어 검증하고, 리포트를 artifact JSON으로 남긴다.
# seed_studio가 이미 커밋 전 게이트로 에러를 막으므로, 여기서는 통계·경고 기록이 목적이다.
def write_seed_report(path: Path = SEED_REPORT_PATH) -> graph_integrity.GraphReport:
    session = SessionLocal()
    try:
        report = graph_integrity.validate_graph(graph_integrity.collect_graph_data(session))
    finally:
        session.close()

    payload = {"generated_at": datetime.now(UTC).isoformat(), **report.to_dict()}
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return report


# 기존 DB를 비운 뒤 Studio 전 층을 적재한다.
def reset_and_seed_studio() -> None:
    reset_database()
    seed_studio()


if __name__ == "__main__":
    reset_and_seed_studio()
    report = write_seed_report()
    stats = report.stats
    print(
        f"개발 DB 초기화 및 Studio 데이터 적재 완료 - "
        f"건물 {stats['buildings']} 층 {stats['floors']} 노드 {stats['nodes']} "
        f"간선 {stats['edges']}(전이 {stats['transfer_edges']})"
    )
    if report.warnings:
        print(f"경고 {len(report.warnings)}건 (자세한 내용은 {SEED_REPORT_PATH}).")
    print(f"검증 리포트: {SEED_REPORT_PATH}")
