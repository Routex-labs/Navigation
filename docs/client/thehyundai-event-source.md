# 더현대 서울 행사 — 원본 조사와 앱 배선 (2026-08-21 실측)

팝업·전시를 앱에 싣기 전에 **원본이 무엇을 주는지** 재고, 그 결과로 무엇을 만들었는지
남긴다. 여기 있는 수치는 전부 2026-08-21에 직접 받아 확인한 값이다.

## 원본은 어디에 있나

`ehyundai.com/newPortal/DP/DP000000_V.do?branchCd=B00140000`은 302로
**`thehyundaiseoul.ehyundai.com`**(Next.js)으로 넘어간다. 본사 포털의 행사안내
페이지는 이 지점에 대해 0건을 준다.

| 무엇 | 어디 |
|---|---|
| 전체 목록 | `thehyundaiseoul.ehyundai.com/sitemap.xml` |
| 행사 상세 | `/event-info/{ID}` (12건) |
| **주간 팝업·다이닝** | `/issue-diary/{UUID}` (5쪽, 25건) |
| 이미지 | `imgprism.ehyundai.com` · Supabase 퍼블릭 버킷 |
| 내부 API | `apiprism.ehyundai.com` — **robots가 `/api/`를 막는다** |

robots(`Allow: /` · `Disallow: /api/`, `/styleguide`)는 위 경로를 막지 않고 sitemap을
스스로 공개한다. 본사 `ehyundai.com`도 행사 경로는 열려 있다(막는 것은 `/images/`·
`/upload/`·`/attachfiles/`와 `branchCd=B00147100` — 다른 점포다).

## 데이터는 HTML이 아니라 flight 페이로드에 있다

본문만 긁으면 목록이 1건만 나온다. 실제 값은 Next.js RSC 페이로드
(`self.__next_f.push([1,"…"])`) 안에 JSON으로 들어 있다.

```json
{"title":"명탐정 코난\nWIND FESTIVAL",
 "period_start":"2026-08-20","period_end":"2026-08-26",
 "place":"지하2층 POP-UP@ICONIC","hero_image_url":"…",
 "blocks":[{"type":"heading",…},{"type":"products",…},{"type":"notice",…}]}
```

`period_start`/`period_end`가 **ISO 날짜**라 표기 파싱이 필요 없다. 중복을 걷으면
**25건**, 그중 기간이 있는 것 **17건**이다(상시 브랜드 소개는 기간이 빈다).

`blocks`가 상세 본문이다: `heading` · `paragraph` · `products`(구매 특전) · `notice` ·
`rows` · `image` · `divider` · `kv` · `tel` · `link`. **`products`를 놓치기 쉽다** —
`type=="image"`만 세면 코난·핫토이가 0장으로 보이는데, 특전 사진은 전부 여기 있다.

## place → storeId 매칭 (17/17)

`place` 문구를 라이브 `store-index`(1,640건)에 붙인다. 규칙은 두 단이다.

1. 층 접두(`지하2층`→`B2`)를 떼고 이름을 정규화해 같은 층에서 찾는다
   (`POP-UP@ICONIC` → `POP-UP ICONIC B2`, `ATTAG!` → `ATTAG`).
2. 실패하면 **괄호 안 이웃 매장**으로 찾는다 — `해당 매장 (몽블랑 옆)`처럼 본문이
   장소를 안 줄 때 유일한 단서다.

자동으로 12건이 붙고, 나머지 5건은 손으로 채웠다.

| 남은 것 | 어떻게 정했나 |
|---|---|
| `1층 GATE 1·3 앞` (3건) | 아래 GATE 표 |
| `지하1층 중앙 에스컬레이터 옆 행사장` | B1에 행사장은 `식품 행사장` 하나뿐이고, 그것이 중앙 에스컬레이터(ES2 — 건물 중심 최근접) 옆 13m다 |
| 아마이모찌도넛 (`place` 빈 값) | 본문 산문의 `지하1층 POP-UP STUDIO (핑크스핫도그 옆)` |

## GATE 번호 ↔ 출입구

**출입구는 이미 도면에 있다.** 이름이 `출구`, 소분류가 `교통`, `kind`가 `facility`라
`gate`·`출입구`·`kind=='store'`로 찾으면 전부 놓친다. 1층에 5개이고 전부
`entrance_node_id`를 갖는다(`domain/route/building_entrances.dart`가 이미 쓰고 있다).

번호는 층별 안내도의 ①~⑤다. `centroid_local_m` 배치가 안내도 번호 위치와 일치하고,
최근접 브랜드로 재확인했다(1위 대비 2위가 2배 이상 멀어 애매한 것이 없다).
**도면은 북쪽이 위가 아니라 약 48° 돌아가 있다.**

| 번호 | 방위 | 랜드마크 | storeId |
|---|---|---|---|
| ① | 남서 | 프라다·버버리 | `PO-HwdghqaiS1983` |
| ② | 북서 | 보테가 베네타 | `PO-OtkDgCUwm0591` |
| ③ | 북동 | 티파니앤코 | `PO-aCd83OWPJ4438` |
| ④ | 남동 | 셀린느·생로랑 | `PO-IUr0JcJdy0927` |
| ⑤ | 남 | 페라가모·몽클레르 | `PO-37OFT9ZUH7718` |

## 사진 — 750이 상한이다

포스터를 화면 가득 채울 수 있는지가 화면 설계를 갈랐다. 세 경로를 다 막아 봤다.

- Supabase 변환(`render/image?width=2000`)은 **업스케일을 안 한다**(1500 원본 →
  1500, 750 원본 → 750).
- `blocks`의 본문 이미지도, 모바일 포털 상세(`/mobile/SN/SN_0201000.do`)의
  `evntCrdInf/imgPath2`·`img1/img2ItemNmPrcTypeInf`도 전부 **750×750**이다.
- HTML은 `width="1200"`이라고 적어 놓고 실제로는 750을 내려준다.

**전부 정사각이고 세로 사진이 하나도 없다.** 그래서 포스터는 화면 폭에만 맞추고
(1080/750 = 1.44배) 세로는 채우지 않는다 — 세로까지 채우면 3배라 눈에 띄게 뭉갠다.
공식 모바일 웹도 같은 방식이다.

## 앱에 어떻게 물려 있나

지도 위 가로 열의 **"이벤트" pill** 하나가 진입점이다.

```
이벤트 pill → 목록(썸네일) → 한 줄 탭 → 포스터 전면
                                        ↓ 좌우 스와이프로 오늘 전체
                                        ↓ 아래로 스크롤하면 특전·유의사항
                                        ↓ "여기로 안내"
                                     상세 시트 → 기존 안내
```

| 무엇 | 어디 |
|---|---|
| 데이터(17건·이미지 66장) | `client/assets/mock/events.json` · `client/assets/events/` |
| 목록 규칙·본문 블록 파싱 | `client/lib/domain/event/building_events.dart` |
| 검증 기준 | `client/test/domain/event/building_events_test.dart` |
| 목록 시트 | `.../widgets/sheets/events_sheet.dart` |
| 포스터 화면 | `.../widgets/sheets/event_poster_view.dart` |
| pill·핸들러·제목 교체 | `map_shell_screen.dart` · `parts/sheets.dart` |

### 정한 것

- **행사 중인 매장은 제목이 행사 이름이다.** `_targetFor`가 상세 시트의 유일한
  깔때기라 거기 한 곳만 고쳤다 — 검색·지도 탭·근처 매장이 함께 바뀐다. 원래 매장명은
  메타 줄에 남는다. **지도 라벨과 검색은 그대로다** — 라벨은 서버 도면이 소유하고,
  `POP-UP ICONIC B2`로 검색해도 찾아져야 한다.
- **매칭은 이름이 아니라 `placeId`로 한다.** 같은 팝업 칸에 행사가 며칠씩 갈아드는데
  이름으로 맞추면 `POP-UP EAST`처럼 이름 겹치는 칸에서 엉뚱한 행사가 붙는다.
- **pill은 실내/야외를 가리지 않는다.** 오늘 뭘 하는지는 건물에 들어가기 전에 궁금한
  것이라 진입까지 맡긴다(`enterBuildingIfNeeded: true` — 공유 링크와 같은 맥락).
- **좌표가 없어도 목록·포스터에는 남긴다.** 장소 문구는 읽을 값이 있고, 안내 버튼만
  잠근다. 감추면 사용자는 그 행사가 없는 줄 안다.
- **빈 목록은 파싱 실패로 본다.** 손으로 넣은 스냅샷이라 0건은 "행사가 없다"가 아니라
  "파일이 깨졌다"에 가깝다. 다만 화면 문구는 둘을 가르지 않는다.
- **모르는 블록 종류는 담아만 두고 화면이 건너뛴다.** 원본이 새 종류를 더해도 목록이
  통째로 깨지지 않는다.
- **매장 색인 대기에 시한(6초)을 건다.** 목록은 에셋만으로 그릴 수 있는데 시한 없이
  기다리면 서버에 못 닿을 때 예외가 아니라 멎는다 — 실기기에서 실제로 그랬다.

### 자동 수집을 아직 안 하는 이유

수집 경로는 확정됐다(`sitemap.xml` → `/issue-diary/{UUID}` → flight 파싱 → `place`
매칭). 그런데도 크론을 붙이지 않았다 — **다음 주 데모까지는 이 스냅샷으로 충분하고**,
그 뒤에도 쓸 기능으로 판명된 다음에 붙이는 편이 싸다.

붙일 때 주의할 것 둘.

- flight 페이로드는 공식 계약이 아니라 Next.js 내부 형식이다. 사이트가 프레임워크를
  올리면 깨진다. **파서가 0건을 내면 조용히 빈 목록을 보이지 말고 실패로 처리한다.**
- DB에 넣는다면 **매장 행을 고치지 말고 별도 테이블**이어야 한다. 한 매장에 행사가
  동시에 여럿 열리고(B1 식품 행사장에 지금 4건이 겹친다) 끝나면 되돌려야 하는데,
  매장 칸을 덮어쓰면 원래 값을 아무도 모른다.
