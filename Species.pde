// 종족 파라미터. 가중치만 달라도 서로 다른 군집 형태와 전투 양상이 나온다.
// (자원/에너지는 V0.3, 유전자 보정은 V0.4에서 추가)

class Species {
  int id;
  String name;
  color col;
  float size;                       // 그리는 크기 (월드 px)
  float perception;                 // 감지 반경
  float sepFrac = 0.45;             // 같은 종족 분리 반경 = perception * sepFrac
  float maxSpeed, maxForce;         // px/s, px/s^2
  float wSep, wAli, wCoh;           // Boids 3규칙 가중치
  float wSepOther;                  // 다른 종족과 겹치지 않으려는 정도
  float wBound = 2.0;               // 경계 회피
  float jitter;                     // 개체 간 동기화를 깨는 미세한 무작위 힘

  // 전투 능력
  float hp, attack, defense;
  float attackCd;                   // 공격 간격 (초)
  float attackRange;                // 공격 사거리 (px)
  float aggression;                 // 공격 성향 : 클수록 불리해도 싸운다
  float evasion;                    // 회피 성향 : 클수록 도주 힘이 강하다
  float retreatHp;                  // 체력 비율이 이보다 낮으면 후퇴

  // 상태별 조향 가중치와 속도 배수
  float wSeek, wFlee, wSupport, wRegroup;
  float chaseMul, fleeMul;
  float regen = 1.0;                // 전투 밖 체력 회복 (hp/초)

  // 생태 (에너지 100이 가득 찬 상태)
  float metab;                      // 초당 에너지 유지비
  float hungerThr;                  // 에너지 비율이 이보다 낮으면 먹이를 찾아 나선다
  float wForage;                    // 먹이 추적 가중치
  float reproThr;                   // 에너지 비율이 이 이상이면 번식 가능
  float reproCost, childEnergy;     // 번식 비용과 자식의 초기 에너지
  float minAge;                     // 번식 가능 나이 (초)
  float repCd;                      // 번식 후 재번식까지 (초)
  float killEnergy;                 // 적을 처치했을 때 얻는 에너지 (포식)

  Species(int id, String name, color col, float size, float perception, float maxSpeed, float maxForce,
          float wSep, float wAli, float wCoh, float wSepOther) {
    this.id = id;
    this.name = name;
    this.col = col;
    this.size = size;
    this.perception = perception;
    this.maxSpeed = maxSpeed;
    this.maxForce = maxForce;
    this.wSep = wSep;
    this.wAli = wAli;
    this.wCoh = wCoh;
    this.wSepOther = wSepOther;
    this.jitter = 0.15 * maxForce;
    this.attackRange = size * 1.7;
  }

  Species combat(float hp, float attack, float defense, float attackCd, float aggression, float evasion, float retreatHp) {
    this.hp = hp;
    this.attack = attack;
    this.defense = defense;
    this.attackCd = attackCd;
    this.aggression = aggression;
    this.evasion = evasion;
    this.retreatHp = retreatHp;
    return this;
  }

  Species tactics(float wSeek, float wFlee, float wSupport, float wRegroup, float chaseMul, float fleeMul) {
    this.wSeek = wSeek;
    this.wFlee = wFlee;
    this.wSupport = wSupport;
    this.wRegroup = wRegroup;
    this.chaseMul = chaseMul;
    this.fleeMul = fleeMul;
    return this;
  }

  Species ecology(float metab, float hungerThr, float wForage, float reproThr, float reproCost,
                  float childEnergy, float minAge, float repCd, float killEnergy) {
    this.killEnergy = killEnergy;
    this.metab = metab;
    this.hungerThr = hungerThr;
    this.wForage = wForage;
    this.reproThr = reproThr;
    this.reproCost = reproCost;
    this.childEnergy = childEnergy;
    this.minAge = minAge;
    this.repCd = repCd;
    return this;
  }

  float sepRadius() { return perception * sepFrac; }
  float otherSepRadius() { return min(sepRadius(), size * 1.2); }
}

// 0 RED 포식자 : 빠르고 공격적. 느슨한 추격 대형
// 1 BLUE 수호자 : 느리고 단단하다. 조밀한 대형과 아군 지원
// 2 GREEN 생존자 : 작고 약하지만 민첩하다. 위험하면 빠르게 도주
Species[] makeSpecies() {
  Species[] s = new Species[N_SPECIES];
  s[0] = new Species(0, "RED",   color(255, 70, 70),  12, 70, 150, 300, 1.6, 0.8, 0.5,  1.2)
    .combat(60, 14, 4, 0.5, 1.6, 0.4, 0.25)
    .tactics(2.2, 1.2, 0.6, 1.0, 1.15, 1.0)
    .ecology(1.8, 0.70, 1.0, 0.80, 45, 35, 12, 6, 30);
  s[1] = new Species(1, "BLUE",  color(80, 140, 255), 14, 60,  95, 220, 1.4, 1.6, 1.5,  1.2)
    .combat(110, 8, 14, 0.7, 1.0, 0.8, 0.20)
    .tactics(1.3, 1.3, 2.0, 1.6, 1.0, 1.0)
    .ecology(1.2, 0.80, 1.8, 0.75, 40, 35, 10, 6, 10);
  s[2] = new Species(2, "GREEN", color(90, 230, 120), 10, 50, 125, 380, 2.4, 0.7, 0.35, 1.5)
    .combat(40, 4, 2, 0.8, 0.5, 1.6, 0.50)
    .tactics(0.9, 3.0, 0.4, 1.0, 1.0, 1.35)
    .ecology(1.1, 0.90, 2.5, 0.70, 28, 28, 8, 5, 5);
  return s;
}
