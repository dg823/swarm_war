// 생태계 : 먹이 생성(일정한 생성량), 채집, 에너지 대사, 굶주림, 번식.
//
// 에너지 흐름 : 생성된 먹이 -> 개체가 먹으면 에너지 -> 유지비로 소모. 에너지가 0이면 체력이 줄어 사망.
// 폭증 방지 : 먹이 생성량이 고정이고 먹이 수에 상한이 있다. 번식 확률은 전체 개체 수가 많을수록 낮아진다.
// 정합성   : (생성된 먹이 + 시체 먹이) = 소비된 먹이 + 남은 먹이  가 항상 성립한다.

class FoodField {
  float[] x = new float[MAX_FOOD];
  float[] y = new float[MAX_FOOD];
  float[] v = new float[MAX_FOOD];
  boolean[] gone = new boolean[MAX_FOOD];     // 먹혀서 이번 스텝 끝에 제거될 먹이
  int count;

  int cols, rows, nCells;
  int[] cellStart, fillPos, cellOf, order;
  float nearD2;                               // nearest()의 결과 거리^2

  FoodField() {
    cols = ceil(WORLD_W / CELL);
    rows = ceil(WORLD_H / CELL);
    nCells = cols * rows;
    cellStart = new int[nCells + 1];
    fillPos = new int[nCells];
    cellOf = new int[MAX_FOOD];
    order = new int[MAX_FOOD];
  }

  int cellX(float px) {
    int c = (int) (px / CELL);
    return c < 0 ? 0 : (c >= cols ? cols - 1 : c);
  }

  int cellY(float py) {
    int c = (int) (py / CELL);
    return c < 0 ? 0 : (c >= rows ? rows - 1 : c);
  }

  boolean add(float px, float py, float val) {
    if (count >= MAX_FOOD) return false;
    x[count] = px;
    y[count] = py;
    v[count] = val;
    gone[count] = false;
    count++;
    return true;
  }

  // 먹힌 먹이를 뒤에서부터 제거 (마지막 먹이와 교체)
  void compact() {
    for (int i = count - 1; i >= 0; i--) {
      if (!gone[i]) continue;
      count--;
      x[i] = x[count];
      y[i] = y[count];
      v[i] = v[count];
      gone[i] = gone[count];
      gone[count] = false;
    }
  }

  void build() {
    java.util.Arrays.fill(cellStart, 0);
    for (int i = 0; i < count; i++) {
      int c = cellY(y[i]) * cols + cellX(x[i]);
      cellOf[i] = c;
      cellStart[c + 1]++;
    }
    for (int c = 0; c < nCells; c++) cellStart[c + 1] += cellStart[c];
    System.arraycopy(cellStart, 0, fillPos, 0, nCells);
    for (int i = 0; i < count; i++) order[fillPos[cellOf[i]]++] = i;
  }

  // 반경 r(<= CELL) 안에서 가장 가까운 (먹히지 않은) 먹이. 없으면 -1. 거리^2는 nearD2.
  int nearest(float px, float py, float r) {
    int cx = cellX(px), cy = cellY(py);
    float best = r * r;
    int bi = -1;
    for (int gy = max(0, cy - 1); gy <= min(rows - 1, cy + 1); gy++) {
      for (int gx = max(0, cx - 1); gx <= min(cols - 1, cx + 1); gx++) {
        int c = gy * cols + gx;
        for (int k = cellStart[c]; k < cellStart[c + 1]; k++) {
          int j = order[k];
          if (gone[j]) continue;
          float dx = x[j] - px, dy = y[j] - py;
          float d2 = dx * dx + dy * dy;
          if (d2 < best) {
            best = d2;
            bi = j;
          }
        }
      }
    }
    nearD2 = best;
    return bi;
  }
}

class Ecosystem {
  FoodField food = new FoodField();
  boolean enabled = true;                     // false면 먹이/대사/번식을 모두 끈다 (전투만 검증할 때)
  float foodRate = FOOD_RATE;
  float acc;                                  // 먹이 생성 누적기
  float[] hotX = {400, 1200, 2000, 700, 1700, 1200, 2100};      // 오아시스 (먹이가 많이 나는 곳)
  float[] hotY = {300, 250, 300, 750, 450, 1250, 1050};

  // 누적 통계
  long generated, consumed, corpses, skipped;
  int[] births = new int[N_SPECIES];
  int totalBirths;
  int[] starved = new int[N_SPECIES];

  float fx, fy;                               // forage()가 만든 조향력

  void reset() {
    food.count = 0;
    acc = 0;
    generated = 0;
    consumed = 0;
    corpses = 0;
    skipped = 0;
    totalBirths = 0;
    for (int s = 0; s < N_SPECIES; s++) {
      births[s] = 0;
      starved[s] = 0;
    }
  }

  int nearestHot(float px, float py) {
    int bi = 0;
    float best = 1e18;
    for (int i = 0; i < hotX.length; i++) {
      float dx = hotX[i] - px, dy = hotY[i] - py;
      float d2 = dx * dx + dy * dy;
      if (d2 < best) {
        best = d2;
        bi = i;
      }
    }
    return bi;
  }

  void spawnOne(World w) {
    if (food.count >= MAX_FOOD) {
      skipped++;
      return;
    }
    float px, py;
    if (w.rng.nextFloat() < 0.7) {
      int h = w.rng.nextInt(hotX.length);
      px = hotX[h] + (float) w.rng.nextGaussian() * 110;
      py = hotY[h] + (float) w.rng.nextGaussian() * 110;
    } else {
      px = w.rng.nextFloat() * WORLD_W;
      py = w.rng.nextFloat() * WORLD_H;
    }
    px = constrain(px, 5, WORLD_W - 5);
    py = constrain(py, 5, WORLD_H - 5);
    if (w.nObs > 0 && w.pushOut(px, py, 4)) {          // 장애물 안에는 먹이가 생기지 않는다 (난수를 더 쓰지 않고 바깥으로 옮김)
      px = w.pushX;
      py = w.pushY;
    }
    food.add(px, py, FOOD_ENERGY);
    generated++;
  }

  // 스텝 시작 : 일정한 생성량으로 먹이를 만들고, 먹이 격자를 다시 만든다
  void begin(World w) {
    if (!enabled) return;
    acc += foodRate * DT;
    while (acc >= 1) {
      acc -= 1;
      spawnOne(w);
    }
    food.build();
  }

  // 사망 개체의 일부가 먹이(시체)가 된다
  void onDeath(World w, Agent a) {
    if (!enabled) return;
    if (w.rng.nextFloat() < CORPSE_P) {
      if (food.add(a.x, a.y, FOOD_ENERGY * 0.5)) corpses++;
    }
  }

  // 이 개체의 채집 : 가까운 먹이를 먹을 후보로 정하고, 배고프면 먹이(또는 오아시스)를 향해 움직인다.
  // 전투 중(공격/도주/후퇴/지원)에는 먹이를 쫓지 않지만, 발밑의 먹이는 먹는다.
  void forage(World w, Agent me, Species s) {
    fx = 0;
    fy = 0;
    me.eatIdx = -1;
    if (!enabled || me.energy >= me.maxEnergy * 0.98) return;

    int f = food.nearest(me.x, me.y, me.perception);
    if (f >= 0) {
      float er = s.size * 0.8 + 5;
      if (food.nearD2 <= er * er) me.eatIdx = f;
    }

    if (me.state != AS_FLOCK && me.state != AS_REGROUP) return;
    if (me.energy >= s.hungerThr * me.maxEnergy) return;

    float hunger = 1 - me.energy / me.maxEnergy;
    BoidsSystem b = w.boids;
    if (f >= 0) {
      b.steer(food.x[f] - me.x, food.y[f] - me.y, me, s.maxForce);
      fx = b.outX * s.wForage * (0.5 + hunger);
      fy = b.outY * s.wForage * (0.5 + hunger);
    } else {                                  // 눈에 보이는 먹이가 없으면 가까운 오아시스 쪽으로
      int h = nearestHot(me.x, me.y);
      b.steer(hotX[h] - me.x, hotY[h] - me.y, me, s.maxForce);
      fx = b.outX * s.wForage * 0.4 * (0.5 + hunger);
      fy = b.outY * s.wForage * 0.4 * (0.5 + hunger);
    }
  }

  // 먹기(선착순), 유지비, 나이, 굶주림
  void update(World w) {
    if (!enabled) return;
    for (int i = 0; i < w.count; i++) {
      Agent a = w.pool[i];
      Species s = w.species[a.species];
      if (a.eatIdx >= 0 && !food.gone[a.eatIdx]) {
        food.gone[a.eatIdx] = true;
        a.energy = min(a.maxEnergy, a.energy + food.v[a.eatIdx]);
        a.eaten++;
        consumed++;
      }
      a.eatIdx = -1;
      a.energy -= s.metab * a.costMul * DT;           // 능력치가 높을수록 유지비가 크다
      a.age += DT;
      if (a.energy <= 0) {
        a.energy = 0;
        a.hp -= STARVE_DPS * DT;
      }
    }
  }

  // 번식 : 에너지가 충분하고, 나이가 찼고, 전투 중이 아닌 개체가 자식을 낳는다 (이번 스텝 이전에 있던 개체만).
  void reproduce(World w) {
    if (!enabled) return;
    int n0 = w.count;
    for (int i = 0; i < n0; i++) {
      Agent p = w.pool[i];
      Species s = w.species[p.species];
      if (p.repCd > 0) p.repCd -= DT;
      if (p.energy < s.reproThr * p.maxEnergy || p.age < s.minAge || p.repCd > 0) continue;
      if (p.state != AS_FLOCK && p.state != AS_REGROUP) continue;
      if (w.count >= MAX_AGENTS) break;
      float room = 1.0 - w.count / (float) POP_SOFT_CAP;
      if (room <= 0 || w.rng.nextFloat() > room) continue;

      Agent c = w.spawn(p.species, p.x + (w.rng.nextFloat() - 0.5) * 16, p.y + (w.rng.nextFloat() - 0.5) * 16);
      if (c == null) break;

      // 짝이 아직 살아 있고 조건이 맞으면 교차, 아니면 복제 + 돌연변이
      Agent m = p.mate;
      boolean sexual = m != null && m != p && m.alive && m.id == p.mateId && m.species == p.species
        && m.energy >= s.reproThr * m.maxEnergy * 0.8;
      w.evo.breed(w, c, p, sexual ? m : null);
      float csp = sqrt(c.vx * c.vx + c.vy * c.vy);               // 물려받은 유전자로 속도 범위가 바뀌었으니 초기 속도를 맞춘다
      float clo = 0.4 * c.speedMax;
      if (csp > c.speedMax) {
        c.vx *= c.speedMax / csp;
        c.vy *= c.speedMax / csp;
      } else if (csp < clo && csp > 1e-6) {
        c.vx *= clo / csp;
        c.vy *= clo / csp;
      }
      c.energy = s.childEnergy;
      p.energy -= s.reproCost;
      p.repCd = s.repCd;
      p.offspring++;
      if (sexual) {
        m.offspring++;
        m.repCd = max(m.repCd, s.repCd * 0.5);
      }
      births[p.species]++;
      totalBirths++;
      w.events.add(EV_BIRTH, c.x, c.y, p.species);
    }
  }

  void end() {
    food.compact();
  }
}
