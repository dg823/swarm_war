// 시뮬레이션 세계 : 시드 RNG, 개체 풀, 격자, 고정 타임스텝.
// 시뮬레이션 안에서는 이 클래스의 rng만 사용한다 (Processing random()/noise() 금지) -> 같은 시드면 같은 결과.

class World {
  long seed;
  java.util.Random rng;
  Agent[] pool = new Agent[MAX_AGENTS];
  int count;
  int nextId;
  Species[] species;
  SpatialGrid grid;
  BoidsSystem boids;
  CombatSystem combat;
  Ecosystem eco;
  Evolution evo;
  Commander[] cmd = new Commander[N_SPECIES];
  int playerSpecies = -1;           // 플레이어가 지휘하는 종족 (-1이면 모두 AI)
  Stats stats = new Stats();
  EventLog events = new EventLog(); // 타격/사망/번식 기록 (시각 효과가 읽어 간다. 시뮬레이션 결과에는 영향 없음)

  float acc;                        // 고정 스텝 시간 누적기
  long stepCount;
  float stepMs;                     // 최근 스텝 시간 (지수 이동 평균)
  long nsGrid, nsBoids, nsInt, nsCombat, nsEco;   // 성능 분석용 누적 시간
  float[] powerSum = new float[N_SPECIES];        // 종족별 전투력 합 (이전 스텝 기준)
  float[] meanEnergy = new float[N_SPECIES];      // 종족별 평균 에너지 비율 (0~1)
  float[] avgGen = new float[N_SPECIES];          // 종족별 평균/최대 세대
  int[] maxGen = new int[N_SPECIES];
  float[][] geneMean = new float[N_SPECIES][NGENE];   // 종족별 현재 개체들의 평균 유전자
  int[] pop = new int[N_SPECIES];

  // 종족별 통계 (전투)
  int[] kills = new int[N_SPECIES];
  int[] deaths = new int[N_SPECIES];
  int totalDeaths;
  int combatAgents;                 // 이번 스텝에 적을 감지한 개체 수
  float damageDealt;                // 누적 피해량 (검증용)
  float[] cx = new float[N_SPECIES];     // 종족별 무게중심
  float[] cy = new float[N_SPECIES];

  float[] homeX = {700, 1700, 1700};     // 종족별 초기 거점
  float[] homeY = {750, 450, 1050};

  World(long seed) {
    for (int i = 0; i < MAX_AGENTS; i++) pool[i] = new Agent();
    species = makeSpecies();
    for (Species s : species) {
      if (s.perception > CELL) throw new RuntimeException("감지 반경이 CELL보다 큽니다: " + s.name);
    }
    grid = new SpatialGrid(WORLD_W, WORLD_H, CELL, MAX_AGENTS);
    boids = new BoidsSystem();
    combat = new CombatSystem();
    eco = new Ecosystem();
    evo = new Evolution();
    for (int s = 0; s < N_SPECIES; s++) cmd[s] = new Commander(s);
    reset(seed);
  }

  // 플레이어가 지휘할 종족을 바꾼다. 나머지 종족은 자체 AI가 지휘한다.
  void setPlayer(int s) {
    playerSpecies = s;
    for (int i = 0; i < N_SPECIES; i++) {
      boolean p = i == s;
      if (p && !cmd[i].isPlayer) cmd[i].order = ORD_NONE;     // 새로 지휘를 맡으면 일단 자율 행동
      cmd[i].isPlayer = p;
    }
  }

  void reset(long seed) {
    this.seed = seed;
    rng = new java.util.Random(seed);
    clear();
    acc = 0;
    stepCount = 0;
    nextId = 0;
    stepMs = 0;
    for (int s = 0; s < N_SPECIES; s++) {
      kills[s] = 0;
      deaths[s] = 0;
    }
    totalDeaths = 0;
    combatAgents = 0;
    damageDealt = 0;
    eco.reset();
    evo.reset();
    stats.reset();
    for (int s = 0; s < N_SPECIES; s++) cmd[s].reset(homeX[s], homeY[s]);
    for (int s = 0; s < N_SPECIES; s++) spawnCluster(s, INITIAL_PER_SPECIES, homeX[s], homeY[s], 230);
    for (int i = 0; i < count; i++) pool[i].age = rng.nextFloat() * 30;     // 번식 시점이 한꺼번에 몰리지 않게
    countSpecies();
  }

  void clear() {
    for (int i = 0; i < count; i++) pool[i].alive = false;
    count = 0;
  }

  // ---------- 생성과 제거 ----------

  // 종족 기본 능력치로 초기화 (V0.4부터 유전자가 이 값을 바꾼다)
  void initStats(Agent a) {
    Species s = species[a.species];
    a.maxHp = s.hp;
    a.hp = s.hp;
    a.atk = s.attack;
    a.def = s.defense;
    a.speedMax = s.maxSpeed;
    a.perception = s.perception;
    a.aggression = s.aggression;
    a.evasion = s.evasion;
    a.power = 0;
    a.cooldown = 0;
    a.hurtTimer = 0;
    a.pendingDmg = 0;
    a.attackerSp = -1;
    a.state = AS_FLOCK;
    a.speedMul = 1;
    a.maxEnergy = 100;
    a.energy = a.maxEnergy * (0.55 + 0.4 * rng.nextFloat());
    a.age = 0;
    a.gen = 0;
    a.repCd = 0;
    a.eatIdx = -1;
    a.offspring = 0;
    a.eaten = 0;
    a.kills = 0;
    a.attacker = null;
    a.attackerId = -1;
  }

  Agent spawn(int s, float x, float y) {
    if (count >= MAX_AGENTS) return null;
    Agent a = pool[count++];
    Species sp = species[s];
    a.id = nextId++;
    a.species = s;
    a.x = constrain(x, 0, WORLD_W - 0.01);
    a.y = constrain(y, 0, WORLD_H - 0.01);
    float ang = rng.nextFloat() * TWO_PI;
    float spd = sp.maxSpeed * (0.5 + 0.5 * rng.nextFloat());
    a.vx = cos(ang) * spd;
    a.vy = sin(ang) * spd;
    a.heading = ang;
    a.ax = 0;
    a.ay = 0;
    initStats(a);
    a.alive = true;
    a.mate = null;
    a.mateId = -1;
    evo.initGenes(this, a);                        // 유전자와 그에 따른 능력치 (initStats의 기본값을 덮어쓴다)
    return a;
  }

  void spawnCluster(int s, int n, float cx, float cy, float radius) {
    for (int i = 0; i < n; i++) {
      float r = radius * sqrt(rng.nextFloat());
      float th = rng.nextFloat() * TWO_PI;
      if (spawn(s, cx + cos(th) * r, cy + sin(th) * r) == null) return;
    }
  }

  // 마지막 개체와 자리를 바꿔 제거 (풀 객체는 그대로 재사용)
  void removeAt(int i) {
    Agent t = pool[i];
    t.alive = false;
    pool[i] = pool[count - 1];
    pool[count - 1] = t;
    count--;
  }

  // 사망 기록 (removeAt 직전에 호출)
  void onDeath(Agent a) {
    events.add(EV_DEATH, a.x, a.y, a.species);
    deaths[a.species]++;
    totalDeaths++;
    if (a.attackerSp >= 0) {
      kills[a.attackerSp]++;
      Agent k = a.attacker;                        // 처치한 개체는 에너지를 얻는다 (포식)
      if (eco.enabled && k != null && k.id == a.attackerId) {
        k.kills++;
        k.energy = min(k.maxEnergy, k.energy + species[k.species].killEnergy);
      }
    } else {
      eco.starved[a.species]++;
    }
    evo.onDeath(a);
    eco.onDeath(this, a);
  }

  void countSpecies() {
    for (int s = 0; s < N_SPECIES; s++) pop[s] = 0;
    for (int i = 0; i < count; i++) pop[pool[i].species]++;
  }

  // 종족별 개체 수와 무게중심 (매 스텝 계산 전에 갱신)
  void refreshSpeciesStats() {
    for (int s = 0; s < N_SPECIES; s++) {
      pop[s] = 0;
      cx[s] = 0;
      cy[s] = 0;
      avgGen[s] = 0;
      maxGen[s] = 0;
      powerSum[s] = 0;
      meanEnergy[s] = 0;
      for (int g = 0; g < NGENE; g++) geneMean[s][g] = 0;
    }
    for (int i = 0; i < count; i++) {
      Agent a = pool[i];
      pop[a.species]++;
      powerSum[a.species] += a.power;
      meanEnergy[a.species] += a.energy / a.maxEnergy;
      cx[a.species] += a.x;
      cy[a.species] += a.y;
      avgGen[a.species] += a.gen;
      if (a.gen > maxGen[a.species]) maxGen[a.species] = a.gen;
      for (int g = 0; g < NGENE; g++) geneMean[a.species][g] += a.gene[g];
    }
    for (int s = 0; s < N_SPECIES; s++) {
      if (pop[s] > 0) {
        cx[s] /= pop[s];
        cy[s] /= pop[s];
        avgGen[s] /= pop[s];
        meanEnergy[s] /= pop[s];
        for (int g = 0; g < NGENE; g++) geneMean[s][g] /= pop[s];
      } else {
        cx[s] = homeX[s];
        cy[s] = homeY[s];
      }
    }
  }

  // 종족의 개체 수를 target으로 맞춘다. 늘릴 때는 그 종족 무리 근처에서 태어난다.
  int setPopulation(int s, int target) {
    target = max(0, target);
    countSpecies();
    int cur = pop[s];
    if (target > cur) {
      float px = homeX[s], py = homeY[s];
      if (cur > 0) {
        px = 0;
        py = 0;
        for (int i = 0; i < count; i++) {
          if (pool[i].species == s) {
            px += pool[i].x;
            py += pool[i].y;
          }
        }
        px /= cur;
        py /= cur;
      }
      for (int i = cur; i < target; i++) {
        float r = 80 * sqrt(rng.nextFloat());
        float th = rng.nextFloat() * TWO_PI;
        if (spawn(s, px + cos(th) * r, py + sin(th) * r) == null) break;
      }
    } else if (target < cur) {
      int toRemove = cur - target;
      for (int i = count - 1; i >= 0 && toRemove > 0; i--) {
        if (pool[i].species == s) {
          removeAt(i);
          toRemove--;
        }
      }
    }
    countSpecies();
    return pop[s];
  }

  // ---------- 시간 진행 ----------

  void step() {
    long t0 = System.nanoTime();
    for (int s = 0; s < N_SPECIES; s++) cmd[s].update(this);     // 자체 AI 지휘관의 명령 갱신
    eco.begin(this);                // 먹이 생성(일정한 양) + 먹이 격자
    grid.build(pool, count);
    long t1 = System.nanoTime();
    boids.compute(this);            // Boids + 전투 + 채집 (이웃 순회 한 번)
    long t2 = System.nanoTime();
    boids.integrate(this);
    long t3 = System.nanoTime();
    eco.update(this);               // 먹기, 유지비, 굶주림
    combat.resolve(this);           // 피해 적용, 사망 (시체는 먹이가 된다)
    eco.reproduce(this);            // 번식
    eco.end();                      // 먹힌 먹이 정리
    long t4 = System.nanoTime();
    stepCount++;
    if (stepCount % 60 == 0) stats.sample(this);                 // 1초마다 그래프용 통계 기록
    nsGrid += t1 - t0;
    nsBoids += t2 - t1;
    nsInt += t3 - t2;
    nsCombat += t4 - t3;
    stepMs = stepMs * 0.95 + ((t4 - t0) / 1000000.0f) * 0.05;
  }

  // 프레임 시간을 누적해 고정 스텝을 필요한 만큼 실행. 실행한 스텝 수를 돌려준다.
  int update(float frameDt, float timeScale) {
    acc += constrain(frameDt, 0, 0.1) * max(0, timeScale);     // 비정상적인 시간 값(음수, 아주 큰 값)에도 안전하게
    int n = 0;
    while (acc >= DT && n < MAX_STEPS_PER_FRAME) {
      step();
      acc -= DT;
      n++;
    }
    if (acc >= DT) acc = 0;         // 따라잡지 못하면 밀린 시간은 버린다
    return n;
  }
}
