// 개체 한 마리의 데이터. 객체는 시작할 때 MAX_AGENTS개를 미리 만들어 풀(pool)에서 재사용한다.
// 능력치는 종족 기본값으로 초기화되고(World.initStats), V0.4부터 유전자가 이 값을 바꾼다.

class Agent {
  float x, y;                       // 위치
  float vx, vy;                     // 속도 (px/s)
  float ax, ay;                     // 이번 스텝에 계산된 가속도
  float heading;                    // 그릴 때 쓰는 방향 (속도 방향을 부드럽게 따라간다)
  int species;
  int id;                           // 고유 번호 (풀 슬롯과 무관, 검증용)

  // 이 개체의 실제 능력치
  float maxHp, hp;
  float atk, def;
  float speedMax;
  float perception;
  float aggression, evasion;

  // 유전 : 유전자 값(0~1)과 그로부터 계산된 배율
  float[] gene = new float[NGENE];
  float costMul = 1;                // 능력치가 높을수록 커지는 에너지 유지비 배율
  float flockMul = 1;               // 군집 성향 (정렬/응집 가중치 배율)
  boolean alive;                    // 풀에서 활성 상태인가 (제거되면 false)
  Agent mate;                       // 이번 스텝에 찾은 번식 상대 후보 (mateId로 같은 개체인지 확인)
  int mateId;

  // 생태
  float energy, maxEnergy;
  float age;                        // 초
  int gen;                          // 세대 (초기 개체는 0)
  float repCd;                      // 재번식까지 남은 시간
  int eatIdx;                       // 이번 스텝에 먹을 먹이 (없으면 -1)
  int offspring, eaten, kills;
  Agent attacker;                   // 마지막으로 때린 개체 (처치 보상용, attackerId로 같은 개체인지 확인)
  int attackerId;

  // 전투 상태
  float power;                      // 전투력 추정 = 초당 공격 * 체력 * (1 + 방어/100)
  float cooldown;                   // 다음 공격까지 남은 시간
  float hurtTimer;                  // 최근 공격받은 뒤 남은 시간 (아군 지원 신호)
  float pendingDmg;                 // 이번 스텝에 받을 피해 (두 단계 처리용)
  int attackerSp;                   // 마지막으로 때린 종족
  int state;                        // AS_*
  float speedMul;                   // 상태에 따른 속도 배수
}
