"""BoundedTileCache 단위 테스트.

새로 도입한 세 가지 동작을 못 박는다.
  1) 바이트/항목 상한 초과 시 LRU 축출 — 메모리가 무제한으로 안 큰다.
  2) 같은 키 동시 요청은 single-flight로 한 번만 render 한다.
  3) get/set/invalidate 메트릭이 정확하다.

DB가 필요 없는 순수 로직이라 유닛에서 빠르게 검증한다. revision 변경(재시드)에
따른 무효화는 tile_queries 키에 세대 토큰이 들어가는 통합 테스트
(tests/integration/test_tile_cache.py)가 담당한다.
"""

import threading
import time

import pytest

from app.repositories.tile_cache import BoundedTileCache


def test_히트는_렌더_없이_같은_바이트를_돌려준다():
    cache = BoundedTileCache(max_entries=8, max_bytes=1024)
    calls = 0

    def render() -> bytes:
        nonlocal calls
        calls += 1
        return b"tile"

    first = cache.get_or_render("k", render)
    second = cache.get_or_render("k", render)

    assert first == second == b"tile"
    assert calls == 1  # 두 번째는 캐시 히트
    metrics = cache.metrics()
    assert metrics["hits"] == 1
    assert metrics["misses"] == 1
    assert metrics["entries"] == 1
    assert metrics["current_bytes"] == 4


def test_render가_None이면_저장하지_않는다():
    cache = BoundedTileCache(max_entries=8, max_bytes=1024)

    assert cache.get_or_render("missing", lambda: None) is None
    metrics = cache.metrics()
    assert metrics["entries"] == 0
    assert metrics["current_bytes"] == 0


def test_바이트_상한을_넘으면_가장_오래된_항목부터_축출한다():
    # 항목 하나 10바이트, 상한 25바이트 → 최대 2개만 남는다.
    cache = BoundedTileCache(max_entries=100, max_bytes=25)

    for key in ("a", "b", "c"):
        cache.get_or_render(key, lambda k=key: k.encode() * 10)

    metrics = cache.metrics()
    assert metrics["current_bytes"] <= 25
    assert metrics["entries"] == 2
    assert metrics["evictions"] == 1
    # 가장 먼저 넣은 a가 밀려났다.
    calls = 0

    def render_a() -> bytes:
        nonlocal calls
        calls += 1
        return b"a" * 10

    cache.get_or_render("a", render_a)
    assert calls == 1  # a는 축출됐으므로 다시 렌더된다


def test_항목_수_상한을_넘으면_축출한다():
    cache = BoundedTileCache(max_entries=2, max_bytes=1_000_000)

    for key in ("a", "b", "c"):
        cache.get_or_render(key, lambda k=key: k.encode())

    metrics = cache.metrics()
    assert metrics["entries"] == 2
    assert metrics["evictions"] == 1


def test_최근_사용_항목은_축출에서_살아남는다():
    # 상한 2. a,b 넣고 a를 다시 만져 최근으로 올린 뒤 c를 넣으면 b가 밀린다.
    cache = BoundedTileCache(max_entries=2, max_bytes=1_000_000)
    cache.get_or_render("a", lambda: b"a")
    cache.get_or_render("b", lambda: b"b")
    cache.get_or_render("a", lambda: b"a")  # a를 최근으로 → LRU는 b
    cache.get_or_render("c", lambda: b"c")  # b가 축출돼야 함

    # a를 먼저 확인한다 — b 재렌더가 새 항목을 넣으며 다시 축출을 일으키기 전에.
    a_calls = 0

    def render_a() -> bytes:
        nonlocal a_calls
        a_calls += 1
        return b"a"

    cache.get_or_render("a", render_a)
    assert a_calls == 0  # a는 최근으로 올려 살아남았다(히트)

    b_calls = 0

    def render_b() -> bytes:
        nonlocal b_calls
        b_calls += 1
        return b"b"

    cache.get_or_render("b", render_b)
    assert b_calls == 1  # b는 LRU라 밀렸으므로 재렌더


def test_동일_키_동시_요청은_한_번만_렌더한다():
    cache = BoundedTileCache(max_entries=8, max_bytes=1_000_000)
    render_calls = 0
    start = threading.Barrier(6)  # 5 워커 + 메인

    def render() -> bytes:
        nonlocal render_calls
        render_calls += 1
        time.sleep(0.05)  # 다른 스레드가 키 락에서 대기하도록 창을 벌린다
        return b"tile"

    results: list[bytes | None] = []
    results_lock = threading.Lock()

    def worker() -> None:
        start.wait()
        value = cache.get_or_render("hot", render)
        with results_lock:
            results.append(value)

    threads = [threading.Thread(target=worker) for _ in range(5)]
    for thread in threads:
        thread.start()
    start.wait()  # 다섯 스레드를 동시에 출발
    for thread in threads:
        thread.join()

    assert render_calls == 1  # single-flight: 인코딩은 한 번만
    assert results == [b"tile"] * 5  # 모두 같은 결과를 받았다
    metrics = cache.metrics()
    assert metrics["coalesced"] >= 1  # 최소 하나는 렌더를 건너뛰고 합류했다


def test_invalidate_all은_항목을_비우되_누적_메트릭은_유지한다():
    cache = BoundedTileCache(max_entries=8, max_bytes=1_000_000)
    cache.get_or_render("a", lambda: b"a")
    cache.get_or_render("a", lambda: b"a")  # hit 1

    cache.invalidate_all()

    metrics = cache.metrics()
    assert metrics["entries"] == 0
    assert metrics["current_bytes"] == 0
    assert metrics["hits"] == 1  # 누적치는 유지
    assert metrics["misses"] == 1


def test_상한은_양수여야_한다():
    with pytest.raises(ValueError):
        BoundedTileCache(max_entries=0, max_bytes=1024)
    with pytest.raises(ValueError):
        BoundedTileCache(max_entries=8, max_bytes=0)
