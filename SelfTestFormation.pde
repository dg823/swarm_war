// V0.6 진형 검증 (F1~F6, P). SelfTest.pde의 runSelfTest()에서 -Only form 으로, 또는 전체 실행에서 호출된다.
//   F1 슬롯 기하   F2 분대 배정   F3 이동하며 진형 형성   F4 교전 붕괴와 재정비   F5 장애물   F6 호환성   P 성능

boolean testFormation() {
  boolean ok = true;
  ok &= testSlotGeometry();
  ok &= testSquadAssign();
  ok &= testFormMove();
  ok &= testFormEngage();
  ok &= testObstacles();
  ok &= testFormCompat();
  ok &= testFormPerf();
  println(ok ? "=== FORMATION PASS ===" : "=== FORMATION FAILED ===");
  return ok;
}

// ---------- 공용 측정 ----------

float fqError;                        // 평균 슬롯 오차 (px)
float fqAspect;                       // 분대 좌표계에서 좌우 퍼짐 / 앞뒤 퍼짐 (표준편차 비)

// 종족 sp의 진형 품질 : 슬롯에서 슬롯 간격 하나 이내에 있는 비율. fqError, fqAspect도 채운다.
float formQuality(World w, int sp) {
  int n = 0, near = 0;
  float err = 0;
  double su = 0, su2 = 0, sv = 0, sv2 = 0;
  for (int i = 0; i < w.count; i++) {
    Agent a = w.pool[i];
    if (a.species != sp) continue;
    Squad q = w.squads.of(a);
    if (q == null || q.form == FM_NONE) continue;
    float wx = q.cx + q.dirX * a.slotU - q.dirY * a.slotV;
    float wy = q.cy + q.dirY * a.slotU + q.dirX * a.slotV;
    float e = dist(a.x, a.y, wx, wy);
    err += e;
    if (e <= (q.form == FM_SCATTER ? q.gap * 2.2 : q.gap)) near++;     // 허용 오차 = 슬롯 간격 하나 (산개는 간격이 2.2배)
    float rx = a.x - q.cx, ry = a.y - q.cy;
    float u = rx * q.dirX + ry * q.dirY, v = -rx * q.dirY + ry * q.dirX;
    su += u;
    su2 += u * u;
    sv += v;
    sv2 += v * v;
    n++;
  }
  if (n == 0) {
    fqError = -1;
    fqAspect = 0;
    return 0;
  }
  fqError = err / n;
  double vu = su2 / n - (su / n) * (su / n), vv = sv2 / n - (sv / n) * (sv / n);
  fqAspect = (float) Math.sqrt(Math.max(vv, 1e-6) / Math.max(vu, 1e-6));
  return near / (float) n;
}

// 같은 종족 최근접 이웃 거리 평균 (Boids 분리가 살아 있는지)
float meanNN(World w, int sp) {
  float sum = 0;
  int n = 0;
  for (int i = 0; i < w.count; i++) {
    Agent a = w.pool[i];
    if (a.species != sp) continue;
    float best = 1e9;
    for (int j = 0; j < w.count; j++) {
      if (j == i || w.pool[j].species != sp) continue;
      best = min(best, dist(a.x, a.y, w.pool[j].x, w.pool[j].y));
    }
    if (best < 1e9) {
      sum += best;
      n++;
    }
  }
  return n > 0 ? sum / n : 0;
}

// ---------- F1 : 슬롯 기하 ----------

boolean testSlotGeometry() {
  boolean pass = true;
  String detail = "";
  int[] ns = {20, 60, 120};
  float gap = 30;
  for (int f = FM_LINE; f <= FM_SCATTER; f++) {
    String fd = formName(f) + ":";
    for (int n : ns) {
      float[] u = new float[n], v = new float[n];
      float mu = 0, mv = 0;
      for (int k = 0; k < n; k++) {
        slotLocal(f, k, n, gap);
        u[k] = fmU;
        v[k] = fmV;
        mu += fmU;
        mv += fmV;
      }
      mu /= n;
      mv /= n;
      float minD = 1e9;
      for (int a = 0; a < n; a++) for (int b = a + 1; b < n; b++) minD = min(minD, dist(u[a], v[a], u[b], v[b]));
      float uMin = 1e9, uMax = -1e9, vMin = 1e9, vMax = -1e9;
      for (int k = 0; k < n; k++) {
        uMin = min(uMin, u[k]);
        uMax = max(uMax, u[k]);
        vMin = min(vMin, v[k]);
        vMax = max(vMax, v[k]);
      }
      float depth = uMax - uMin, width = vMax - vMin;
      boolean spacing = minD >= gap * (f == FM_CIRCLE ? 0.75 : 0.95);   // 원형의 안쪽 고리는 둘레 간격이 조금 좁다
      boolean shape = true;
      if (f == FM_LINE && n >= 60) shape = width > depth * 2;
      if (f == FM_COLUMN && n >= 60) shape = depth > width * 2;
      if (f == FM_WEDGE) {                                      // 꼭짓점 하나가 맨 앞, 뒤로 갈수록 넓어진다
        int front = 0;
        for (int k = 0; k < n; k++) if (u[k] > uMax - 0.01) front++;
        shape = front == 1 && width >= depth * 1.5;
      }
      if (f == FM_CIRCLE) {                                     // 바깥 고리가 꽉 차고, 대칭이라 평균이 중심 근처
        float rMax = 0;
        for (int k = 0; k < n; k++) rMax = max(rMax, sqrt(u[k] * u[k] + v[k] * v[k]));
        int outer = 0;
        for (int k = 0; k < n; k++) if (sqrt(u[k] * u[k] + v[k] * v[k]) > rMax - 0.5) outer++;
        int R = round(rMax / gap);
        shape = outer == min(ringCap(R), n) && abs(mu) < gap * 0.3 && abs(mv) < gap * 0.3;
      }
      if (f == FM_SCATTER) spacing = minD >= gap * 1.2;          // 산개는 간격이 넓다
      boolean ok = spacing && shape;
      pass &= ok;
      fd += " n" + n + (ok ? "O" : "X") + "(최소간격 " + nf(minD / gap, 1, 2) + "g, 폭/깊이 " + nf(width / max(1, depth), 1, 1) + ")";
    }
    detail += fd + "  ";
  }
  report("F1 슬롯 기하 (5종 x n=20/60/120)", pass, detail);
  return pass;
}

// ---------- F2 : 분대 배정 ----------

boolean testSquadAssign() {
  World w = orderWorld(0);
  w.spawnCluster(0, 400, 1200, 750, 300);
  w.cmd[0].formSet = FM_LINE;
  for (int i = 0; i < 60; i++) w.step();
  w.countSpecies();
  int K = w.squads.k[0];
  boolean allIn = true;
  int sum = 0, minN = 9999, maxN = 0;
  for (int i = 0; i < w.count; i++) {
    Agent a = w.pool[i];
    if (a.species != 0) continue;
    Squad q = w.squads.of(a);
    if (q == null || a.squad >= K) allIn = false;
  }
  for (int j = 0; j < K; j++) {
    int n = w.squads.sq[j].n;
    sum += n;
    minN = min(minN, n);
    maxN = max(maxN, n);
  }
  boolean countOk = K == 6 && sum == 400;
  boolean balanced = minN >= 20 && maxN <= 140;

  // 분대에 속한 개체는 다른 분대 중심보다 자기 분대 중심에 대체로 가깝다 (공간적으로 뭉친 분대)
  int closer = 0, tot = 0;
  for (int i = 0; i < w.count; i++) {
    Agent a = w.pool[i];
    Squad q = w.squads.of(a);
    if (q == null) continue;
    float dOwn = dist(a.x, a.y, q.cx, q.cy), dBest = 1e9;
    for (int j = 0; j < K; j++) dBest = min(dBest, dist(a.x, a.y, w.squads.sq[j].cx, w.squads.sq[j].cy));
    if (dOwn <= dBest * 1.3 + 40) closer++;
    tot++;
  }
  boolean coherent = closer >= tot * 0.95;

  // 재현성 : 같은 시드면 분대 배정도 같다
  long[] cs = new long[2];
  for (int r = 0; r < 2; r++) {
    World x = orderWorld(0, 11);
    x.spawnCluster(0, 300, 900, 750, 250);
    x.spawnCluster(1, 200, 1600, 750, 200);
    x.cmd[0].formSet = FM_LINE;
    x.cmd[0].moveTo(1500, 750);
    for (int i = 0; i < 600; i++) x.step();
    long h = checksum(x);
    for (int i = 0; i < x.count; i++) h = 31 * h + x.pool[i].squad;
    cs[r] = h;
  }
  boolean det = cs[0] == cs[1];

  // 난수 소비 불변 : 진형을 켜도 RNG 사용량이 같다 (먹이/번식/적 없이 지터만 쓰는 조건)
  long[] rn = new long[2];
  for (int r = 0; r < 2; r++) {
    World x = orderWorld(0, 12);
    x.spawnCluster(0, 200, 900, 750, 200);
    x.cmd[0].formSet = r == 0 ? FM_NONE : FM_LINE;
    for (int i = 0; i < 300; i++) x.step();
    rn[r] = x.rng.nextLong();
  }
  boolean rngSame = rn[0] == rn[1];

  boolean pass = countOk && allIn && balanced && coherent && det && rngSame;
  report("F2 분대 배정", pass, "RED 400 -> 분대 " + K + "개 (기대 6), 합 " + sum + ", 크기 " + minN + "~" + maxN
    + ", 전원 배정 " + (allIn ? "O" : "X") + ", 공간 응집 " + closer + "/" + tot
    + ", 재현성 " + (det ? "O" : "X") + ", 난수 소비 불변 " + (rngSame ? "O" : "X"));
  return pass;
}

// ---------- F3 : 이동하며 진형 형성 ----------

boolean testFormMove() {
  boolean pass = true;
  String detail = "";
  int[] forms = {FM_LINE, FM_WEDGE, FM_CIRCLE, FM_COLUMN, FM_SCATTER};
  for (int f : forms) {
    World w = orderWorld(0, 21);
    w.spawnCluster(0, 70, 350, 750, 90);
    w.cmd[0].formSet = f;
    w.cmd[0].moveTo(2100, 750);
    float sepR = w.species[0].sepRadius();
    float qMove = 0, aspMove = 0, errMove = 0;
    for (int i = 1; i <= 420; i++) {                           // 7초 : 아직 이동 중
      w.step();
    }
    qMove = formQuality(w, 0);
    aspMove = fqAspect;
    errMove = fqError;
    float nn = meanNN(w, 0);
    float cx = w.cx[0];
    boolean moving = cx > 900;                                 // 대열을 짜면서도 목표 쪽으로 나아간다
    boolean shape = true;
    if (f == FM_LINE) shape = aspMove >= 2.0;
    if (f == FM_COLUMN) shape = aspMove <= 0.5;
    if (f == FM_WEDGE) shape = aspMove >= 1.0;
    boolean boids = nn >= sepR * 0.6;                          // 슬롯이 분리 규칙을 이기지 않는다 (겹쳐 쌓이지 않음)
    boolean ok = qMove >= 0.6 && shape && moving && boids;
    pass &= ok;
    detail += formName(f) + (ok ? "O" : "X") + "(슬롯 이내 " + round(qMove * 100) + "%, 오차 " + nf(errMove, 1, 1) + "px, 좌우/앞뒤 " + nf(aspMove, 1, 2)
      + ", NN " + nf(nn / sepR, 1, 2) + "sep, x " + round(cx) + ")  ";
  }
  report("F3 이동하며 진형 형성 (RED 70, 7초)", pass, detail);
  return pass;
}

// ---------- F4 : 교전 붕괴와 재정비 ----------

boolean testFormEngage() {
  World w = orderWorld(0, 31);
  w.spawnCluster(0, 70, 250, 750, 80);
  w.cmd[0].formSet = FM_LINE;
  w.cmd[0].moveTo(2250, 750);
  for (int i = 0; i < 240; i++) w.step();                    // 4초 : 진형을 짠다
  float q0 = formQuality(w, 0);

  w.refreshSpeciesStats();
  w.spawnCluster(2, 30, w.cx[0] + 220, w.cy[0], 50);          // 앞에 GREEN 무리
  float qMin = q0, engMax = 0;
  int t = 0;
  for (; t < 300; t++) {                                      // 최대 5초 교전
    w.step();
    float qq = formQuality(w, 0);
    qMin = min(qMin, qq);
    for (int j = 0; j < w.squads.k[0]; j++) engMax = max(engMax, w.squads.sq[j].engaged);
    if (t > 90 && engMax > 0.3) break;
  }
  w.setPopulation(2, 0);                                      // 적을 치운다
  int rec = -1;
  float qEnd = 0;
  for (int i = 1; i <= 480; i++) {                            // 8초 안에 80% 회복
    w.step();
    qEnd = formQuality(w, 0);
    if (rec < 0 && qEnd >= q0 * 0.8) rec = i;
  }
  boolean collapsed = qMin <= q0 * 0.6 && engMax > 0.15;
  boolean recovered = rec > 0;
  boolean pass = collapsed && recovered;
  report("F4 교전 붕괴와 재정비", pass, "교전 전 슬롯 이내 " + round(q0 * 100) + "% -> 교전 중 최저 " + round(qMin * 100) + "% (교전 비율 최대 " + round(engMax * 100) + "%)"
    + " -> 적 제거 후 " + (recovered ? nf(rec / 60.0, 1, 1) + "초에 80% 회복" : "8초 안에 회복 못 함") + ", 8초 뒤 " + round(qEnd * 100) + "%");
  return pass;
}

// ---------- F5 : 장애물 ----------

boolean testObstacles() {
  World w = orderWorld(0, 41);
  w.addObstacle(1200, 750, 120);
  w.spawnCluster(0, 70, 550, 750, 80);
  w.cmd[0].formSet = FM_AUTO;
  w.cmd[0].moveTo(1850, 750);                                // AUTO -> 이동 = 종대
  int insideMax = 0;
  for (int i = 0; i < 1500; i++) {                           // 25초
    w.step();
    int inside = 0;
    for (int k = 0; k < w.count; k++) if (w.insideObstacle(w.pool[k].x, w.pool[k].y)) inside++;
    insideMax = max(insideMax, inside);
  }
  int arrived = 0, n = 0;
  for (int k = 0; k < w.count; k++) {
    Agent a = w.pool[k];
    if (a.species != 0) continue;
    n++;
    if (dist(a.x, a.y, 1850, 750) < 200) arrived++;
  }

  // 먹이는 장애물 안에 생기지 않는다 (기본 장애물 배치, 생태계 켬)
  boolean saved = worldObstacles;
  worldObstacles = true;
  World e = new World(42);
  worldObstacles = saved;
  int foodInside = 0;
  for (int i = 0; i < 900; i++) e.step();
  for (int f = 0; f < e.eco.food.count; f++) if (e.insideObstacle(e.eco.food.x[f], e.eco.food.y[f])) foodInside++;
  int agentInside = 0;
  for (int k = 0; k < e.count; k++) if (e.insideObstacle(e.pool[k].x, e.pool[k].y)) agentInside++;

  boolean pass = insideMax == 0 && arrived >= n * 0.7 && foodInside == 0 && agentInside == 0 && e.nObs == 8;
  report("F5 장애물", pass, "RED 70 종대가 반경 120 장애물 너머로 이동 : 안에 들어간 개체 최대 " + insideMax + ", 도착 " + arrived + "/" + n
    + " | 기본 배치 " + e.nObs + "개, 15초 뒤 장애물 안 먹이 " + foodInside + " / " + e.eco.food.count + ", 안의 개체 " + agentInside);
  return pass;
}

// ---------- F6 : 호환성 ----------

boolean testFormCompat() {
  // (a) 진형 NONE이면 V0.5와 같다 : AI가 명령을 내리지 않는 조건에서 분대가 생기지 않는다
  World a = orderWorld(0, 51);
  a.cmd[0].formSet = FM_AUTO;                                // AUTO + 명령 없음 = NONE
  a.spawnCluster(0, 300, 900, 750, 200);
  for (int i = 0; i < 300; i++) a.step();
  boolean noneNoSquads = a.squads.k[0] == 0;

  // (b) 장애물 + AI 진형이 들어간 기본 월드의 재현성과 불변식
  boolean saved = worldObstacles;
  worldObstacles = true;
  long[] cs = new long[2];
  int formSteps = 0, bad = 0, mismatch = 0;
  for (int r = 0; r < 2; r++) {
    World w = new World(52);
    w.setPlayer(-1);
    for (int i = 0; i < 2400; i++) {                         // 40초
      w.step();
      if (r == 0) {
        boolean any = false;
        for (int s = 0; s < N_SPECIES; s++) any |= w.squads.k[s] > 0;
        if (any) formSteps++;
        if (i % 60 == 0) {
          for (int k = 0; k < w.count; k++) {
            Agent g = w.pool[k];
            if (Float.isNaN(g.x) || Float.isNaN(g.vx) || g.x < 0 || g.x >= WORLD_W || g.y < 0 || g.y >= WORLD_H || w.insideObstacle(g.x, g.y)) bad++;
            Squad q = w.squads.of(g);
            if (q != null && q.species != g.species) mismatch++;
          }
        }
      }
    }
    cs[r] = checksum(w);
  }
  worldObstacles = saved;
  boolean det = cs[0] == cs[1];
  boolean pass = noneNoSquads && det && bad == 0 && mismatch == 0;
  report("F6 호환성", pass, "진형 없음이면 분대 없음 " + (noneNoSquads ? "O" : "X") + ", 기본 월드(장애물+AI 진형) 재현성 " + (det ? "O" : "X")
    + ", 불변식 위반 " + bad + ", 분대-종족 불일치 " + mismatch + ", AI가 진형을 쓴 시간 " + nf(formSteps / 60.0, 1, 1) + "초/40초");
  return pass;
}

// ---------- P : 성능 ----------

boolean testFormPerf() {
  float[] best = {1e9, 1e9};
  float satRate = 0, squadShare = 0;
  for (int mode = 0; mode < 2; mode++) {
    for (int rep = 0; rep < 3; rep++) {
      World w = new World(61);
      w.eco.enabled = false;                                   // 개체 수 고정 (1,200)
      w.setPlayer(-1);
      for (int s = 0; s < N_SPECIES; s++) {
        w.cmd[s].formSet = mode == 0 ? FM_NONE : FM_LINE;
        w.cmd[s].isPlayer = true;                              // AI 명령 없이 진형 설정만 비교
      }
      for (int i = 0; i < 60; i++) w.step();
      long sat = 0, ag = 0;
      w.nsSquad = 0;
      long t0 = System.nanoTime();
      for (int i = 0; i < 600; i++) {
        w.step();
        sat += w.forceSat;
        ag += w.count;
      }
      float ms = (System.nanoTime() - t0) / 1e6 / 600;
      if (ms < best[mode]) {
        best[mode] = ms;
        if (mode == 1) {
          satRate = sat / (float) max(1, ag);
          squadShare = w.nsSquad / 1e6 / 600;
        }
      }
    }
  }
  float ratio = best[1] / best[0];
  boolean pass = ratio <= 1.25;
  report("P 진형 성능 (1,200마리, best-of-3 x 600스텝)", pass, "진형 없음 " + nf(best[0], 1, 2) + "ms, 횡대 " + nf(best[1], 1, 2) + "ms (x" + nf(ratio, 1, 2)
    + ", 기준 1.25 이하), 분대 처리 " + nf(squadShare, 1, 3) + "ms/스텝, 합력 상한 포화율 " + nf(satRate * 100, 1, 1) + "%");
  return pass;
}

// ---------- 스크린샷 (selfTestFrame에서 호출) ----------

World formShotWorld() {
  boolean saved = worldObstacles;
  worldObstacles = true;
  World w = new World(71);
  worldObstacles = saved;
  w.eco.enabled = false;
  w.clear();
  w.setPlayer(-1);
  for (int s = 0; s < N_SPECIES; s++) w.cmd[s].isPlayer = true;
  w.spawnCluster(0, 140, 400, 450, 120);
  w.spawnCluster(1, 140, 1750, 1100, 120);
  w.spawnCluster(2, 140, 400, 1100, 120);
  w.cmd[0].formSet = FM_LINE;
  w.cmd[0].moveTo(1900, 450);
  w.cmd[1].formSet = FM_AUTO;
  w.cmd[1].defendAt(1750, 1100);
  w.cmd[2].formSet = FM_AUTO;
  w.cmd[2].moveTo(1500, 1250);
  return w;
}
