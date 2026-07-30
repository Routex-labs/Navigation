# 바이트 크기 기반 bounded LRU 타일 캐시 + 키 단위 single-flight.
#
# 왜 필요한가 — MVT 인코딩은 CPU 바운드다(층 하나 여러 타일에 수백 ms~초). 예전
# 구현은 무제한 전역 dict였다: 프로세스가 오래 살면(배포) 건물·층·줌·좌표 조합이
# 계속 쌓여 메모리가 상한 없이 늘고, 같은 키를 동시에 요청하면 각 요청이 제각기
# 인코딩을 돌려 CPU를 중복 소모한다. 이 모듈은 두 문제를 함께 막는다.
#
#   1) bounded LRU — 항목 수(max_entries)와 총 바이트(max_bytes) 두 상한을 두고,
#      둘 중 하나라도 넘으면 가장 오래 안 쓰인 항목부터 버린다. 값이 바이트열이라
#      실제 메모리를 바이트로 정확히 셀 수 있어, "항목 수"만으로는 잡히지 않는
#      큰 타일 편중을 바이트 상한이 잡는다.
#   2) single-flight — 같은 키를 여러 스레드가 동시에 요청해도 인코딩은 한 번만
#      돈다. 나머지는 그 결과를 그대로 받는다. 동기 def 핸들러가 anyio 스레드풀에서
#      병렬로 도는 환경이라(MapLibre가 층 전환 시 격자 여러 장을 동시에 요청),
#      threading.Lock 기반 키 락으로 중복 인코딩을 합친다(coalesce).

from __future__ import annotations

import threading
from collections import OrderedDict
from collections.abc import Callable, Hashable


# 키마다 하나씩 두는 single-flight 락 + 대기자 수(레퍼런스 카운트).
# 대기자가 0이 되면 딕셔너리에서 제거해, 서로 다른 키가 무한히 쌓이지 않게 한다.
class _KeyLock:
    __slots__ = ("lock", "waiters")

    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.waiters = 0


# 바이트 크기 기반 LRU. 값은 항상 bytes(=len으로 정확한 크기)를 전제한다.
class BoundedTileCache:
    def __init__(self, max_entries: int, max_bytes: int) -> None:
        if max_entries <= 0:
            raise ValueError("max_entries must be positive")
        if max_bytes <= 0:
            raise ValueError("max_bytes must be positive")
        self._max_entries = max_entries
        self._max_bytes = max_bytes
        # OrderedDict의 앞=가장 오래됨(LRU), 뒤=가장 최근. move_to_end로 갱신한다.
        self._store: OrderedDict[Hashable, bytes] = OrderedDict()
        self._current_bytes = 0
        # 캐시 구조(_store·바이트·메트릭)를 만지는 짧은 임계 구역용. 인코딩 같은
        # 무거운 작업은 이 락 밖에서 돈다.
        self._lock = threading.Lock()
        # 키 락 딕셔너리 자체를 만지는 가드. _lock과 분리해, 인코딩 대기가
        # 캐시 구조 락을 붙잡지 않게 한다.
        self._keylocks: dict[Hashable, _KeyLock] = {}
        self._keylock_guard = threading.Lock()
        # 메트릭(누적).
        self._hits = 0
        self._misses = 0
        self._coalesced = 0
        self._evictions = 0

    # 캐시 히트면 바로 돌려주고, 미스면 render()로 만든 뒤 저장한다. 같은 키를
    # 동시에 요청한 스레드는 한 번만 render()를 돌리고 나머지는 그 결과를 받는다.
    # render()가 None(그릴 게 없음)을 주면 저장하지 않고 None을 돌려준다.
    def get_or_render(self, key: Hashable, render: Callable[[], bytes | None]) -> bytes | None:
        with self._lock:
            cached = self._store.get(key)
            if cached is not None:
                self._store.move_to_end(key)
                self._hits += 1
                return cached
            self._misses += 1

        keylock = self._acquire_keylock(key)
        try:
            with keylock.lock:
                # 락을 기다리는 사이 다른 스레드가 이미 채웠을 수 있다 — 그러면
                # 인코딩을 건너뛴다(single-flight 합류).
                with self._lock:
                    cached = self._store.get(key)
                    if cached is not None:
                        self._store.move_to_end(key)
                        self._coalesced += 1
                        return cached

                value = render()
                if value is None:
                    return None
                self._put(key, value)
                return value
        finally:
            self._release_keylock(key)

    def _acquire_keylock(self, key: Hashable) -> _KeyLock:
        with self._keylock_guard:
            entry = self._keylocks.get(key)
            if entry is None:
                entry = _KeyLock()
                self._keylocks[key] = entry
            entry.waiters += 1
            return entry

    def _release_keylock(self, key: Hashable) -> None:
        with self._keylock_guard:
            entry = self._keylocks.get(key)
            if entry is None:
                return
            entry.waiters -= 1
            if entry.waiters <= 0:
                del self._keylocks[key]

    # 저장 + 상한 초과 시 LRU 축출. self._lock 안에서 부른다.
    def _put(self, key: Hashable, value: bytes) -> None:
        with self._lock:
            existing = self._store.pop(key, None)
            if existing is not None:
                self._current_bytes -= len(existing)
            self._store[key] = value
            self._current_bytes += len(value)
            self._evict_locked()

    # 항목 수·바이트 중 하나라도 상한을 넘으면 가장 오래된 것부터 버린다.
    # 방금 넣은 값 하나가 max_bytes보다 크면 그 값까지 축출돼 캐시에 안 남을 수
    # 있다 — 그래도 호출자는 이미 render() 결과를 받았으니 응답에는 문제없다.
    def _evict_locked(self) -> None:
        while self._store and (len(self._store) > self._max_entries or self._current_bytes > self._max_bytes):
            _, evicted = self._store.popitem(last=False)
            self._current_bytes -= len(evicted)
            self._evictions += 1

    # 전체 무효화(재시드 등으로 세대가 바뀌면 호출). 메트릭 누적치는 유지한다.
    def invalidate_all(self) -> None:
        with self._lock:
            self._store.clear()
            self._current_bytes = 0

    def metrics(self) -> dict[str, int]:
        with self._lock:
            return {
                "entries": len(self._store),
                "current_bytes": self._current_bytes,
                "max_bytes": self._max_bytes,
                "max_entries": self._max_entries,
                "hits": self._hits,
                "misses": self._misses,
                "coalesced": self._coalesced,
                "evictions": self._evictions,
            }
