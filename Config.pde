// 전역 상수 모음. 시뮬레이션 단위는 월드 픽셀(px)과 초(s).

final float WORLD_W = 2400;
final float WORLD_H = 1500;

final float DT = 1.0 / 60.0;            // 고정 타임스텝 (초)
final int MAX_STEPS_PER_FRAME = 5;      // 한 프레임에 따라잡을 최대 스텝 수 (배속 4까지 여유)

final int N_SPECIES = 3;
final int MAX_AGENTS = 4000;
final int INITIAL_PER_SPECIES = 400;

final float CELL = 100;                 // 격자 셀 크기. 모든 개체의 감지 반경(과 지원 반경) 이상이어야 한다.
final int NEIGHBOR_CAP = 48;            // 정렬/응집에 반영하는 같은 종족 이웃 수 상한 (최악 성능 보호)

// 생태계
final int MAX_FOOD = 2500;              // 먹이 상한. 소비가 생성을 못 따라가도 무한히 쌓이지 않는다.
final float FOOD_RATE = 45;             // 초당 먹이 생성량 (기본값, 게임 중 조절 가능)
final float FOOD_ENERGY = 30;           // 먹이 하나의 에너지
final float CORPSE_P = 0.5;             // 사망 개체가 먹이(에너지 절반)가 될 확률
final float STARVE_DPS = 8;             // 에너지가 0일 때 초당 체력 감소
final int POP_SOFT_CAP = 2600;          // 전체 개체 수가 이에 가까울수록 번식 확률이 낮아진다

// 유전자 (값은 0~1, 0.5가 종족 기본값 = 배율 1.0, 범위 0.6~1.4)
final int NGENE = 7;
final int GN_SPEED = 0, GN_ATK = 1, GN_DEF = 2, GN_PERC = 3, GN_AGGR = 4, GN_FLOCK = 5, GN_EVADE = 6;
final float MUT_RATE = 0.15;            // 유전자 하나가 돌연변이를 일으킬 확률
final float MUT_SIGMA = 0.08;           // 돌연변이 크기 (정규분포 표준편차)
final float INIT_GENE_SIGMA = 0.15;     // 초기 개체의 유전자 변이 (변이가 있어야 선택이 일어난다)
final int MAX_GEN_TRACK = 120;          // 세대별 통계를 기록하는 최대 세대

// 지휘 명령
final int ORD_NONE = 0, ORD_MOVE = 1, ORD_DEFEND = 2, ORD_ATTACK = 3, ORD_RETREAT = 4;

// 개체 행동 상태
final int AS_FLOCK = 0, AS_ATTACK = 1, AS_FLEE = 2, AS_SUPPORT = 3, AS_RETREAT = 4, AS_REGROUP = 5;

final long DEFAULT_SEED = 20261103L;
final boolean SELFTEST = false;         // true면 setup에서 자동 검증을 돌리고 스크린샷을 저장한 뒤 종료
final String SELFTEST_ONLY = "";        // 비어 있지 않으면 해당 검증만 실행 (balance, duels 등. 파라미터 튜닝용)
