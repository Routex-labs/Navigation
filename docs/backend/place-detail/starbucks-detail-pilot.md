# 스타벅스 리저브 상세 화면 파일럿

작성일: 2026-07-30

## 대상

- Studio id: `PO-HU40njvml1512`
- 표시명: 스타벅스 리저브
- 위치: 더현대 서울 B2

## 파일럿 범위

- 대표 이미지 두 장과 메뉴 카드 UI를 이용해 매장 상세의 사진·메뉴 영역을 검증한다.
- 사용자가 스타벅스 코리아 공식 매장 화면에서 제공한 더현대서울(B2)R점 사진 네 장을
  대표·갤러리 이미지로 쓴다.
- 영업시간은 요일별 일정으로, 메뉴·가격은 수집일과 출처를 함께 내려보낸다.

## 이미지 출처

| 파일 | 용도 | 출처 | 라이선스 |
|---|---|---|---|
| `client/assets/place_details/starbucks_logo.svg` | 매장 식별 로고 | Wikimedia Commons에 게시된 Starbucks Corporation 로고 | 상표: Starbucks Corporation, 데모 식별용 |
| `client/assets/place_details/starbucks_reserve_store_01.png` | 대표 사진 | 스타벅스 코리아 더현대서울(B2)R점 공식 매장 화면, 사용자 제공 | 데모용 |
| `client/assets/place_details/starbucks_reserve_store_02.png` | 갤러리: 바 카운터 | 스타벅스 코리아 더현대서울(B2)R점 공식 매장 화면, 사용자 제공 | 데모용 |
| `client/assets/place_details/starbucks_reserve_store_03.png` | 갤러리: 좌석 | 스타벅스 코리아 더현대서울(B2)R점 공식 매장 화면, 사용자 제공 | 데모용 |
| `client/assets/place_details/starbucks_reserve_store_04.png` | 갤러리: 리저브 바 | 스타벅스 코리아 더현대서울(B2)R점 공식 매장 화면, 사용자 제공 | 데모용 |
| `client/assets/place_details/starbucks_reserve_hero.jpg` | 대표 이미지 | Pexels, Mariya Yordanova | Pexels에서 무료 사용으로 표시 |
| `client/assets/place_details/starbucks_reserve_menu.jpg` | (미사용) 메뉴 카드 데모 이미지 | Pexels, Arda Kaykısız | Pexels에서 무료 사용으로 표시 |
| `client/assets/place_details/starbucks_menu_americano.jpg` | 메뉴: 카페 아메리카노 | 스타벅스 코리아 공식 메뉴 페이지 | 상표·이미지: Starbucks Corporation, 데모 식별용 |
| `client/assets/place_details/starbucks_menu_latte.jpg` | 메뉴: 카페 라떼 | 스타벅스 코리아 공식 메뉴 페이지 | 상표·이미지: Starbucks Corporation, 데모 식별용 |
| `client/assets/place_details/starbucks_menu_dolce_latte.jpg` | 메뉴: 스타벅스 돌체 라떼 | 스타벅스 코리아 공식 메뉴 페이지 | 상표·이미지: Starbucks Corporation, 데모 식별용 |
| `client/assets/place_details/starbucks_menu_caramel_macchiato.jpg` | 메뉴: 카라멜 마키아또 | 스타벅스 코리아 공식 메뉴 페이지 | 상표·이미지: Starbucks Corporation, 데모 식별용 |

원본 URL은 아래와 같다.

- https://www.pexels.com/photo/coffee-and-roll-served-in-a-coffee-shop-19455695/
- https://www.pexels.com/photo/coffee-with-pastries-20002825/
- https://upload.wikimedia.org/wikipedia/en/d/d3/Starbucks_Corporation_Logo_2011.svg

## 확인된 매장 사실

- 더현대 서울의 공식 층별 안내는 B2 F&B에 스타벅스 리저브를 기재한다.
- 더현대 서울 공식 안내는 이 매장을 `스타벅스 더현대서울R점(B2)`으로 표기한다.
- 스타벅스 코리아는 리저브 매장을 스페셜티 커피와 전용 추출 방식을 경험하는 매장으로
  소개한다.
- 소개: 프리미엄 커피와 스페셜한 공간이 있는 더현대서울(B2)R점.
- 주소: 서울특별시 영등포구 여의대로 108 (여의도동, 파크원).
- 주차: 지원 불가.
- 오시는 길: 여의도역 3번 출구 지하 무빙워크를 통해 더현대 서울 B2와 연결.
- 인증: 식약처 음식점 위생등급제 매우우수 매장.

## 영업시간

| 요일 | 시간 |
|---|---|
| 월~목 | 10:30~20:00 |
| 금~일 | 10:30~20:30 |

`영업 중` 표시는 이 시간표와 기기 현지 시간을 비교해 클라이언트에서 계산한다. 고정 문구를
데이터에 저장하지 않는다.

## 화면에 올리지 않기로 한 항목

위 "확인된 매장 사실"을 전부 상세 화면에 올리지는 않는다. 오버레이
(`backend/resources/store_details/starbucks-thehyundai-seoul-b2.json`)에 실제로 들어간 것은
`summary`·`hero`·`menu`와 `businessInfo`의 `주소`뿐이다.

| 항목 | 처리 | 사유 |
|---|---|---|
| 영업시간 | **제외** | 시간이 지나면 자동으로 거짓이 된다. 갱신을 보장할 방법이 없다 |
| 주차 | **제외** | 매장이 아니라 건물 단위 정보 |
| 오시는 길 | **제외** | 이미 실내에 들어와 있는 사용자에게 의미가 없다 |
| 위생등급 | **제외** | 매장 선택에 쓰이지 않는 정보 |
| 대표번호 | **제외** | `1522-3232`는 스타벅스 코리아 전국 고객센터 번호로 **이 매장 직통이 아니다.** 위 사실 목록에도 없던 값이다 |
| 주소 | 남김 | 다만 건물 주소라 전 매장이 동일하다 — 뺄지 검토 중 |

영업시간·연락처류는 **검증기가 데이터 단계에서 막는다**(`_schema.json`의
`forbidden_labels`). 넣고 싶어지면 먼저 갱신 방법을 정하고 그 목록에서 빼야 한다.
경위는 설계 [9-1](place-detail-interface.md)에 있다.

## 메뉴 사진 출처

메뉴 4종은 스타벅스 코리아 공식 메뉴 페이지의 제품 사진을 쓴다. 원본 위치는 아래와 같고,
받아서 `client/assets/place_details/`에 넣었다(각 300×313 · 4KB 내외).

| 메뉴 | 원본 (`https://image.istarbucks.co.kr/upload/store/skuimg/` 이하) |
|---|---|
| 카페 아메리카노 | `2021/04/[94]_20210430103337006.jpg` |
| 카페 라떼 | `2021/04/[41]_20210415133833725.jpg` |
| 스타벅스 돌체 라떼 | `2021/04/[128692]_20210426091933665.jpg` |
| 카라멜 마키아또 | `2021/04/[126197]_20210415154609863.jpg` |

리저브 음료도 조사해 뒀다(현재 미사용): 리저브 콜드 브루
`2024/03/[9200000002093]_20240318144604476.jpg`, 리저브 나이트로
`2021/02/[9200000002407]_20210225095106743.jpg`.

**원격 URL이 아니라 번들 asset으로 넣는 이유**는 설계 9-1 D1′의 조건이다 — 서버가 남의
이미지를 프록시하지 않고, 시트 첫 프레임이 네트워크를 기다리지 않는다(설계 8절 성능 기준).
URL을 그대로 `Image.network`에 넘기면 두 조건이 다 깨지고, CDN 경로가 바뀌면 화면이 빈다.

> 출처 페이지에는 `ⓒ 2026 Starbucks Coffee Company. All Rights Reserved.` 고지가 있다.
> 이 저장소의 다른 스타벅스 사진과 같은 **데모 식별용** 취급이며, 배포 전에 교체하거나
> 사용 허가를 받아야 한다.

## 메뉴 파일럿

아래 네 항목은 더현대서울 B2 리저브 매장으로 식별된 외부 매장 정보에서 확인한 값이다.
공식 메뉴가 아니므로 `manual` 출처와 확인일을 함께 내리고, 정기적으로 재검증한다.

| 메뉴 | 가격 | 설명 |
|---|---:|---|
| 카페 아메리카노 | 4,700원 | 강렬한 에스프레소 샷과 뜨거운 물의 조화 |
| 카페 라떼 | 5,200원 | 에스프레소와 따뜻한 우유, 우유 거품으로 마무리한 음료 |
| 스타벅스 돌체 라떼 | 6,100원 | 에스프레소와 무지방 우유를 사용한 달콤한 라떼 |
| 카라멜 마키아또 | 6,100원 | 바닐라 시럽과 우유, 에스프레소 및 카라멜 드리즐의 조화 |

확인 URL: https://www.diningcode.com/profile.php?rid=w289z6ThczxW

이 외의 매장별 메뉴·가격·영업시간·서비스는 별도 공식 근거가 생긴 뒤 추가한다.
