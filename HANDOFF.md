# SWARM WAR — 인수인계 (다른 컴퓨터에서 이어서 작업하기)

최종 정리: 2026-11-10 · 저장소: https://github.com/dg823/swarm_war · 협업자: `jinsupsup`(Write)
이 문서와 `docs/ROADMAP_V06_V10.md`(사용자 요구사항 원문)를 **먼저 읽고** 시작한다.

## 1. 지금 어디까지 왔나
| 항목 | 상태 |
|---|---|
| **main 브랜치** | V0.5 + FINAL(시각 효과, 게임 모드 5종, 안정성) 완료. 커밋 `ecfe856`(+ 이 인수인계 문서 커밋) |
| **V0.6 (진형)** | **아직 코드 없음.** 설계는 승인됨 → 아래 4장 |
| **wip/red-matchup 브랜치** | RED 개체 수 문제를 고치려던 **검증 안 된 수정**(3장). **GitHub에는 올리지 않았고 원래 개발 PC의 로컬 저장소에만 있다**(`1abf6b2`). 다른 컴퓨터에는 없으니 3장의 요약을 참고해 필요하면 다시 만든다. 마지막 테스트 수정 후 빌드를 확인하지 못해 컴파일 여부도 모른다 |
| 검증 결과(main) | part1 41개 통과/실패 0, part2 29개 통과(T23 렌더 성능은 보고 전용), 진화 T14a~d 4개 통과 |

구현하지 않은 것은 완성이라고 쓰지 않는다. V0.6 이후(진형, 전술 AI, 투사체, 미니맵, 추가 모드)는 전부 **미구현**이다.

> **방향 변경 (2026-11-10):** 과제 주제가 **시뮬레이션**으로 바뀌었다. 중심은 AI의 자율 행동과 그것을 관찰·분석하는 도구다. 플레이어 지휘(클릭 이동/방어, `Q`/`E`)와 게임 모드는 **삭제하지 않고 보조 기능(관찰자의 개입 도구)으로 유지**한다. 플레이어 조작을 넓히는 기능(부대 나누기 등)은 우선순위가 낮다. `docs/ROADMAP_V06_V10.md`는 원문 보관용이라 고치지 않았으니, 게임 쪽 표현은 이 방향에 맞춰 해석한다.

## 2. 새 컴퓨터 준비
1. 설치: Git, **Processing 4.x**(CLI 포함), (선택) GitHub CLI `gh`.
2. `git clone https://github.com/dg823/swarm_war` — **폴더 이름이 `swarm_war`여야 한다**(Processing은 폴더명 = 메인 `.pde` 이름).
3. 한글 폰트: `swarm_war.pde`의 `createFont("Malgun Gothic", 16)`은 Windows 전용. 다른 OS는 한글이 되는 폰트 이름으로 바꾼다(예: macOS `AppleSDGothicNeo-Regular`).
4. 실행: Processing에서 `swarm_war.pde`를 열고 Run, 또는 `Processing.exe cli --sketch=<폴더> --run`(Mac/Linux는 `processing cli`).
5. 빌드만 확인: `Processing.exe cli --sketch=<폴더> --output=<임시폴더> --force --build`
6. git 사용자: `git config user.name / user.email`(이 저장소 커밋은 `dg823`). 커밋 메시지 끝에 `Co-Authored-By: Claude ... <noreply@anthropic.com>` 를 붙여 왔다.

## 3. 알려진 문제와 wip 브랜치
**RED로 명령을 내리면 개체 수가 늘기는커녕 무너진다.** 3분 시뮬레이션(RED 지휘, BLUE/GREEN은 AI, 2시드 평균):

| RED의 행동 | 3분 뒤 RED | 원인 |
|---|---|---|
| 명령 없음(자율) | 약 300 | 굶주림 530 + BLUE에게 피살 약 390 |
| 공격 `Q` | **0** | 가장 가까운 적(BLUE)을 목표로 잡아 상성이 나쁜데 돌격 |
| 이동(먼 오아시스) | **0** | BLUE 근처로 이동 |
| 방어(근거지 오아시스) | 약 100 | 오아시스 하나는 RED 약 75~100마리만 먹일 수 있어 400마리가 굶음 |

근본 원인: 개체의 교전 판단이 **전투력 합만 보고 종족 상성을 모른다**(BLUE는 방어·지원 때문에 RED를 이긴다). 공격 명령은 공격 성향을 2배로 올려 오판을 키운다.

`wip/red-matchup`의 수정 내용(미검증):
- `Commander`: 공격 목표를 "가장 가까운 적"이 아니라 `bestTarget`(상성 점수)으로, 상성표를 전역 `MATCHUP_TABLE`/`matchupOf()`로 분리
- `Commander.force`: 에너지 30% 미만이면 복종도가 0으로 줄어 먹이 우선 / `Ecosystem.forage`: 굶주리면 오아시스로 2배 강하게
- `CombatSystem.react`: 비율에 `matchupOf(나, 가장 가까운 적)` 곱함
- `Species`: RED 유지비 1.8→1.6, 처치 에너지 30→40
- `SelfTest`: T7c, T16e 시나리오를 상성 변경에 맞게 수정(RED vs BLUE 2마리)
- 이 중간 결과(상성 반영 전 단계): 자율 303→373, 공격 0→50. **상성 반영 후는 측정하지 못했다.**

**결정:** 사용자는 "되돌리고 V0.6부터"를 택했다. 그래서 main에는 이 수정이 없다. RED 문제는 **V0.7 전술 AI에서 상성·후퇴 판단과 함께** 다룬다. wip 브랜치는 원래 개발 PC에만 있는 참고/복구용이다(위 내용만 알면 V0.7에서 처음부터 다시 구현해도 된다).

## 4. 다음 할 일: V0.6 Formation System (승인된 설계)
세부 계획은 이 저장소 밖의 계획서였으므로 핵심을 옮겨 둔다.

**원칙:** 진형은 개체를 고정 좌표에 박는 것이 아니라 *분대 중심·방향 기준 슬롯을 조향력의 한 항*으로 더하는 것. Boids(분리·정렬)는 그대로 살아 있고, 교전하면 슬롯 힘이 약해져 무너졌다 재정비된다. 진형 `NONE`이 기본이라 명령 없을 때 동작은 V0.5와 같다.

**새 파일:** `Formation.pde`(상수 `FM_NONE/LINE/WEDGE/CIRCLE/COLUMN/SCATTER`/`FM_AUTO`, 순수 함수 `slotLocal`), `Squad.pde`(`Squad`, `SquadSystem` 풀 48개), 장애물은 `World`의 `Obstacle` 배열(원형 약 8개), 테스트 `SelfTestFormation.pde`.

**분대 갱신 5Hz(12스텝):** 종족별 분대 수 `clamp(ceil(인원/70),1,12)`, 가장 가까운 중심에 배정(k-means 1회 + 소속 히스테리시스, RNG 소비 없음) → 방향 보간 → 슬롯 배정(u로 줄 나누고 줄 안은 v 순, CIRCLE은 바깥 우선) → 교전 비율 이동평균.

**조향 통합(`BoidsSystem.compute`):** 슬롯 힘 = `steer(슬롯-내위치) x FORM_W x 진형 강도 x (1 - 0.85 x 교전 비율) x 군집성 유전자`, 도착 감속, 진형 중 응집 가중치 감소, 전환 블렌드 2초, 교전 해제 1.5초 후 0.5/s로 복귀. 장애물은 반발+접선 성분, 적분에서 밀어냄, 먹이는 장애물 안에 생성 금지. 합력 상한 `2.5 x maxForce` 포화율을 측정.

**조작:** `Z` 진형 순환(기본 AUTO: 없음=NONE, 이동=종대, 공격=쐐기, 방어=원형, 후퇴=산개), `B` 분대 디버그.

**수정 파일:** `Config`, `Agent`(`squad`, `slotU/V`, `engaged`), `World`(`step`에 분대 갱신 끼우기, 장애물, `nsSquad`), `BoidsSystem`, `CombatSystem`(`engaged` 1줄), `Commander`(진형 필드), `Ecosystem`(먹이 위치), `Renderer`, `Hud`, `swarm_war.pde`, `SelfTest`(분기 1줄, 테스트용 장애물 비우기).

**검증(F1~F6, P, V):** 슬롯 기하(5종 x n=20/60/120), 분대 배정, 이동하며 진형 형성(모양 지표, Boids 유지), 교전 붕괴와 8초 내 80% 회복, 장애물(안에 0마리, 70% 도착), 호환성(결정성 T2·프레임 독립 T24·불변식 T4/T22e, 기존 part1/part2), 성능(진형 켠 스텝이 NONE 대비 +25% 이내·1,200마리 스텝 ≤ 6ms), 스크린샷 직접 확인.

**첫 작업 순서:** ① 기준선 측정(`part1`/`part2`, 스텝·그리기·HUD 1,200/2,000/3,000마리 best-of-5, 전원 상태 기록) ② `Formation.pde` + F1 ③ 분대 배정 + F2 ④ 조향 통합 + F3 ⑤ 교전/재정비 + F4 ⑥ 장애물 + F5 ⑦ 조작·HUD·디버그 ⑧ 회귀·성능·스크린샷 ⑨ 로컬 커밋, push는 사용자에게 확인.

**V0.7~V1.0 개요:** V0.7 전술 AI(Strategic 1Hz → Tactical 5Hz → Squad 5Hz → Agent) + 전선 분석 + Flow Field, V0.8 투사체·파티클·충격파 객체 풀(원거리 종족은 그때 결정), V0.9 추적 카메라·미니맵·전선/밀도 표시·렌더 LOD, V1.0 모드·설정·최적화·밸런스. 각 버전 시작 때 다시 계획한다.

## 5. 아키텍처 한눈에
`World.step()` 순서: 종족 통계 갱신 → `Commander.update`(AI, 3초) → `eco.begin`(먹이 생성 + 먹이 격자) → `grid.build` → `boids.compute`(**이웃 순회 한 번**: 분리/정렬/응집 + `NeighborScan` → `combat.react` → `eco.forage` → `Commander.force` → 경계 → 지터 → `2.5 x maxForce` 제한) → `integrate` → `eco.update`(먹기·유지비·굶주림) → `combat.resolve`(피해·사망) → `eco.reproduce` → `eco.end` → 1초마다 `stats.sample`.

불변 원칙: **고정 타임스텝 1/60초**(프레임당 최대 5스텝), 시뮬레이션은 `World.rng`(`java.util.Random`)만 사용(Processing `random()`/`noise()`는 시각 효과 전용), **개체 풀 4,000개 + swap-remove**(프레임 중 `new` 금지), 가속도 계산 → 적분의 **2단계 갱신**, 시뮬레이션과 렌더링 분리(`EventLog` → `Effects`).

| 파일 | 역할 |
|---|---|
| `Config` | 상수(월드 2400x1500, `CELL`=100, `MAX_AGENTS`, 먹이, 유전자, 상태/명령/모드 코드, `SELFTEST` 플래그) |
| `Species`, `Agent` | 종족 파라미터(Boids·전투·생태) / 개체 데이터(능력치는 유전자가 덮어씀) |
| `World`, `SpatialGrid` | 시뮬레이션 본체, 풀, 스텝 / 균일 격자 카운팅 정렬 |
| `BoidsSystem`, `CombatSystem`, `Ecosystem`, `Evolution` | 이동 / 전투 AI(6상태) / 먹이·에너지·번식 / 유전자 7개·교차·돌연변이 |
| `Commander` | 종족당 1개. 명령 4종은 조향력의 한 항, 복종도 = 군집 성향 x 에너지, AI는 상성표 기반 |
| `Camera`, `Renderer`, `Effects`, `Hud`, `Stats`, `Metrics`, `GameMode` | 카메라 / 종족별 삼각형 일괄 그리기 / 파티클·후광 / HUD 오프스크린 5Hz + 그래프 / 1초 통계 / 군집 지표 / 5개 모드 |
| `SelfTest` | 자체 검증(T1~T24) |

조작: 좌클릭 이동, 우클릭 방어, Q 공격, E 후퇴, 1/2/3 지휘 종족, WASD·휠 카메라, SPACE 정지, M 모드, F 효과 수준, TAB 그래프, G 격자, T 잔상, H HUD, R/N 재시작, `, .` 배속.

## 6. 테스트 실행 (`tools/run_selftest.ps1`)
저장소 파일은 수정하지 않고 임시 복사본에 `SELFTEST=true`를 적용해 Processing CLI로 돌린다. `-Only` 값: `part1`(T1~T13) · `part2`(T15~T24 + 렌더 성능) · `evo`(T14, 약 8분) · `balance` · `duels` · `genetics` · `inv`(T4) · `perf` · `final` · `v05` · `shots`(스크린샷) · `renderprof`.
**한 번에 10분을 넘기는 실행은 도구가 끊을 수 있으니 part1/part2/evo로 나눈다.** 병렬 실행은 `-Tag`를 다르게 준다. 새 테스트는 `SelfTestFormation.pde`에 만들고 `runSelfTest()`의 `-Only` 분기에 추가한다.

## 7. 배운 함정 (다시 겪지 않도록)
- Processing 4 CLI에서 `Random`은 자동 import가 안 된다 → `java.util.Random` 전체 이름.
- `noSmooth()`는 `settings()` 안에서만 가능 — 실행 중 토글 불가.
- **`text()`가 약 0.5ms**라 HUD를 매 프레임 그리면 느리다 → 오프스크린 버퍼에 5Hz(`Hud.draw`, 전역 `g`를 잠시 바꾸는 방식). 반투명 선·도형도 느려서 배경과 미리 섞은 불투명 색을 쓴다.
- 렌더링 시간은 **`setup()`이 아니라 `draw()` 안에서** 재야 한다(첫 프레임들은 JIT 때문에 훨씬 느림). 측정은 best-of-N.
- **이 개발 PC는 배터리 모드에서 같은 코드가 2배 이상 느려진다**(1,100마리 그리기 11ms ↔ 25ms). 성능 판정은 전원 상태를 기록하고, 절대 시간 합격 기준을 쓰지 않는다(T23은 보고 전용).
- 경로에 `[3화]`처럼 대괄호가 있으면 PowerShell이 와일드카드로 해석한다 → `-LiteralPath`, 또는 Bash 사용.
- `mouseWheel`은 `processing.event.MouseEvent` 전체 이름.
- 검증이 두 번 이상 "진짜 버그"를 잡았다: AI의 0스텝 결정이 초기화 안 된 통계를 봄, 유전자로 속도 범위가 바뀐 뒤 범위 밖 초기 속도로 태어남. 새 시스템도 **같은 불변식 테스트(T4, T22e)** 를 통과시킬 것.

## 8. 작업 약속
- 답변은 한국어. 기존 구조를 갈아엎지 말고 단계적으로, 한 버전씩 독립 검증 후 다음으로.
- 기존 기능을 삭제·단순화하지 않는다. 구현하지 않은 기능을 완성으로 표시하지 않는다.
- **GitHub push, 협업자 초대, 저장소 설정 변경은 그때마다 사용자에게 확인**한다(협업자 초대는 권한 부여라 자동 승인되지 않는다).
- 이 저장소는 **Public**이다. 수업 과제라 표절 검사에 걸릴 수 있다는 점은 사용자가 알고 선택했다.
