// V0.7 Flow Field 검증 (FL1~FL5). SelfTest.pde의 runSelfTest()에서 -Only flow 로 호출된다.
//   FL1 장의 정확성 (최적성 조건, 막힌 칸, 경로 도달)   FL2 오목 장애물(U자) 돌파   FL3 캐시 재사용과 재현성
//   FL4 목표가 장애물 안/갇힌 곳일 때 안전   FL5 성능

boolean testFlow() {
  boolean ok = true;
  ok &= testFlowCorrect();
  ok &= testFlowTrap();
  ok &= testFlowCache();
  ok &= testFlowEdge();
  ok &= testFlowPerf();
  println(ok ? "=== FLOW PASS ===" : "=== FLOW FAILED ===");
  return ok;
}

// U자 함정 : 서쪽이 열린 오목한 장애물 (원 12개). 안쪽 (1000, 750)에서 동쪽 목표로 가려면 서쪽으로 나왔다가 돌아가야 한다.
void addTrap(World w) {
  for (int i = 0; i < 6; i++) w.addObstacle(1200, 550 + i * 80, 60);        // 동쪽 벽
  for (int i = 0; i < 3; i++) {
    w.addObstacle(1120 - i * 80, 550, 60);                                  // 위쪽 팔
    w.addObstacle(1120 - i * 80, 950, 60);                                  // 아래쪽 팔
  }
}

// ---------- FL1 : 장의 정확성 ----------

boolean testFlowCorrect() {
  World w = orderWorld(-1, 81);
  addTrap(w);
  w.addObstacle(1700, 300, 100);
  FlowField f = new FlowField();
  f.build(w, 1900, 750);
  int open = 0, reach = 0, badOpt = 0, badWalk = 0, blockedDir = 0, walkLen = 0;
  float maxWalk = 0;
  for (int c = 0; c < FF_NX * FF_NY; c++) {
    int cx = c % FF_NX, cy = c / FF_NX;
    if (f.blocked[c]) {
      if (f.dx[c] != 0 || f.dy[c] != 0) blockedDir++;
      continue;
    }
    open++;
    if (f.cost[c] >= 1e8) continue;
    reach++;
    // 최적성 조건 : 합법적인 모든 이웃 m에 대해 cost[c] <= cost[m] + 이동 비용 (다익스트라 해의 필요충분 조건)
    for (int oy = -1; oy <= 1; oy++) {
      for (int ox = -1; ox <= 1; ox++) {
        if (ox == 0 && oy == 0) continue;
        int nx = cx + ox, ny = cy + oy;
        if (nx < 0 || ny < 0 || nx >= FF_NX || ny >= FF_NY) continue;
        int m = ny * FF_NX + nx;
        if (f.blocked[m]) continue;
        if (ox != 0 && oy != 0 && (f.blocked[cy * FF_NX + nx] || f.blocked[ny * FF_NX + cx])) continue;
        float step = (ox != 0 && oy != 0) ? 1.4142 : 1.0;
        if (f.cost[c] > f.cost[m] + step + 1e-3) badOpt++;
      }
    }
    // 방향을 따라 칸 단위로 걸으면 목표 칸에 닿는다 (막힌 칸을 밟지 않고 비용이 줄어든다)
    int cur = c, steps = 0;
    boolean good = true;
    while (cur != f.goal && steps < 400) {
      int x = cur % FF_NX, y = cur / FF_NX;
      int nx = x + round(f.dx[cur]), ny = y + round(f.dy[cur]);
      if (nx < 0 || ny < 0 || nx >= FF_NX || ny >= FF_NY) {
        good = false;
        break;
      }
      int m = ny * FF_NX + nx;
      if (f.blocked[m] || f.cost[m] >= f.cost[cur]) {
        good = false;
        break;
      }
      cur = m;
      steps++;
    }
    if (!good || cur != f.goal) badWalk++;
    walkLen += steps;
    maxWalk = max(maxWalk, steps);
  }
  // 직선이 열린 곳에서는 비용이 (대략) 직선 거리 : 목표에서 동쪽으로 600px 떨어진 열린 칸
  float straight = f.costAt(1900, 750 + 600);
  float expect = 600 / FF_CELL;
  boolean straightOk = abs(straight - expect) <= 1.5;
  // 함정 안쪽 (1000, 750)의 비용은 직선 거리보다 훨씬 크다 (돌아가야 한다)
  float inside = f.costAt(1000, 750);
  boolean detour = inside > (900 / FF_CELL) * 1.6;
  boolean pass = badOpt == 0 && badWalk == 0 && blockedDir == 0 && reach > open * 0.95 && straightOk && detour && f.cost[f.goal] == 0;
  report("FL1 장의 정확성", pass, "열린 칸 " + open + " (도달 " + reach + "), 최적성 위반 " + badOpt + ", 경로 실패 " + badWalk + ", 막힌 칸 방향 " + blockedDir
    + ", 직선 구간 비용 " + nf(straight, 1, 1) + " (기대 " + nf(expect, 1, 1) + "), 함정 안 비용 " + nf(inside, 1, 1) + " (직선 " + nf(900 / FF_CELL, 1, 1)
    + "), 최장 경로 " + round(maxWalk) + "칸");
  return pass;
}

// ---------- FL2 : U자 함정 ----------

float[] flowTrapRun(boolean useFlow, int form) {
  World w = orderWorld(0, 82);
  w.useFlow = useFlow;
  addTrap(w);
  w.spawnCluster(0, 60, 1000, 750, 55);
  w.cmd[0].formSet = form;
  w.cmd[0].moveTo(1900, 750);
  int insideMax = 0;
  int firstHalf = -1;
  for (int i = 0; i < 3600; i++) {                          // 60초
    w.step();
    if (i % 30 == 0) {
      int inside = 0;
      for (int k = 0; k < w.count; k++) if (w.insideObstacle(w.pool[k].x, w.pool[k].y)) inside++;
      insideMax = max(insideMax, inside);
    }
    if (firstHalf < 0 && i % 60 == 0) {
      int past = 0;
      for (int k = 0; k < w.count; k++) if (w.pool[k].x > 1400) past++;
      if (past >= w.count / 2) firstHalf = i;
    }
  }
  int arrived = 0, n = 0;
  for (int k = 0; k < w.count; k++) {
    Agent a = w.pool[k];
    n++;
    if (dist(a.x, a.y, 1900, 750) < 220) arrived++;
  }
  return new float[] {arrived, n, insideMax, firstHalf < 0 ? -1 : firstHalf / 60.0};
}

boolean testFlowTrap() {
  float[] on = flowTrapRun(true, FM_NONE);
  float[] off = flowTrapRun(false, FM_NONE);
  float[] onF = flowTrapRun(true, FM_AUTO);                 // 진형(종대)과 함께
  boolean pass = on[0] >= on[1] * 0.7 && on[2] == 0 && onF[0] >= onF[1] * 0.7 && onF[2] == 0 && on[0] >= off[0] + on[1] * 0.3;
  report("FL2 U자 함정 (RED 60, 60초)", pass, "Flow 켬 " + round(on[0]) + "/" + round(on[1]) + " 도착 (절반이 벽을 넘은 시각 " + nf(on[3], 1, 1) + "초, 장애물 안 최대 " + round(on[2])
    + ") | Flow 끔 " + round(off[0]) + "/" + round(off[1]) + " (절반 통과 " + nf(off[3], 1, 1) + "초) | Flow+종대 " + round(onF[0]) + "/" + round(onF[1])
    + " (장애물 안 최대 " + round(onF[2]) + ")");
  return pass;
}

// ---------- FL3 : 캐시 재사용과 재현성 ----------

boolean testFlowCache() {
  // 같은 목표를 향하는 많은 개체는 장 하나를 공유한다
  World w = orderWorld(0, 83);
  addTrap(w);
  w.spawnCluster(0, 200, 1000, 750, 55);
  w.cmd[0].formSet = FM_NONE;
  w.cmd[0].moveTo(1900, 750);
  w.flow.reset();
  for (int i = 0; i < 120; i++) w.step();                   // 2초
  int builds = w.flow.builds, hits = w.flow.hits;
  // 목표를 옮기면 새 장, 되돌리면 캐시 적중
  w.cmd[0].moveTo(1900, 1300);
  for (int i = 0; i < 60; i++) w.step();
  int b2 = w.flow.builds;
  w.cmd[0].moveTo(1900, 750);
  for (int i = 0; i < 60; i++) w.step();
  int b3 = w.flow.builds;
  boolean shared = builds <= 2 && hits > builds * 50;
  boolean reuse = b3 == b2;                                 // 처음 목표로 돌아와도 새로 만들지 않는다
  // 장애물이 바뀌면 캐시를 버린다
  w.flow.get(w, 1900, 750);                                 // 이 목표의 장은 캐시에 있다
  int b4 = w.flow.builds;
  w.nObs = MAX_OBS - 1;                                     // 함정이 12개를 다 채웠으므로 하나 비우고 새로 놓는다
  w.addObstacle(1500, 300, 50);                             // 배치가 바뀌면 같은 목표도 새로 만든다
  w.flow.get(w, 1900, 750);
  boolean invalidated = w.flow.builds == b4 + 1;

  // 재현성 : 같은 시드에서 Flow를 쓰는 두 실행이 정확히 같다
  long[] cs = new long[2];
  for (int r = 0; r < 2; r++) {
    World a = orderWorld(0, 84);
    addTrap(a);
    a.spawnCluster(0, 80, 1000, 750, 55);
    a.cmd[0].moveTo(1900, 750);
    for (int i = 0; i < 1200; i++) a.step();
    cs[r] = checksum(a);
  }
  boolean det = cs[0] == cs[1];
  boolean pass = shared && reuse && invalidated && det;
  report("FL3 캐시와 재현성", pass, "200마리 2초 : 장 " + builds + "개 생성, 적중 " + hits + (shared ? "" : " (공유 부족)") + " | 목표 복귀 시 재생성 " + (reuse ? "없음" : "있음")
    + " | 장애물 변경 후 재생성 " + (invalidated ? "O" : "X") + " | 두 실행 일치 " + (det ? "O" : "X"));
  return pass;
}

// ---------- FL4 : 예외 상황 ----------

boolean testFlowEdge() {
  // (a) 목표가 장애물 한가운데 : 가장자리 근처로 간다. 개체는 장애물 안으로 들어가지 않는다.
  World w = orderWorld(0, 85);
  w.addObstacle(1600, 750, 100);
  w.spawnCluster(0, 50, 600, 750, 60);
  w.cmd[0].formSet = FM_NONE;
  w.cmd[0].moveTo(1600, 750);
  int inside = 0;
  for (int i = 0; i < 1800; i++) {
    w.step();
    if (i % 60 == 0) for (int k = 0; k < w.count; k++) if (w.insideObstacle(w.pool[k].x, w.pool[k].y)) inside++;
  }
  int near = 0;
  for (int k = 0; k < w.count; k++) if (dist(w.pool[k].x, w.pool[k].y, 1600, 750) < 260) near++;
  boolean a = inside == 0 && near >= w.count * 0.8;

  // (b) 완전히 둘러싸인 구역이 목표 : 길이 없으므로 장은 쓸 수 없지만 죽거나 NaN이 되지 않는다
  World e = orderWorld(0, 86);
  for (int i = 0; i < 12; i++) {
    float ang = TWO_PI * i / 12;
    e.addObstacle(1700 + cos(ang) * 130, 750 + sin(ang) * 130, 70);
  }
  e.spawnCluster(0, 40, 700, 750, 60);
  e.cmd[0].formSet = FM_NONE;
  e.cmd[0].moveTo(1700, 750);                                // 고리 한가운데
  int bad = 0;
  for (int i = 0; i < 1200; i++) {
    e.step();
    if (i % 60 == 0) {
      for (int k = 0; k < e.count; k++) {
        Agent g = e.pool[k];
        if (Float.isNaN(g.x) || Float.isNaN(g.vx) || e.insideObstacle(g.x, g.y)) bad++;
      }
    }
  }
  boolean b = bad == 0 && e.count == 40;

  // (c) 장애물이 없으면 장을 전혀 만들지 않는다 (V0.6 이전과 같은 경로)
  World n = orderWorld(0, 87);
  n.spawnCluster(0, 50, 600, 750, 60);
  n.cmd[0].moveTo(1800, 750);
  n.flow.reset();
  for (int i = 0; i < 300; i++) n.step();
  boolean c = n.flow.builds == 0;

  boolean pass = a && b && c;
  report("FL4 예외 상황", pass, "목표가 장애물 안 : 장애물 안 개체 " + inside + ", 목표 260px 이내 " + near + "/" + w.count + (a ? "" : " X")
    + " | 닫힌 고리 안 목표 : 위반 " + bad + (b ? " O" : " X") + " | 장애물 없음이면 장 생성 " + n.flow.builds + "개" + (c ? " O" : " X"));
  return pass;
}

// ---------- FL5 : 성능 ----------

boolean testFlowPerf() {
  World w = orderWorld(-1, 88);
  addTrap(w);
  for (int i = 0; i < 6; i++) w.addObstacle(300 + i * 280, 300 + (i % 2) * 700, 70);
  FlowField f = new FlowField();
  float bestBuild = 1e9;
  for (int rep = 0; rep < 7; rep++) {
    long t0 = System.nanoTime();
    f.build(w, 1900 + rep * 10, 750);
    bestBuild = min(bestBuild, (System.nanoTime() - t0) / 1e6);
  }
  float bestSample = 1e9;
  float sink = 0;
  for (int rep = 0; rep < 5; rep++) {
    long t0 = System.nanoTime();
    for (int i = 0; i < 100000; i++) {
      if (f.sample((i * 37) % 2400, (i * 91) % 1500)) sink += f.outX;
    }
    bestSample = min(bestSample, (System.nanoTime() - t0) / 1e5);          // 전체 ns / 100,000회 = 1회당 ns
  }
  float nsPerSample = bestSample + (sink > 1e30 ? 1 : 0);                   // sink 사용 (최적화로 호출이 사라지지 않게)
  // 개체 3,000마리가 매 스텝 직선 검사 + 장 조회를 하는 비용 상한 추정 : 장애물이 있는 월드의 스텝 시간
  float best[] = {1e9, 1e9};
  float useShare = 0;
  int builds = 0;
  for (int mode = 0; mode < 2; mode++) {
    for (int rep = 0; rep < 3; rep++) {
      World p = new World(89);
      p.eco.enabled = false;
      p.setPlayer(-1);
      for (int s = 0; s < N_SPECIES; s++) p.cmd[s].isPlayer = true;
      boolean saved = worldObstacles;
      worldObstacles = true;
      p.reset(89);
      worldObstacles = saved;
      p.useFlow = mode == 1;
      for (int s = 0; s < N_SPECIES; s++) p.cmd[s].moveTo(homeXFlow(s), 750);
      for (int i = 0; i < 60; i++) p.step();
      p.flow.uses = 0;
      p.flow.builds = 0;
      long t0 = System.nanoTime();
      for (int i = 0; i < 480; i++) p.step();
      float ms = (System.nanoTime() - t0) / 1e6f / 480;
      if (ms < best[mode]) {
        best[mode] = ms;
        if (mode == 1) {
          useShare = p.flow.uses / (float) (480L * p.count);
          builds = p.flow.builds;
        }
      }
    }
  }
  // 직선 검사만의 비용 (개체 1,200 x 장애물 8)
  World q = new World(90);
  boolean sv = worldObstacles;
  worldObstacles = true;
  q.reset(90);
  worldObstacles = sv;
  float bestSeg = 1e9;
  int hitsSeg = 0;
  for (int rep = 0; rep < 5; rep++) {
    long t0 = System.nanoTime();
    for (int k = 0; k < q.count; k++) {
      Agent g = q.pool[k];
      if (q.segBlocked(g.x, g.y, 1200, 750, FF_CLEAR)) hitsSeg++;
    }
    bestSeg = min(bestSeg, (System.nanoTime() - t0) / (float) max(1, q.count));   // 전체 ns / 개체 수 = 개체당 ns
  }
  float ratio = best[1] / max(0.01, best[0]);
  boolean pass = bestBuild <= 3.0 && nsPerSample <= 400 && ratio <= 1.15;
  report("FL5 성능", pass, "장 하나 생성 " + nf(bestBuild, 1, 2) + "ms (기준 3.0 이하, " + FF_NX + "x" + FF_NY + "칸), 조회 1회 " + nf(nsPerSample, 1, 0) + "ns, 1,200마리 스텝 Flow 끔 "
    + nf(best[0], 1, 2) + "ms / 켬 " + nf(best[1], 1, 2) + "ms (x" + nf(ratio, 1, 2) + ", 기준 1.15 이하), 장을 따른 비율 " + nf(useShare * 100, 1, 1) + "%, 장 생성 " + builds
    + "개, 직선 검사 " + nf(bestSeg, 1, 0) + "ns/개체 (막힌 비율 " + nf(hitsSeg / (5f * max(1, q.count)) * 100, 1, 1) + "%)");
  return pass;
}

float homeXFlow(int s) {
  return s == 0 ? 1900 : (s == 1 ? 500 : 1200);
}
