// 자체 검증. Config.pde의 SELFTEST를 true로 바꾸면 setup에서 실행된다 (콘솔에 PASS/FAIL 출력).
//   T1 격자 정확도  T2 재현성  T3 군집 창발  T4 불변식  T5 성능  T6 개체 수 조절

void runSelfTest() {
  println("=== SWARM WAR SELFTEST ===");
  boolean runEvo = !SELFTEST_ONLY.equals("noevo");     // "noevo" : 진화 실험(약 8분)만 빼고 전부
  if (SELFTEST_ONLY.length() > 0 && runEvo) {
    if (SELFTEST_ONLY.equals("balance")) testBalance();
    else if (SELFTEST_ONLY.equals("duels")) testDuels();
    else if (SELFTEST_ONLY.equals("genetics")) testGenetics();
    else if (SELFTEST_ONLY.equals("evo")) testEvolution();
    else if (SELFTEST_ONLY.equals("dbg")) debugControl();
    else if (SELFTEST_ONLY.equals("inv")) testInvariants();
    else if (SELFTEST_ONLY.equals("part1")) {            // T1~T13 (진화 실험 제외)
      boolean ok = true;
      ok &= testGrid();
      ok &= testDeterminism();
      ok &= testFlocking();
      ok &= testInvariants();
      testPerformance();
      ok &= testPopulation();
      ok &= testCombatLogic();
      ok &= testDuels();
      ok &= testCombatIntegrity();
      ok &= testFood();
      ok &= testReproduction();
      ok &= testBalance();
      ok &= testGenetics();
      println(ok ? "=== PART1 PASS ===" : "=== PART1 FAILED ===");
    } else if (SELFTEST_ONLY.equals("part2")) {          // T15~T24 + 렌더 성능
      boolean ok = true;
      ok &= testCamera();
      ok &= testOrders();
      ok &= testAI();
      ok &= testStats();
      ok &= testInput();
      ok &= testModes();
      ok &= testEffects();
      ok &= testStability();
      ok &= testFrameIndependence();
      stAllOk = ok;
    }
    else if (SELFTEST_ONLY.equals("renderprof")) println("(렌더 프로파일은 draw()에서 실행)");
    else if (SELFTEST_ONLY.equals("final")) {
      testModes();
      testEffects();
      testStability();
      testFrameIndependence();
    }
    else if (SELFTEST_ONLY.equals("v05")) {
      testCamera();
      testOrders();
      testAI();
      testStats();
      testInput();
    }
    println("=== ONLY " + SELFTEST_ONLY + " done ===");
    return;
  }
  boolean ok = true;
  ok &= testGrid();
  ok &= testDeterminism();
  ok &= testFlocking();
  ok &= testInvariants();
  testPerformance();
  ok &= testPopulation();
  ok &= testCombatLogic();
  ok &= testDuels();
  ok &= testCombatIntegrity();
  ok &= testFood();
  ok &= testReproduction();
  ok &= testBalance();
  ok &= testGenetics();
  if (runEvo) ok &= testEvolution();
  ok &= testCamera();
  ok &= testOrders();
  ok &= testAI();
  ok &= testStats();
  ok &= testInput();
  ok &= testModes();
  ok &= testEffects();
  ok &= testStability();
  ok &= testFrameIndependence();
  stAllOk = ok;                                       // 렌더링 성능(T23)은 draw() 안에서 재고 최종 판정을 출력한다
}

boolean stAllOk = true;

void report(String name, boolean pass, String detail) {
  println("[" + (pass ? "PASS" : "FAIL") + "] " + name + " : " + detail);
}

// T1 : 격자 이웃 조회가 전수 비교(brute force)와 정확히 일치하는가
boolean testGrid() {
  World w = new World(7);
  w.clear();
  for (int i = 0; i < 1000; i++) {
    w.spawn(w.rng.nextInt(N_SPECIES), w.rng.nextFloat() * WORLD_W, w.rng.nextFloat() * WORLD_H);
  }
  w.spawnCluster(0, 500, 1200, 750, 100);             // 조밀한 덩어리도 섞는다
  w.grid.build(w.pool, w.count);

  int[] viaGrid = new int[MAX_AGENTS];
  int[] viaBrute = new int[MAX_AGENTS];
  int mismatches = 0, samples = 0;
  float r = 70;
  for (int i = 0; i < w.count; i += 30) {
    Agent me = w.pool[i];
    int ng = w.grid.queryRadius(w.pool, me.x, me.y, r, i, viaGrid);
    int nb = 0;
    for (int j = 0; j < w.count; j++) {
      if (j == i) continue;
      float dx = w.pool[j].x - me.x, dy = w.pool[j].y - me.y;
      if (dx * dx + dy * dy < r * r) viaBrute[nb++] = j;
    }
    java.util.Arrays.sort(viaGrid, 0, ng);
    java.util.Arrays.sort(viaBrute, 0, nb);
    boolean same = ng == nb;
    for (int k = 0; same && k < ng; k++) if (viaGrid[k] != viaBrute[k]) same = false;
    if (!same) mismatches++;
    samples++;
  }
  boolean pass = mismatches == 0;
  report("T1 격자 정확도", pass, w.count + "마리, 표본 " + samples + "개, 불일치 " + mismatches);
  return pass;
}

long checksum(World w) {
  long h = 1125899906842597L;
  for (int i = 0; i < w.count; i++) {
    Agent a = w.pool[i];
    h = 31 * h + Float.floatToIntBits(a.x);
    h = 31 * h + Float.floatToIntBits(a.y);
    h = 31 * h + Float.floatToIntBits(a.vx);
    h = 31 * h + Float.floatToIntBits(a.vy);
    h = 31 * h + Float.floatToIntBits(a.hp);
    h = 31 * h + Float.floatToIntBits(a.energy);
    h = 31 * h + a.species;
    h = 31 * h + a.state;
    h = 31 * h + a.gen;
  }
  h = 31 * h + w.totalDeaths;
  h = 31 * h + w.eco.totalBirths;
  h = 31 * h + w.eco.generated;
  h = 31 * h + w.eco.consumed;
  return h;
}

long runChecksum(long seed, int steps) {
  World w = new World(seed);
  for (int i = 0; i < steps; i++) w.step();
  return checksum(w);
}

// T2 : 같은 시드는 같은 결과, 다른 시드는 다른 결과
boolean testDeterminism() {
  long a = runChecksum(123, 600);
  long b = runChecksum(123, 600);
  long c = runChecksum(124, 600);
  boolean pass = a == b && a != c;
  report("T2 재현성", pass, "같은 시드 " + (a == b ? "일치" : "불일치") + ", 다른 시드 " + (a != c ? "다름" : "같음"));
  return pass;
}

// 한 종족만 흩뿌려 놓고 seconds초 진행했을 때의 군집 지표
// {국소 정렬도 처음, 국소 정렬도 끝, NN, 군집 수, 최대 군집, 고립, 전역 정렬도 처음, 전역 정렬도 끝}
float[] flockRun(int species, int n, float seconds) {
  return flockRun(species, n, seconds, true);
}

float[] flockRun(int species, int n, float seconds, boolean boidsOn) {
  World w = new World(11);
  w.eco.enabled = false;                              // Boids만 본다 (채집으로 흩어지는 효과 제외)
  if (!boidsOn) {                                     // 대조군 : 정렬과 응집을 끈다
    w.species[species].wAli = 0;
    w.species[species].wCoh = 0;
  }
  w.clear();
  w.spawnCluster(species, n, 1200, 750, 300);
  Metrics m = new Metrics();
  m.compute(w);
  float la0 = m.localAlign[species], g0 = m.polarization[species];
  int steps = round(seconds / DT);
  for (int i = 0; i < steps; i++) w.step();
  m.compute(w);
  return new float[] {la0, m.localAlign[species], m.meanNN[species], m.clusters[species], m.largest[species],
    m.isolated[species], g0, m.polarization[species]};
}

// T3 : 무작위 방향으로 출발한 무리가 군집을 형성하는가
//      통과 기준 : 국소 정렬도 0.8 이상(처음보다 0.5 이상 상승), 고립 개체 5% 이하
//      (전역 정렬도는 군집이 여러 개면 낮아지므로 참고용으로만 출력한다)
boolean testFlocking() {
  boolean pass = true;
  float[] nn = new float[N_SPECIES];
  for (int s = 0; s < N_SPECIES; s++) {
    float[] r = flockRun(s, 300, 20);
    nn[s] = r[2];
    boolean p = r[1] >= 0.8 && r[1] > r[0] + 0.5 && r[5] <= 15;
    pass &= p;
    report("T3 군집 창발 " + makeSpecies()[s].name, p, "국소 정렬 " + nf(r[0], 1, 2) + " -> " + nf(r[1], 1, 2)
      + ", 전역 " + nf(r[6], 1, 2) + " -> " + nf(r[7], 1, 2)
      + ", NN " + nf(r[2], 1, 1) + ", 군집 " + int(r[3]) + " (최대 " + int(r[4]) + "), 고립 " + int(r[5]));
  }
  // 대조군 : 정렬과 응집을 끄면 국소 정렬도가 낮게 남아야 한다 (지표가 항상 높게 나오는 게 아님을 확인)
  for (int s = 0; s < N_SPECIES; s++) {
    float[] c = flockRun(s, 300, 20, false);
    boolean p = c[1] < 0.5;
    pass &= p;
    report("T3 대조군(Boids 끔) " + makeSpecies()[s].name, p, "국소 정렬 " + nf(c[0], 1, 2) + " -> " + nf(c[1], 1, 2) + " (0.5 미만이어야 함)");
  }
  boolean tight = nn[1] < nn[0];
  report("T3 BLUE가 RED보다 조밀", tight, "NN BLUE " + nf(nn[1], 1, 1) + " < RED " + nf(nn[0], 1, 1));
  return pass && tight;
}

// T4 : 2000스텝 동안 NaN 없음, 월드 안, 속도 범위 유지
boolean testInvariants() {
  World w = new World(21);
  int bad = 0, firstBadStep = -1;
  int vPos = 0, vLo = 0, vHi = 0, vHp = 0, vEn = 0, vOther = 0;      // 조건별 위반 수 (원인 추적용)
  for (int st = 0; st < 2000; st++) {
    w.step();
    for (int i = 0; i < w.count; i++) {
      Agent a = w.pool[i];
      float sp = sqrt(a.vx * a.vx + a.vy * a.vy);
      boolean fin = !Float.isNaN(a.x) && !Float.isNaN(a.y) && !Float.isNaN(sp) && !Float.isInfinite(sp);
      boolean pos = fin && a.x >= 0 && a.x < WORLD_W && a.y >= 0 && a.y < WORLD_H;
      boolean lo = sp >= 0.4 * a.speedMax * 0.99;
      boolean hi = sp <= a.speedMax * a.speedMul * 1.01;
      boolean hp = a.hp > 0 && a.hp <= a.maxHp;
      boolean en = a.energy >= 0 && a.energy <= a.maxEnergy + 0.001 && !Float.isNaN(a.energy);
      boolean other = a.pendingDmg == 0 && a.state >= 0 && a.state <= AS_REGROUP && a.gen >= 0;
      if (!(pos && lo && hi && hp && en && other)) {
        bad++;
        if (firstBadStep < 0) firstBadStep = st;
        if (!pos) vPos++;
        if (!lo) vLo++;
        if (!hi) vHi++;
        if (!hp) vHp++;
        if (!en) vEn++;
        if (!other) vOther++;
      }
    }
  }
  boolean pass = bad == 0;
  report("T4 불변식", pass, "2000스텝 x " + w.count + "마리, 위반 " + bad + (pass ? "" : " (첫 위반 스텝 " + firstBadStep + "; 위치 " + vPos + ", 속도 하한 "
    + vLo + ", 속도 상한 " + vHi + ", 체력 " + vHp + ", 에너지 " + vEn + ", 기타 " + vOther + ")"));
  return pass;
}

// T5 : 개체 수별 스텝 시간
void testPerformance() {
  int[] sizes = {1000, 2000, 3000};
  for (int n : sizes) {
    World w = new World(31);
    w.clear();
    for (int s = 0; s < N_SPECIES; s++) w.spawnCluster(s, n / N_SPECIES, w.homeX[s], w.homeY[s], 230);
    for (int i = 0; i < 300; i++) w.step();                    // 무리가 모여 밀도가 높아진 상태까지 예열
    w.nsGrid = 0;
    w.nsBoids = 0;
    w.nsInt = 0;
    int steps = 300;
    long t0 = System.nanoTime();
    for (int i = 0; i < steps; i++) w.step();
    float total = (System.nanoTime() - t0) / 1000000.0f / steps;
    println("[INFO] T5 성능 N=" + w.count + " : 스텝 평균 " + nf(total, 1, 2) + "ms (격자 " + nf(w.nsGrid / 1000000.0f / steps, 1, 2)
      + " / 계산 " + nf(w.nsBoids / 1000000.0f / steps, 1, 2) + " / 적분 " + nf(w.nsInt / 1000000.0f / steps, 1, 2) + ")");
  }
}

// T6 : 개체 수 조절 후 개수와 풀 무결성
boolean testPopulation() {
  World w = new World(41);
  boolean pass = true;
  String detail = "";

  w.setPopulation(0, 700);
  pass &= w.pop[0] == 700 && w.count == 700 + 400 + 400;
  w.setPopulation(0, 100);
  pass &= w.pop[0] == 100 && w.count == 100 + 400 + 400;
  w.setPopulation(1, 0);
  pass &= w.pop[1] == 0 && w.count == 100 + 0 + 400;
  int capped = w.setPopulation(2, 100000);
  pass &= w.count == MAX_AGENTS && capped == MAX_AGENTS - 100;
  detail += "최종 " + w.count + "마리 (RED " + w.pop[0] + ", BLUE " + w.pop[1] + ", GREEN " + w.pop[2] + ")";

  // 풀 무결성 : 활성 구간의 ID 중복이 없고 종족 값이 정상이며, 활성+비활성이 모두 서로 다른 객체
  java.util.HashSet<Integer> ids = new java.util.HashSet<Integer>();
  java.util.HashSet<Agent> objs = new java.util.HashSet<Agent>();
  boolean unique = true;
  for (int i = 0; i < w.count; i++) {
    if (!ids.add(w.pool[i].id)) unique = false;
    if (w.pool[i].species < 0 || w.pool[i].species >= N_SPECIES) unique = false;
  }
  for (int i = 0; i < MAX_AGENTS; i++) objs.add(w.pool[i]);
  pass &= unique && objs.size() == MAX_AGENTS;
  detail += ", ID 중복/오류 " + (unique ? "없음" : "있음") + ", 풀 객체 " + objs.size() + "/" + MAX_AGENTS;

  report("T6 개체 수 조절", pass, detail);
  return pass;
}

// ---------- V0.2 전투 검증 ----------

World sandbox() {
  World w = new World(1);
  w.clear();
  return w;
}

// 시나리오용 개체 : 유전자를 모두 종족 기본값(0.5)으로 고정해서 전투력 비율 같은 판단 경계가 우연에 흔들리지 않게 한다
Agent put(World w, int sp, float x, float y) {
  Agent a = w.spawn(sp, x, y);
  a.vx = 0;
  a.vy = 0;
  for (int g = 0; g < NGENE; g++) a.gene[g] = 0.5;
  w.evo.apply(a, w.species[sp]);
  return a;
}

// 한 스텝의 계산만 돌려서 개체 idx의 상태를 읽는다
int stateOf(World w, int idx) {
  w.grid.build(w.pool, w.count);
  w.boids.compute(w);
  return w.pool[idx].state;
}

String stateName(int s) {
  String[] n = {"FLOCK", "ATTACK", "FLEE", "SUPPORT", "RETREAT", "REGROUP"};
  return n[s];
}

// 주변에 n마리를 (cx, cy) 근처 반지름 r의 원 위에 배치
void ring(World w, int sp, int n, float cx, float cy, float r) {
  for (int i = 0; i < n; i++) {
    float th = TWO_PI * i / n;
    put(w, sp, cx + cos(th) * r, cy + sin(th) * r);
  }
}

// T7 : 개체가 주변 아군과 적의 수와 전투력을 보고 상태를 결정하는가
boolean testCombatLogic() {
  boolean pass = true;
  float X = 1200, Y = 750;
  String detail;

  // (a) 수적으로 크게 밀리면 도주
  World w = sandbox();
  put(w, 2, X, Y);                                   // GREEN 1마리
  ring(w, 0, 5, X, Y, 35);                           // RED 5마리
  int a = stateOf(w, 0);
  boolean pa = a == AS_FLEE;
  report("T7a 열세면 도주 (GREEN 1 vs RED 5)", pa, stateName(a));
  pass &= pa;

  // (b) 수적으로 우세하면 공격
  w = sandbox();
  put(w, 0, X, Y);
  ring(w, 0, 6, X, Y, 30);                           // 아군 RED 6마리
  ring(w, 2, 2, X, Y, 40);                           // 적 GREEN 2마리
  int b = stateOf(w, 0);
  boolean pb = b == AS_ATTACK;
  report("T7b 우세면 공격 (RED 7 vs GREEN 2)", pb, stateName(b));
  pass &= pb;

  // (c) 같은 적 1마리라도 아군 수에 따라 결정이 바뀐다 (가장 가까운 적을 무조건 공격하지 않는다)
  w = sandbox();
  put(w, 1, X, Y);                                   // BLUE 혼자
  put(w, 0, X + 30, Y);                              // RED 1마리
  int c1 = stateOf(w, 0);
  w = sandbox();
  put(w, 1, X, Y);
  ring(w, 1, 3, X, Y, 25);                           // 아군 BLUE 3마리 추가
  put(w, 0, X + 30, Y);
  int c2 = stateOf(w, 0);
  boolean pc = c1 == AS_FLEE && c2 == AS_ATTACK;
  report("T7c 같은 적, 아군 수에 따라 결정이 바뀜", pc, "혼자 " + stateName(c1) + ", 아군 3마리 " + stateName(c2));
  pass &= pc;

  // (d) 체력이 낮으면 후퇴
  w = sandbox();
  Agent hurt = put(w, 1, X, Y);
  hurt.hp = hurt.maxHp * 0.1;
  ring(w, 1, 4, X, Y, 25);                           // 아군이 많아 우세해도
  put(w, 0, X + 30, Y);
  int d = stateOf(w, 0);
  boolean pd = d == AS_RETREAT;
  report("T7d 체력 낮으면 후퇴", pd, stateName(d));
  pass &= pd;

  // (e) 아군이 공격받으면 지원
  w = sandbox();
  put(w, 1, X, Y);
  Agent victim = put(w, 1, X + 50, Y);
  victim.hurtTimer = 0.8;
  int e1 = stateOf(w, 0);
  w = sandbox();
  put(w, 1, X, Y);
  put(w, 1, X + 50, Y);
  int e2 = stateOf(w, 0);
  boolean pe = e1 == AS_SUPPORT && e2 == AS_FLOCK;
  report("T7e 피격 아군 지원", pe, "피격 있음 " + stateName(e1) + ", 없음 " + stateName(e2));
  pass &= pe;

  // (f) 주변에 아군이 없으면 군집으로 복귀 (같은 종족이 멀리 있을 때만)
  w = sandbox();
  put(w, 2, X, Y);
  put(w, 2, X + 600, Y);
  put(w, 2, X + 650, Y);
  int f1 = stateOf(w, 0);
  w = sandbox();
  put(w, 2, X, Y);
  int f2 = stateOf(w, 0);
  boolean pf = f1 == AS_REGROUP && f2 == AS_FLOCK;
  report("T7f 고립되면 군집 복귀", pf, "다른 무리 있음 " + stateName(f1) + ", 종족 혼자 " + stateName(f2));
  pass &= pf;

  return pass;
}

// 두 집단을 120px 떨어뜨려 놓고 한쪽이 전멸하거나 maxSec가 될 때까지 진행. {A 생존, B 생존, 걸린 초}
float[] duel(int spA, int nA, int spB, int nB, long seed, float maxSec) {
  World w = new World(seed);
  w.eco.enabled = false;                             // 전투만 본다 (먹이, 번식, 굶주림 없음)
  w.clear();
  float spread = 10 + 8 * sqrt(max(nA, nB));
  w.spawnCluster(spA, nA, 1140, 750, spread);
  w.spawnCluster(spB, nB, 1260, 750, spread);
  int steps = round(maxSec / DT);
  int st = 0;
  for (; st < steps; st++) {
    w.step();
    w.countSpecies();
    if (w.pop[spA] == 0 || w.pop[spB] == 0) break;
  }
  w.countSpecies();
  return new float[] {w.pop[spA], w.pop[spB], st * DT};
}

// T8 : 종족 대결 결과. 설계한 상성이 나오는가
//   RED가 GREEN을 잡는다 (빠른 포식자), BLUE가 RED를 이긴다 (방어력과 아군 지원),
//   GREEN은 BLUE에게서 도주해 거의 죽지 않는다 (BLUE가 느려서 따라잡지 못함)
boolean testDuels() {
  String[] nm = {"RED", "BLUE", "GREEN"};
  int[][] pairs = {{0, 2}, {1, 2}, {1, 0}};
  int[] sizes = {1, 10, 30};
  int[][] wins = new int[3][3];                      // [pair][0 A승 / 1 B승 / 2 무승부]
  float[][] surv = new float[3][2];                  // 30:30 평균 생존 [pair][A/B]
  for (int p = 0; p < pairs.length; p++) {
    for (int sz : sizes) {
      int aw = 0, bw = 0, aSurv = 0, bSurv = 0;
      for (int sd = 0; sd < 5; sd++) {
        float[] r = duel(pairs[p][0], sz, pairs[p][1], sz, 100 + sd, 60);
        if (r[0] > r[1]) aw++;
        else if (r[1] > r[0]) bw++;
        aSurv += r[0];
        bSurv += r[1];
      }
      println("[INFO] T8 " + nm[pairs[p][0]] + " vs " + nm[pairs[p][1]] + " " + sz + ":" + sz + " : "
        + nm[pairs[p][0]] + " 승 " + aw + " / " + nm[pairs[p][1]] + " 승 " + bw + " (5회, 평균 생존 " + nf(aSurv / 5.0, 1, 1) + " : " + nf(bSurv / 5.0, 1, 1) + ")");
      if (sz == 30) {
        wins[p][0] = aw;
        wins[p][1] = bw;
        surv[p][0] = aSurv / 5.0;
        surv[p][1] = bSurv / 5.0;
      }
    }
  }
  boolean p1 = wins[0][0] >= 4;                      // RED가 GREEN을 이긴다
  boolean p2 = wins[2][0] >= 4;                      // BLUE가 RED를 이긴다
  boolean p3 = surv[1][1] >= 25;                     // GREEN은 BLUE에게서 도주해 30마리 중 25마리 이상 생존
  report("T8 상성: RED가 GREEN을 이김 (30:30, 5회 중 4회 이상)", p1, wins[0][0] + "/5");
  report("T8 상성: BLUE가 RED를 이김 (30:30, 5회 중 4회 이상)", p2, wins[2][0] + "/5");
  report("T8 상성: GREEN은 BLUE를 회피 (GREEN 평균 생존 25 이상)", p3, "GREEN " + nf(surv[1][1], 1, 1) + "/30");
  return p1 && p2 && p3;
}

// T9 : 사망과 처치 기록의 정합성, 개체 상태 불변식
//      생존 + 사망 = 시작 수 + 출생 / 사망 = 처치(전투) + 아사 / 처치 합은 사망 합 이하
boolean testCombatIntegrity() {
  World w = new World(77);
  int[] start = new int[N_SPECIES];
  for (int s = 0; s < N_SPECIES; s++) start[s] = w.pop[s];
  int badHp = 0;
  for (int st = 0; st < 3600; st++) {
    w.step();
    for (int i = 0; i < w.count; i++) {
      Agent a = w.pool[i];
      if (a.hp <= 0 || a.hp > a.maxHp + 0.001 || a.pendingDmg != 0) badHp++;
    }
  }
  w.countSpecies();
  int killSum = 0, deathSum = 0, starveSum = 0;
  boolean conserve = true;
  for (int s = 0; s < N_SPECIES; s++) {
    killSum += w.kills[s];
    deathSum += w.deaths[s];
    starveSum += w.eco.starved[s];
    if (w.pop[s] + w.deaths[s] != start[s] + w.eco.births[s]) conserve = false;
  }
  boolean pass = badHp == 0 && conserve && killSum + starveSum == deathSum && deathSum == w.totalDeaths;
  report("T9 전투 무결성", pass, "60초 후 생존 " + w.pop[0] + "/" + w.pop[1] + "/" + w.pop[2] + ", 사망 " + deathSum
    + " (처치 " + killSum + " + 아사 " + starveSum + "), 출생 " + w.eco.totalBirths + ", 체력 위반 " + badHp
    + ", 수 보존 " + (conserve ? "O" : "X") + ", 누적 피해 " + nf(w.damageDealt, 1, 0));
  return pass;
}

// ---------- V0.3 생태계 검증 ----------

// T10 : 먹이 생성량 일정, 상한, 먹기, 굶주림, 시체 확률, 먹이 정합성
boolean testFood() {
  boolean pass = true;

  // (a) 개체가 없으면 먹이는 정확히 일정한 양으로 생긴다 (20초 x 45/초 = 900), 상한을 넘지 않는다
  World w = sandbox();
  for (int i = 0; i < 1200; i++) w.step();
  boolean a1 = abs((int) (w.eco.generated - 900)) <= 1 && w.eco.food.count == w.eco.generated;
  report("T10a 먹이 생성량 일정", a1, "20초 동안 " + w.eco.generated + "개 (기대 900)");
  pass &= a1;
  for (int i = 0; i < 3600; i++) w.step();                        // 총 80초 : 3600개 > 상한
  boolean a2 = w.eco.food.count <= MAX_FOOD && w.eco.skipped > 0 && w.eco.generated + w.eco.skipped >= 3590;
  report("T10a 먹이 상한 (무한 증가 방지)", a2, "먹이 " + w.eco.food.count + "/" + MAX_FOOD + ", 상한 때문에 건너뜀 " + w.eco.skipped);
  pass &= a2;

  // (b) 먹으면 에너지가 먹이 값만큼 오르고 먹이가 사라진다
  w = sandbox();
  w.eco.foodRate = 0;
  Agent g = put(w, 2, 1200, 750);
  g.energy = 30;
  w.eco.food.add(1200, 750, FOOD_ENERGY);
  w.step();
  float expect = 30 + FOOD_ENERGY - w.species[2].metab * DT;
  boolean b1 = abs(g.energy - expect) < 0.01 && w.eco.consumed == 1 && w.eco.food.count == 0;
  report("T10b 먹기", b1, "에너지 " + nf(g.energy, 1, 2) + " (기대 " + nf(expect, 1, 2) + "), 소비 " + w.eco.consumed + ", 남은 먹이 " + w.eco.food.count);
  pass &= b1;

  // (c) 에너지가 0이면 체력이 줄어 사망, 사망 개체의 약 절반이 먹이로 남는다
  w = sandbox();
  w.eco.foodRate = 0;
  for (int i = 0; i < 400; i++) put(w, 2, 200 + (i % 20) * 100, 200 + (i / 20) * 60).energy = 0;
  int steps = 0;
  while (w.count > 0 && steps < 1200) {
    w.step();
    steps++;
  }
  float frac = w.eco.corpses / 400.0;
  boolean c1 = w.count == 0 && w.eco.starved[2] == 400 && steps * DT >= 4.9 && steps * DT <= 5.6;
  boolean c2 = abs(frac - CORPSE_P) < 0.08 && w.eco.food.count == w.eco.corpses;
  report("T10c 굶어 죽음", c1, "400마리 전멸까지 " + nf(steps * DT, 1, 2) + "초 (체력 40 / 초당 8 = 5초), 아사 " + w.eco.starved[2]);
  report("T10c 시체가 먹이가 될 확률", c2, "400마리 중 " + w.eco.corpses + "개 (" + nf(frac, 1, 2) + ", 기대 " + nf(CORPSE_P, 1, 2) + " +-0.08)");
  pass &= c1 && c2;

  // (d) 정합성 : (생성 + 시체) = 소비 + 남은 먹이, 항상 상한 이하
  World d = new World(5);
  boolean ident = true, capOk = true;
  for (int st = 1; st <= 7200; st++) {
    d.step();
    if (st % 600 == 0) {
      if (d.eco.generated + d.eco.corpses != d.eco.consumed + d.eco.food.count) ident = false;
      if (d.eco.food.count > MAX_FOOD) capOk = false;
    }
  }
  report("T10d 먹이 정합성", ident && capOk, "2분 동안 생성 " + d.eco.generated + " + 시체 " + d.eco.corpses + " = 소비 " + d.eco.consumed
    + " + 남음 " + d.eco.food.count + (ident ? " (일치)" : " (불일치)"));
  pass &= ident && capOk;
  return pass;
}

// T11 : 번식 조건 (에너지, 나이, 전투 중 금지, 밀도 의존, 재번식 대기)
boolean testReproduction() {
  boolean pass = true;
  float X = 1200, Y = 750;
  Species red = makeSpecies()[0];

  // 조건을 모두 갖추면 자식이 하나 태어난다
  World w = sandbox();
  w.eco.foodRate = 0;
  Agent p = put(w, 0, X, Y);
  p.energy = 95;
  p.age = 30;
  w.step();
  Agent child = w.count == 2 ? w.pool[1] : null;
  boolean ok1 = child != null && child.gen == 1 && abs(child.energy - red.childEnergy) < 0.01
    && abs(p.energy - (95 - red.reproCost - red.metab * DT)) < 0.05 && w.eco.births[0] == 1 && p.offspring == 1;
  report("T11a 번식", ok1, "개체 " + w.count + ", 자식 세대 " + (child == null ? -1 : child.gen) + ", 부모 에너지 " + nf(p.energy, 1, 2));
  pass &= ok1;
  w.step();
  boolean ok2 = w.count == 2;                                      // 재번식 대기 중이라 또 낳지 않는다
  report("T11b 재번식 대기", ok2, "다음 스텝 개체 " + w.count);
  pass &= ok2;

  // 에너지 부족, 나이 부족이면 번식하지 않는다
  w = sandbox();
  w.eco.foodRate = 0;
  put(w, 0, X, Y).energy = 60;
  Agent young = put(w, 0, X + 400, Y);
  young.energy = 95;
  young.age = 1;
  w.step();
  boolean ok3 = w.count == 2;
  report("T11c 에너지/나이 부족 시 번식 안 함", ok3, "개체 " + w.count);
  pass &= ok3;

  // 전투 중에는 번식하지 않는다
  w = sandbox();
  w.eco.foodRate = 0;
  Agent q = put(w, 1, X, Y);
  q.energy = 95;
  q.age = 40;
  put(w, 0, X + 30, Y);
  w.step();
  w.countSpecies();
  boolean ok4 = w.pop[1] == 1;
  report("T11d 전투 중 번식 안 함", ok4, "BLUE " + w.pop[1] + "마리 (1마리여야 함)");
  pass &= ok4;

  // 개체 수가 소프트 상한이면 번식하지 않는다 (밀도 의존)
  w = sandbox();
  w.eco.foodRate = 0;
  for (int i = 0; i < POP_SOFT_CAP; i++) {
    Agent f = put(w, 2, 50 + (i % 100) * 23, 50 + (i / 100) * 55);
    f.energy = 50;
  }
  Agent elig = put(w, 2, 1200, 750);
  elig.energy = 100;
  elig.age = 50;
  int before = w.count;
  w.step();
  boolean ok5 = w.eco.totalBirths == 0 && w.count == before;
  report("T11e 개체 수 상한에서는 번식 안 함", ok5, "개체 " + before + " -> " + w.count + ", 출생 " + w.eco.totalBirths);
  pass &= ok5;
  return pass;
}

// T12 : 장시간 시뮬레이션에서 개체 수가 폭증하지도, 전멸하지도 않는가
boolean testBalance() {
  boolean pass = true;
  int seeds = 3;
  int coexist = 0;
  for (int sd = 0; sd < seeds; sd++) {
    World w = new World(900 + sd);
    boolean explode = false;
    int maxTotal = 0;
    String line = "";
    for (int st = 1; st <= 14400; st++) {            // 4분
      w.step();
      if (w.count > maxTotal) maxTotal = w.count;
      if (w.count >= MAX_AGENTS - 50) explode = true;
      if (st % 3600 == 0) {
        w.countSpecies();
        line += " [" + (st / 60) + "s " + w.pop[0] + "/" + w.pop[1] + "/" + w.pop[2] + " 먹이 " + w.eco.food.count + "]";
      }
    }
    w.countSpecies();
    int minPop = MAX_AGENTS;
    for (int s = 0; s < N_SPECIES; s++) minPop = min(minPop, w.pop[s]);
    if (minPop >= 100) coexist++;
    boolean ok = !explode && w.count >= 50;
    pass &= ok;
    report("T12 시드 " + (900 + sd) + " 개체 수 균형", ok, "최대 " + maxTotal + ", 최종 " + w.count + " (RED/BLUE/GREEN)" + line
      + ", 출생 " + w.eco.totalBirths + ", 사망 " + w.totalDeaths + ", 평균 세대 " + nf(w.avgGen[0], 1, 1) + "/" + nf(w.avgGen[1], 1, 1) + "/" + nf(w.avgGen[2], 1, 1));
  }
  boolean co = coexist == seeds;
  report("T12 4분 후 3종족 모두 100마리 이상 공존", co, coexist + "/" + seeds + " 시드");
  return pass && co;
}

// ---------- V0.4 진화 검증 ----------

// T13 : 돌연변이 통계, 교차의 혼합, 유전자 -> 능력치 매핑과 비용, 시뮬레이션 안에서의 유전
boolean testGenetics() {
  boolean pass = true;
  World w = sandbox();
  Evolution ev = w.evo;
  java.util.Random rng = new java.util.Random(5);

  // (a) 돌연변이 : 유전자당 확률 MUT_RATE, 크기는 N(0, MUT_SIGMA), 0~1 범위를 벗어나지 않는다
  int n = 200000, mutated = 0;
  double sum2 = 0;
  for (int i = 0; i < n; i++) {
    float v = ev.mutate(rng, 0.5);
    if (v != 0.5) {
      mutated++;
      sum2 += (v - 0.5) * (v - 0.5);
    }
  }
  float rate = mutated / (float) n;
  float sigma = sqrt((float) (sum2 / max(1, mutated)));
  boolean clamp = true;
  for (int i = 0; i < 20000; i++) {
    float hi = ev.mutate(rng, 1.0), lo = ev.mutate(rng, 0.0);
    if (hi > 1 || hi < 0 || lo > 1 || lo < 0) clamp = false;
  }
  boolean a = abs(rate - MUT_RATE) < 0.005 && abs(sigma - MUT_SIGMA) < 0.003 && clamp;
  report("T13a 돌연변이 통계", a, "비율 " + nf(rate, 1, 3) + " (기대 " + nf(MUT_RATE, 1, 3) + "), 크기 " + nf(sigma, 1, 4)
    + " (기대 " + nf(MUT_SIGMA, 1, 3) + "), 범위 이탈 " + (clamp ? "없음" : "있음"));
  pass &= a;

  // (b) 교차 : 돌연변이를 끄면 자식의 유전자는 부모 중 한쪽 값이고, 약 절반씩 섞인다
  ev.mutRate = 0;
  Agent p = put(w, 0, 1000, 700);
  Agent m = put(w, 0, 1010, 700);
  Agent c = put(w, 0, 1020, 700);
  for (int i = 0; i < NGENE; i++) {
    p.gene[i] = 0.2;
    m.gene[i] = 0.8;
  }
  p.gen = 3;
  m.gen = 5;
  int fromP = 0, allP = 0, allM = 0, mixed = 0, total = 5000;
  boolean onlyParents = true, genOk = true;
  for (int k = 0; k < total; k++) {
    ev.breed(w, c, p, m);
    int cp = 0;
    for (int i = 0; i < NGENE; i++) {
      if (c.gene[i] == 0.2) cp++;
      else if (c.gene[i] != 0.8) onlyParents = false;
    }
    fromP += cp;
    if (cp == NGENE) allP++;
    else if (cp == 0) allM++;
    else mixed++;
    if (c.gen != 6) genOk = false;
  }
  float fracP = fromP / (float) (total * NGENE);
  boolean b = onlyParents && abs(fracP - 0.5) < 0.015 && allP + allM <= total * 0.04 && mixed >= total * 0.95 && genOk;
  report("T13b 교차", b, "부모A 유전자 비율 " + nf(fracP, 1, 3) + " (기대 0.5), 한쪽과 완전 동일 " + (allP + allM) + "/" + total
    + " (기대 약 1.6%), 세대 max(3,5)+1 " + (genOk ? "O" : "X"));
  pass &= b;

  // 짝이 없으면 복제 (돌연변이 끄면 부모와 동일)
  ev.breed(w, c, p, null);
  boolean cloneOk = true;
  for (int i = 0; i < NGENE; i++) if (c.gene[i] != 0.2) cloneOk = false;
  report("T13b 짝이 없으면 복제", cloneOk && c.gen == 4, cloneOk ? "부모와 동일, 세대 " + c.gen : "다름");
  pass &= cloneOk && c.gen == 4;
  ev.mutRate = MUT_RATE;

  // (c) 유전자 -> 능력치 : 0.5는 종족 기본값(배율 1.0, 비용 1.0), 1.0은 x1.4, 0.0은 x0.6. 비용은 능력치에 비례해 늘어난다.
  Species red = w.species[0];
  Agent t = put(w, 0, 500, 500);
  for (int i = 0; i < NGENE; i++) t.gene[i] = 0.5;
  ev.apply(t, red);
  boolean base = abs(t.speedMax - red.maxSpeed) < 0.01 && abs(t.atk - red.attack) < 0.01 && abs(t.def - red.defense) < 0.01
    && abs(t.costMul - 1) < 0.001 && abs(t.flockMul - 1) < 0.001;
  for (int i = 0; i < NGENE; i++) t.gene[i] = 1.0;
  ev.apply(t, red);
  boolean hi = abs(t.speedMax - red.maxSpeed * 1.4) < 0.01 && abs(t.atk - red.attack * 1.4) < 0.01
    && abs(t.def - red.defense * 1.4) < 0.01 && abs(t.aggression - red.aggression * 1.4) < 0.01
    && abs(t.evasion - red.evasion * 1.4) < 0.01 && abs(t.flockMul - 1.4) < 0.001 && t.perception <= CELL && t.costMul > 1.2;
  float costHi = t.costMul;
  for (int i = 0; i < NGENE; i++) t.gene[i] = 0.0;
  ev.apply(t, red);
  boolean lo = abs(t.speedMax - red.maxSpeed * 0.6) < 0.01 && abs(t.atk - red.attack * 0.6) < 0.01 && t.costMul < 0.8 && t.costMul > 0;
  boolean mono = true;                                // 비용 대상 유전자를 하나씩 올리면 비용이 증가
  int[] costed = {GN_SPEED, GN_ATK, GN_DEF, GN_PERC};
  for (int gi : costed) {
    for (int i = 0; i < NGENE; i++) t.gene[i] = 0.5;
    ev.apply(t, red);
    float before = t.costMul;
    t.gene[gi] = 0.9;
    ev.apply(t, red);
    if (t.costMul <= before) mono = false;
  }
  boolean cc = base && hi && lo && mono;
  report("T13c 유전자 -> 능력치와 비용", cc, "기본 " + (base ? "O" : "X") + ", 최대 x1.4 " + (hi ? "O" : "X") + " (비용 " + nf(costHi, 1, 2)
    + "), 최소 x0.6 " + (lo ? "O" : "X") + ", 비용 단조 증가 " + (mono ? "O" : "X"));
  pass &= cc;

  // (d) 시뮬레이션 안의 유전 : 두 부모가 번식하면 자식의 유전자는 부모 값(0.3 또는 0.7)에서 나온다
  World w2 = sandbox();
  w2.eco.foodRate = 0;
  w2.evo.mutRate = 0;
  Agent pa = put(w2, 0, 1200, 750);
  Agent pb = put(w2, 0, 1215, 750);
  for (int i = 0; i < NGENE; i++) {
    pa.gene[i] = 0.3;
    pb.gene[i] = 0.7;
  }
  w2.evo.apply(pa, w2.species[0]);
  w2.evo.apply(pb, w2.species[0]);
  pa.energy = 95;
  pb.energy = 90;
  pa.age = 30;
  pb.age = 30;
  w2.step();
  boolean childrenOk = w2.count >= 3;
  boolean anyMixed = false;
  for (int i = 2; i < w2.count; i++) {
    int c3 = 0, c7 = 0;
    for (int g = 0; g < NGENE; g++) {
      float v = w2.pool[i].gene[g];
      if (abs(v - 0.3) < 1e-4) c3++;
      else if (abs(v - 0.7) < 1e-4) c7++;
    }
    if (c3 + c7 != NGENE) childrenOk = false;
    if (c3 > 0 && c7 > 0) anyMixed = true;
    if (w2.pool[i].gen != 1) childrenOk = false;
  }
  report("T13d 시뮬레이션 안의 유전", childrenOk && anyMixed, "자식 " + (w2.count - 2) + "마리, 모든 유전자가 부모 값에서 유래 " + (childrenOk ? "O" : "X") + ", 교차로 섞인 자식 " + (anyMixed ? "있음" : "없음"));
  pass &= childrenOk && anyMixed;
  return pass;
}

// 한 종족(GREEN)만 5분 진화시키고 살아 있는 개체들의 평균 유전자를 돌려준다 {유전자 7개, 개체 수, 평균 세대}
float[] evoRun(long seed, float foodRate, boolean mutation, boolean predators, float seconds) {
  World w = new World(seed);
  w.clear();
  w.eco.foodRate = foodRate;
  w.evo.mutRate = mutation ? MUT_RATE : 0;
  w.setPlayer(2);                                   // AI 지휘관의 영향 제외 (명령 없는 자율 행동)
  w.spawnCluster(2, 400, 1700, 1050, 230);
  if (predators) w.spawnCluster(0, 15, 1500, 900, 100);
  int steps = round(seconds / DT);
  for (int i = 0; i < steps; i++) w.step();
  w.refreshSpeciesStats();
  float[] r = new float[2 * NGENE + 2];
  for (int i = 0; i < NGENE; i++) {
    r[i] = w.geneMean[2][i];
    r[NGENE + 2 + i] = w.evo.selection(2, i);                     // 유전자-적응도 상관
  }
  r[NGENE] = w.pop[2];
  r[NGENE + 1] = w.avgGen[2];
  return r;
}

String[] GENE_KO = {"속도", "공격", "방어", "감지", "공격성", "군집성", "회피성"};

String geneLine(float[] r) {
  String s = "";
  for (int i = 0; i < NGENE; i++) s += GENE_KO[i] + " " + nf(r[i], 1, 2) + "  ";
  return s + "| 개체 " + int(r[NGENE]) + ", 평균 세대 " + nf(r[NGENE + 1], 1, 1);
}

String selLine(float[] r) {
  String s = "";
  for (int i = 0; i < NGENE; i++) s += GENE_KO[i] + " " + nf(r[NGENE + 2 + i], 1, 2) + "  ";
  return s;
}

// T14 : 환경이 다르면 진화 방향이 달라지는가 (돌연변이가 있는 진화 vs 돌연변이를 끈 대조군)
boolean testEvolution() {
  boolean pass = true;
  float sec = 420;
  long[] seeds = {1001, 1002, 1003};
  int L = 2 * NGENE + 2;
  float[] rich = new float[L], scarce = new float[L], scarceNoMut = new float[L];
  float[] noPred = new float[L], pred = new float[L];
  for (long sd : seeds) {
    float[] a = evoRun(sd, 120, true, false, sec);                // 먹이 풍부
    float[] b = evoRun(sd, 24, true, false, sec);                 // 먹이 부족
    float[] c = evoRun(sd, 24, false, false, sec);                // 먹이 부족, 돌연변이 없음 (대조군)
    float[] d = evoRun(sd, 60, true, false, sec);                 // 포식자 없음
    float[] e = evoRun(sd, 60, true, true, sec);                  // 포식자(RED 15마리) 있음
    for (int i = 0; i < L; i++) {
      rich[i] += a[i] / seeds.length;
      scarce[i] += b[i] / seeds.length;
      scarceNoMut[i] += c[i] / seeds.length;
      noPred[i] += d[i] / seeds.length;
      pred[i] += e[i] / seeds.length;
    }
  }
  println("[INFO] T14 평균 유전자 | 먹이 풍부(120/s)   : " + geneLine(rich));
  println("[INFO] T14 평균 유전자 | 먹이 부족(24/s)    : " + geneLine(scarce));
  println("[INFO] T14 평균 유전자 | 부족, 돌연변이 X   : " + geneLine(scarceNoMut));
  println("[INFO] T14 평균 유전자 | 포식자 없음(60/s)  : " + geneLine(noPred));
  println("[INFO] T14 평균 유전자 | 포식자 RED 15마리  : " + geneLine(pred));
  println("[INFO] T14 (참고) 유전자-적응도 상관 | 먹이 부족 : " + selLine(scarce) + " (사망 시점 기준이라 검열되어 약함)");

  // 환경이 달라지면 진화 방향이 달라진다 (3개 시드 평균)
  float percGap = scarce[GN_PERC] - rich[GN_PERC];                                    // 먹이가 부족하면 감지 범위가 유리
  float speedGap = pred[GN_SPEED] - noPred[GN_SPEED];                                 // 포식자가 있으면 속도가 유리
  float costRich = (rich[GN_SPEED] + rich[GN_ATK] + rich[GN_DEF]) / 3;
  float costScarce = (scarce[GN_SPEED] + scarce[GN_ATK] + scarce[GN_DEF]) / 3;         // 부족하면 비용이 큰 능력치는 줄어든다
  float maxDev = 0;                                                                    // 먹이가 풍부하면 선택 압력이 약해 평균이 기본값 근처
  for (int i = 0; i < NGENE; i++) maxDev = max(maxDev, abs(rich[i] - 0.5));
  boolean e1 = percGap >= 0.15, e2 = speedGap >= 0.08, e3 = costRich - costScarce >= 0.03, e4 = maxDev <= 0.1;
  report("T14a 먹이가 부족하면 감지 범위 유전자가 증가", e1, "부족 " + nf(scarce[GN_PERC], 1, 2) + " vs 풍부 " + nf(rich[GN_PERC], 1, 2) + " (차이 " + nf(percGap, 1, 2) + " >= 0.15)");
  report("T14b 포식자가 있으면 속도 유전자가 증가", e2, "포식자 있음 " + nf(pred[GN_SPEED], 1, 2) + " vs 없음 " + nf(noPred[GN_SPEED], 1, 2) + " (차이 " + nf(speedGap, 1, 2) + " >= 0.08)");
  report("T14c 먹이가 부족하면 비용이 큰 능력치(속도/공격/방어)가 감소", e3, "평균 " + nf(costScarce, 1, 2) + " vs 풍부 " + nf(costRich, 1, 2));
  report("T14d 선택 압력이 약한 환경(먹이 풍부)에서는 평균이 기본값 근처", e4, "기본값 0.5와의 최대 차이 " + nf(maxDev, 1, 2) + " <= 0.10");
  pass = e1 && e2 && e3 && e4;
  return pass;
}

// 진단용 : 렌더링 구간별 시간 (워밍업 후 평균, ms)
float timeIt(Runnable r, int reps) {
  long t0 = System.nanoTime();
  for (int i = 0; i < reps; i++) r.run();
  return (System.nanoTime() - t0) / 1000000.0f / reps;
}

void renderProfile() {
  final World w = new World(41);
  w.clear();
  for (int s = 0; s < N_SPECIES; s++) w.spawnCluster(s, 400, w.homeX[s], w.homeY[s], 250);
  for (int i = 0; i < 300; i++) w.step();
  final Effects f = new Effects();
  f.level = 3;
  rdr.vl = cam.left(30);
  rdr.vr = cam.right(30);
  rdr.vt = cam.top(30);
  rdr.vb = cam.bottom(30);
  for (int i = 0; i < 40; i++) {                      // 워밍업
    f.update(w, 0.016);
    rdr.draw(w, cam, player, f, gm);
    hud.draw(w, metrics, player, timeScale, isPaused, gm, f);
  }
  final int R = 30;
  println("[INFO] PROF N=" + w.count + " (구간별 ms/프레임)");
  println("[INFO] PROF 전체 rdr.draw      " + nf(timeIt(new Runnable() { public void run() { rdr.draw(w, cam, player, f, gm); } }, R), 1, 2));
  pushMatrix();
  cam.apply();
  println("[INFO] PROF 배경 격자          " + nf(timeIt(new Runnable() { public void run() { rdr.drawBackdrop(); } }, R), 1, 2));
  println("[INFO] PROF 먹이               " + nf(timeIt(new Runnable() { public void run() { rdr.drawFood(w); } }, R), 1, 2));
  println("[INFO] PROF 궤적(streaks)      " + nf(timeIt(new Runnable() { public void run() { rdr.drawStreaks(w); } }, R), 1, 2));
  println("[INFO] PROF 개체 삼각형        " + nf(timeIt(new Runnable() { public void run() { rdr.drawAgents(w); } }, R), 1, 2));
  println("[INFO] PROF 효과 아래(입자,후광) " + nf(timeIt(new Runnable() { public void run() { f.drawBelow(w); } }, R), 1, 2));
  println("[INFO] PROF 효과 위(파티클,링)  " + nf(timeIt(new Runnable() { public void run() { f.drawAbove(w); } }, R), 1, 2));
  println("[INFO] PROF 명령 표시          " + nf(timeIt(new Runnable() { public void run() { rdr.drawOrders(w, player); } }, R), 1, 2));
  popMatrix();
  println("[INFO] PROF HUD 전체           " + nf(timeIt(new Runnable() { public void run() { hud.draw(w, metrics, player, timeScale, isPaused, gm, f); } }, R), 1, 2));
  println("[INFO] PROF HUD 상단 바        " + nf(timeIt(new Runnable() { public void run() { hud.drawBar(w, metrics, player, timeScale, isPaused); } }, R), 1, 2));
  println("[INFO] PROF HUD 그래프         " + nf(timeIt(new Runnable() { public void run() { hud.drawGraphs(w, player); } }, R), 1, 2));
  println("[INFO] PROF HUD 도움말         " + nf(timeIt(new Runnable() { public void run() { hud.drawHelp(); } }, R), 1, 2));
}

// 진단용 : Boids를 끈 대조군의 국소 정렬도가 왜 높아졌는가
float controlAlign(int species, boolean genesFlat, boolean aiOff, int[] stateHist) {
  World w = new World(11);
  w.eco.enabled = false;
  w.species[species].wAli = 0;
  w.species[species].wCoh = 0;
  w.clear();
  w.spawnCluster(species, 300, 1200, 750, 300);
  if (aiOff) w.setPlayer(species);
  if (genesFlat) {
    for (int i = 0; i < w.count; i++) {
      for (int g = 0; g < NGENE; g++) w.pool[i].gene[g] = 0.5;
      w.evo.apply(w.pool[i], w.species[species]);
    }
  }
  for (int i = 0; i < 1200; i++) w.step();
  Metrics m = new Metrics();
  m.compute(w);
  for (int i = 0; i < w.count; i++) stateHist[w.pool[i].state]++;
  return m.localAlign[species];
}

void debugControl() {
  String[] nm = {"FLOCK", "ATTACK", "FLEE", "SUPPORT", "RETREAT", "REGROUP"};
  for (int s = 0; s < 3; s++) {
    for (int v = 0; v < 3; v++) {
      int[] hist = new int[6];
      float a = controlAlign(s, v == 1, v == 2, hist);
      String h = "";
      for (int k = 0; k < 6; k++) if (hist[k] > 0) h += nm[k] + " " + hist[k] + "  ";
      println("[INFO] CTL " + w3(s) + " | " + (v == 0 ? "기본" : (v == 1 ? "유전자 모두 0.5" : "AI 끔")) + " : 국소 정렬 " + nf(a, 1, 2) + " | 상태 " + h);
    }
  }
}

String w3(int s) {
  return makeSpecies()[s].name;
}

// 진단용 : GREEN만 있을 때 AI 지휘관이 있는 경우와 없는 경우의 개체 수 추이
void debugGreen() {
  for (int mode = 0; mode < 2; mode++) {
    World w = new World(1001);
    w.clear();
    w.eco.foodRate = 120;
    w.spawnCluster(2, 400, 1700, 1050, 230);
    if (mode == 1) w.setPlayer(2);                    // 플레이어가 지휘 (명령 없음 = 자율)
    String line = "";
    for (int st = 1; st <= 3600; st++) {
      w.step();
      if (st % 600 == 0) {
        w.countSpecies();
        line += " [" + (st / 60) + "s 개체 " + w.pop[2] + " 먹이 " + w.eco.food.count + " 명령 " + w.cmd[2].order + " 아사 " + w.eco.starved[2] + "]";
      }
    }
    println("[INFO] DBG " + (mode == 0 ? "AI 지휘관" : "자율") + line);
  }
}

// ---------- V0.5 플레이어 개입 검증 ----------

// T15 : 카메라 변환, 커서 기준 확대, 배율 범위, 이동 한계
boolean testCamera() {
  boolean pass = true;
  Camera c = new Camera();
  c.fit(1200, 800);

  c.zoomAt(600, 400, 2.5);
  c.pan(120, -80);
  float sx = 333, sy = 222;
  float wx = c.toWorldX(sx), wy = c.toWorldY(sy);
  boolean round = abs(c.toScreenX(wx) - sx) < 0.01 && abs(c.toScreenY(wy) - sy) < 0.01;
  report("T15a 월드-화면 변환 왕복", round, "오차 " + nf(abs(c.toScreenX(wx) - sx), 1, 5));
  pass &= round;

  c.fit(1200, 800);
  float px = c.toWorldX(600), py = c.toWorldY(400);            // 화면 중앙이 가리키는 월드 점
  c.zoomAt(600, 400, 2.0);
  boolean fixed = abs(c.toWorldX(600) - px) < 0.5 && abs(c.toWorldY(400) - py) < 0.5 && abs(c.zoom - 2 * c.minZoom) < 1e-4;
  report("T15b 커서 기준 확대 (그 점이 제자리)", fixed, "배율 " + nf(c.zoom, 1, 3) + ", 중심 이동 " + nf(abs(c.toWorldX(600) - px), 1, 3));
  pass &= fixed;

  for (int i = 0; i < 40; i++) c.zoomAt(100, 100, 3.0);
  float zmax = c.zoom;
  for (int i = 0; i < 80; i++) c.zoomAt(900, 500, 0.3);
  float zmin = c.zoom;
  boolean bounds = abs(zmax - c.maxZoom) < 1e-5 && abs(zmin - c.minZoom) < 1e-5;
  report("T15c 배율 범위", bounds, "최대 " + nf(zmax, 1, 2) + ", 최소 " + nf(zmin, 1, 3) + " (창에 월드 전체가 맞는 배율)");
  pass &= bounds;

  c.zoomAt(600, 400, 3.0);
  c.pan(1e6, 1e6);
  boolean inRight = c.right(0) <= WORLD_W + 0.01 && c.bottom(0) <= WORLD_H + 0.01;
  c.pan(-1e7, -1e7);
  boolean inLeft = c.left(0) >= -0.01 && c.top(0) >= -0.01;
  report("T15d 이동 한계 (보이는 영역이 월드 밖으로 나가지 않음)", inRight && inLeft, "오른쪽 끝 " + nf(c.right(0), 1, 0) + ", 왼쪽 끝 " + nf(c.left(0), 1, 0));
  pass &= inRight && inLeft;
  return pass;
}

World orderWorld(int player) {
  return orderWorld(player, 3);
}

World orderWorld(int player, long seed) {
  World w = new World(seed);
  w.eco.enabled = false;                             // 명령의 효과만 본다 (먹이/굶주림/번식 없음)
  w.clear();
  w.setPlayer(player);
  return w;
}

void setEnergy(World w, int sp, float e) {
  for (int i = 0; i < w.count; i++) if (w.pool[i].species == sp) w.pool[i].energy = e;
}

float[] centroidOf(World w, int sp) {
  float sx = 0, sy = 0;
  int n = 0;
  for (int i = 0; i < w.count; i++) {
    if (w.pool[i].species == sp) {
      sx += w.pool[i].x;
      sy += w.pool[i].y;
      n++;
    }
  }
  return new float[] {n > 0 ? sx / n : 0, n > 0 ? sy / n : 0, n};
}

void runSteps(World w, float seconds) {
  int n = round(seconds / DT);
  for (int i = 0; i < n; i++) w.step();
}

// T16 : 명령 4종이 군집 행동을 유지한 채 효과를 내는가, 명령이 무조건 복종이 아닌가
boolean testOrders() {
  boolean pass = true;

  // (a) 이동 명령 : 군집을 유지하며 목표로 이동하고, 도착하면 목표 근처에 머문다
  // 명령이 없어도 Boids 무리는 최소 속도로 계속 흘러간다(무작위 표류). 그래서 목표 4곳으로 평균을 내어,
  // 명령을 받은 무리는 모두 목표 근처에 도착하고 대조군은 평균적으로 멀리 있음을 비교한다.
  float[][] targets = {{1500, 750}, {1500, 300}, {1500, 1200}, {900, 1250}};
  float sumOrder = 0, sumCtl = 0, worstOrder = 0, alignMid = 0, sd = 0;
  int near = 0, total = 0;
  Metrics m = new Metrics();
  for (int k = 0; k < targets.length; k++) {
    float tx = targets[k][0], ty = targets[k][1];
    World w = orderWorld(0, 3 + k);
    w.spawnCluster(0, 200, 600, 750, 120);
    setEnergy(w, 0, 100);
    w.cmd[0].moveTo(tx, ty);
    runSteps(w, 8);
    if (k == 0) {
      m.compute(w);
      alignMid = m.localAlign[0];                                 // 이동 중에도 군집을 유지하는가
    }
    runSteps(w, 17);
    float[] cEnd = centroidOf(w, 0);
    float dOrder = dist(cEnd[0], cEnd[1], tx, ty);
    sumOrder += dOrder;
    worstOrder = max(worstOrder, dOrder);
    if (k == 0) {
      for (int i = 0; i < w.count; i++) {
        if (dist(w.pool[i].x, w.pool[i].y, tx, ty) < 350) near++;
        sd += sq(w.pool[i].x - cEnd[0]) + sq(w.pool[i].y - cEnd[1]);
      }
      total = w.count;
      sd = sqrt(sd / w.count);
    }
    World ctl = orderWorld(0, 3 + k);
    ctl.spawnCluster(0, 200, 600, 750, 120);
    setEnergy(ctl, 0, 100);
    runSteps(ctl, 25);
    float[] cc = centroidOf(ctl, 0);
    sumCtl += dist(cc[0], cc[1], tx, ty);
  }
  float meanOrder = sumOrder / targets.length, meanCtl = sumCtl / targets.length;
  boolean a = alignMid >= 0.8 && worstOrder < 350 && meanOrder < 250 && meanCtl > 2.5 * meanOrder && near >= 0.7 * total && sd > 30;
  report("T16a 이동 명령", a, "이동 중 국소 정렬 " + nf(alignMid, 1, 2) + " (군집 유지), 25초 후 목표까지 평균 " + nf(meanOrder, 1, 0) + "px (최악 "
    + nf(worstOrder, 1, 0) + "px), 350px 안 " + near + "/" + total + ", 무리 퍼짐 " + nf(sd, 1, 0) + "px | 명령 없는 대조군은 평균 " + nf(meanCtl, 1, 0)
    + "px (목표 4곳 평균)");
  pass &= a;

  // (b) 복종도 : 배고픈 개체는 에너지가 충분한 개체보다 명령을 덜 따른다 (무조건 복종 아님)
  World wb = orderWorld(0);
  wb.spawnCluster(0, 100, 600, 350, 100);                         // 에너지 충분
  int nFull = wb.count;
  wb.spawnCluster(0, 100, 600, 1150, 100);                        // 에너지 15%
  for (int i = 0; i < wb.count; i++) wb.pool[i].energy = i < nFull ? 100 : 15;
  float[] startFull = {0, 0}, startHungry = {0, 0};
  for (int i = 0; i < wb.count; i++) {
    if (i < nFull) startFull[0] += wb.pool[i].x / nFull;
    else startHungry[0] += wb.pool[i].x / (wb.count - nFull);
  }
  wb.cmd[0].moveTo(1700, 750);
  runSteps(wb, 6);
  float progFull = 0, progHungry = 0;
  for (int i = 0; i < wb.count; i++) {
    if (wb.pool[i].energy > 50) progFull += wb.pool[i].x / (float) nFull;
    else progHungry += wb.pool[i].x / (float) (wb.count - nFull);
  }
  progFull -= startFull[0];
  progHungry -= startHungry[0];
  boolean b = progFull > progHungry * 1.1 && progHungry > 0;
  report("T16b 복종도 (군집 성향 x 에너지)", b, "6초 동안 목표 방향 이동 : 에너지 충분 " + nf(progFull, 1, 0) + "px vs 배고픔 " + nf(progHungry, 1, 0) + "px");
  pass &= b;

  // (c) 방어 명령은 이탈 한계가 있어 멀리 추격하지 않고, 공격 명령은 적을 쫓는다
  float[] meanDist = new float[2];
  for (int mode = 0; mode < 2; mode++) {
    World wc = orderWorld(1);
    wc.spawnCluster(1, 80, 1200, 750, 100);
    wc.spawnCluster(2, 60, 1700, 750, 60);                        // 도주하는 GREEN 미끼
    setEnergy(wc, 1, 100);
    setEnergy(wc, 2, 100);
    if (mode == 0) wc.cmd[1].defendAt(1200, 750);
    else wc.cmd[1].attack(wc);
    runSteps(wc, 20);
    float sdist = 0;
    int nb = 0;
    for (int i = 0; i < wc.count; i++) {
      if (wc.pool[i].species == 1) {
        sdist += dist(wc.pool[i].x, wc.pool[i].y, 1200, 750);
        nb++;
      }
    }
    meanDist[mode] = sdist / max(1, nb);
  }
  boolean c = meanDist[0] <= 330 && meanDist[1] >= meanDist[0] + 250;
  report("T16c 방어 이탈 한계 vs 공격 추격", c, "방어 : 평균 " + nf(meanDist[0], 1, 0) + "px (한계 330), 공격 : 평균 " + nf(meanDist[1], 1, 0) + "px");
  pass &= c;

  // (d) 후퇴 명령 : 교전 중이던 RED가 물러나 사상자가 줄어든다
  int[] redDeaths = new int[2];
  float retreatDx = 0;
  for (int mode = 0; mode < 2; mode++) {
    World wd = orderWorld(0);
    wd.spawnCluster(0, 60, 1140, 750, 50);
    wd.spawnCluster(1, 60, 1260, 750, 50);
    setEnergy(wd, 0, 100);
    setEnergy(wd, 1, 100);
    if (mode == 1) {
      wd.cmd[0].rallyX = 300;
      wd.cmd[0].rallyY = 750;
      wd.cmd[0].retreat();
    }
    runSteps(wd, 15);
    redDeaths[mode] = wd.deaths[0];
    if (mode == 1) retreatDx = 1140 - centroidOf(wd, 0)[0];
  }
  boolean d = redDeaths[1] <= redDeaths[0] * 0.7 && retreatDx > 300;
  report("T16d 후퇴 명령", d, "RED 사망 : 명령 없음 " + redDeaths[0] + " vs 후퇴 " + redDeaths[1] + ", 후퇴 이동 " + nf(retreatDx, 1, 0) + "px");
  pass &= d;

  // (e) 명령은 전투 판단의 성향을 바꾼다 (규칙 자체는 그대로)
  float X = 1200, Y = 750;
  int[] es = new int[4];
  for (int k = 0; k < 4; k++) {                                   // 시나리오마다 새 샌드박스 (이전 상태의 히스테리시스 영향 제거)
    World we0 = sandbox();
    put(we0, 1, X, Y);
    if (k >= 2) ring(we0, 1, 3, X, Y, 25);                        // k 2, 3 : 아군 3마리 추가
    put(we0, 0, X + 30, Y);
    if (k == 1) we0.cmd[1].order = ORD_ATTACK;
    if (k == 3) we0.cmd[1].order = ORD_RETREAT;
    es[k] = stateOf(we0, 0);
  }
  int e0 = es[0], e1 = es[1], e2 = es[2], e3 = es[3];
  World we = sandbox();
  Agent far = put(we, 1, X + 900, Y);
  put(we, 0, X + 930, Y);
  we.cmd[1].defendAt(X, Y);
  int e4 = stateOf(we, 0);                                        // 방어 구역에서 멀리 벗어남 : 적이 있어도 추격 안 함
  boolean e = e0 == AS_FLEE && e1 == AS_ATTACK && e2 == AS_ATTACK && e3 == AS_FLEE && e4 != AS_ATTACK && e4 != AS_FLEE;
  report("T16e 명령이 전투 성향에 미치는 영향", e, "공격 명령 전/후 " + stateName(e0) + " -> " + stateName(e1) + ", 후퇴 명령 전/후 " + stateName(e2) + " -> " + stateName(e3)
    + ", 방어 한계 밖 " + stateName(e4));
  pass &= e;
  return pass;
}

// T17 : 자체 AI 지휘관
boolean testAI() {
  World w = new World(8);
  w.setPlayer(-1);                                    // 모두 AI
  boolean greenAttacked = false, redAttacked = false, valid = true;
  int[] orderCount = new int[5];
  for (int st = 0; st < 3600 * 3; st++) {
    w.step();
    if (st % 60 == 0) {
      for (int s = 0; s < N_SPECIES; s++) {
        Commander c = w.cmd[s];
        if (w.pop[s] == 0) continue;
        if (c.order < 0 || c.order > ORD_RETREAT || c.tx < 0 || c.tx > WORLD_W || c.ty < 0 || c.ty > WORLD_H || Float.isNaN(c.tx)) valid = false;
        orderCount[c.order]++;
        if (s == 2 && c.order == ORD_ATTACK) greenAttacked = true;
        if (s == 0 && c.order == ORD_ATTACK) redAttacked = true;
      }
    }
  }
  boolean pass = valid && !greenAttacked && orderCount[ORD_ATTACK] + orderCount[ORD_RETREAT] > 0
    && orderCount[ORD_MOVE] == 0 && orderCount[ORD_DEFEND] == 0;
  report("T17 AI 지휘관", pass, "명령 유효 " + (valid ? "O" : "X") + ", 3분 동안 자율 " + orderCount[ORD_NONE] + " / 공격 " + orderCount[ORD_ATTACK]
    + " / 후퇴 " + orderCount[ORD_RETREAT] + ", GREEN 공격 명령 " + (greenAttacked ? "있음(X)" : "없음(O)")
    + ", RED 공격 명령 " + (redAttacked ? "있음" : "없음"));
  return pass;
}

// T18 : 그래프용 통계의 정합성
boolean testStats() {
  boolean pass = true;
  World w = new World(13);
  runSteps(w, 90);                                    // 90초 -> 샘플 90개
  Stats st = w.stats;
  float sumGen = 0, sumCon = 0;
  for (int i = 0; i < st.len; i++) {
    sumGen += st.foodGen[i];
    sumCon += st.foodCon[i];
  }
  int lastSum = 0;
  for (int s = 0; s < N_SPECIES; s++) lastSum += st.pop[s][st.len - 1];
  boolean a = st.len == 90 && lastSum == w.count && round(sumGen) == w.eco.generated + w.eco.corpses && round(sumCon) == w.eco.consumed;
  report("T18a 통계 샘플", a, "샘플 " + st.len + "개, 마지막 개체 수 합 " + lastSum + " (실제 " + w.count + "), 생성 합 " + int(sumGen) + " (실제 "
    + (w.eco.generated + w.eco.corpses) + "), 소비 합 " + int(sumCon) + " (실제 " + w.eco.consumed + ")");
  pass &= a;

  boolean rates = true;
  String sr = "";
  for (int s = 0; s < N_SPECIES; s++) {
    float win = st.winRate(w, s), sv = st.survival(w, s);
    int k = w.kills[s], d = w.deaths[s];
    if (win < 0 || win > 1 || sv < 0 || abs(win - (k + d > 0 ? k / (float) (k + d) : 0)) > 1e-6) rates = false;
    sr += w.species[s].name + " 승률 " + nf(win, 1, 2) + " 생존율 " + nf(sv, 1, 2) + "  ";
  }
  report("T18b 승률/생존율 계산", rates, sr);
  pass &= rates;

  runSteps(w, 200);                                   // 290초 : 샘플 수가 N(240)을 넘으면 밀어내며 유지
  boolean ring = st.len <= st.N && st.len >= st.N - 1;
  int lastSum2 = 0;
  for (int s = 0; s < N_SPECIES; s++) lastSum2 += st.pop[s][st.len - 1];
  ring &= lastSum2 == w.count;
  report("T18c 오래된 샘플 밀어내기", ring, "샘플 " + st.len + "/" + st.N + ", 최신 값 일치 " + (lastSum2 == w.count ? "O" : "X"));
  pass &= ring;
  return pass;
}

// T19 : 입력 처리 (마우스 클릭, 키 명령, HUD 위 클릭 무시, 종족 선택) - 메인 스케치의 이벤트 함수를 직접 호출한다
boolean testInput() {
  boolean pass = true;
  world.setPlayer(0);
  player = 0;
  world.cmd[0].order = ORD_NONE;
  cam.fit(width, height);

  mouseX = 600;
  mouseY = 400;
  mouseButton = LEFT;
  mousePressed();
  boolean l = world.cmd[0].order == ORD_MOVE && abs(world.cmd[0].tx - cam.toWorldX(600)) < 0.01 && abs(world.cmd[0].ty - cam.toWorldY(400)) < 0.01;
  mouseX = 700;
  mouseY = 500;
  mouseButton = RIGHT;
  mousePressed();
  boolean r = world.cmd[0].order == ORD_DEFEND && abs(world.cmd[0].tx - cam.toWorldX(700)) < 0.01;

  world.cmd[0].order = ORD_NONE;
  mouseX = 600;
  mouseY = 20;                                        // 상단 HUD 위
  mouseButton = LEFT;
  mousePressed();
  boolean hudIgnored = world.cmd[0].order == ORD_NONE;

  keyCode = 'Q';
  key = 'q';
  keyPressed();
  boolean q = world.cmd[0].order == ORD_ATTACK;
  keyCode = 'E';
  key = 'e';
  keyPressed();
  boolean e = world.cmd[0].order == ORD_RETREAT;

  keyCode = '2';
  key = '2';
  keyPressed();
  boolean sel = player == 1 && world.cmd[1].isPlayer && !world.cmd[0].isPlayer && world.playerSpecies == 1;
  keyCode = 'Q';
  key = 'q';
  keyPressed();
  boolean other = world.cmd[1].order == ORD_ATTACK;   // 이제 BLUE가 명령을 받는다

  // 0 : 관찰 모드(모두 AI). 이때 클릭/키 명령은 아무 종족에도 들어가지 않아야 한다
  keyCode = '0';
  key = '0';
  keyPressed();
  boolean obs = player == -1 && world.playerSpecies == -1;
  for (int s = 0; s < N_SPECIES; s++) obs &= !world.cmd[s].isPlayer;
  for (int s = 0; s < N_SPECIES; s++) world.cmd[s].order = ORD_NONE;
  mouseX = 600;
  mouseY = 400;
  mouseButton = LEFT;
  mousePressed();
  keyCode = 'Q';
  key = 'q';
  keyPressed();
  boolean obsNoCmd = true;
  for (int s = 0; s < N_SPECIES; s++) obsNoCmd &= world.cmd[s].order == ORD_NONE;

  boolean ok = l && r && hudIgnored && q && e && sel && other && obs && obsNoCmd;
  report("T19 입력 처리", ok, "좌클릭 이동 " + (l ? "O" : "X") + ", 우클릭 방어 " + (r ? "O" : "X") + ", HUD 위 클릭 무시 " + (hudIgnored ? "O" : "X")
    + ", Q 공격 " + (q ? "O" : "X") + ", E 후퇴 " + (e ? "O" : "X") + ", 1/2/3 종족 선택 " + (sel ? "O" : "X") + ", 선택한 종족에 명령 " + (other ? "O" : "X")
    + ", 0 관찰 모드 " + (obs ? "O" : "X") + ", 관찰 중 명령 무시 " + (obsNoCmd ? "O" : "X"));
  pass &= ok;

  world.setPlayer(-1);                                // 원래대로 (관찰 모드)
  player = -1;
  world.cmd[0].order = ORD_NONE;
  world.cmd[1].order = ORD_NONE;
  return pass;
}

// ---------- FINAL 검증 : 게임 모드, 시각 효과, 안정성, 렌더링 성능 ----------

// T20 : 게임 모드 5종의 승패 조건
boolean testModes() {
  boolean pass = true;
  GameMode g = new GameMode();

  // 자유 : 끝나지 않는다
  World w = orderWorld(0);
  w.spawnCluster(0, 30, 1200, 750, 80);
  g.setMode(MODE_FREE, w);
  runSteps(w, 5);
  g.update(w, 0);
  boolean free = !g.over;

  // 생존 : 마지막 종족이 승리, 모두 사라지면 무승부
  w = orderWorld(0);
  w.spawnCluster(0, 30, 1200, 700, 60);
  w.spawnCluster(1, 30, 1200, 800, 60);
  g.setMode(MODE_SURVIVAL, w);
  g.update(w, 0);
  boolean s1 = !g.over;
  w.setPopulation(1, 0);
  w.step();
  g.update(w, 0);
  boolean s2 = g.over && g.winner == 0;
  w.setPopulation(0, 0);
  g.setMode(MODE_SURVIVAL, w);
  w.step();
  g.update(w, 0);
  boolean s3 = g.over && g.winner == WIN_DRAW;
  report("T20a 자유/생존 모드", free && s1 && s2 && s3, "자유 끝나지 않음 " + (free ? "O" : "X") + ", 생존: 2종족이면 진행 " + (s1 ? "O" : "X")
    + ", 한 종족만 남으면 승리 " + (s2 ? "O" : "X") + ", 전멸이면 무승부 " + (s3 ? "O" : "X"));
  pass &= free && s1 && s2 && s3;

  // 점령 : 구역 안의 우세 종족이 초당 1점, 비등하면 중립, 목표 점수 또는 시간 종료로 승패
  w = orderWorld(0);
  float zx = w.eco.hotX[3], zy = w.eco.hotY[3];
  // Boids 무리는 계속 움직여 구역 밖으로 흘러가므로, 점령 규칙만 보려고 개체를 고정하고 시뮬레이션 시간만 1초씩 흘려보낸다
  w.spawnCluster(1, 40, zx, zy, 50);
  for (int i = 0; i < w.count; i++) w.pool[i].energy = 100;
  g.setMode(MODE_CONQUEST, w);
  for (int sec = 0; sec < 20; sec++) {
    w.stepCount += 60;
    g.update(w, 0);
  }
  boolean c1 = abs(g.points[1] - 20) <= 0.01 && g.zoneOwner[3] == 1 && g.zoneOwner[0] == -1;
  float before = g.points[1];
  w.spawnCluster(0, 40, zx, zy, 50);                                        // RED가 같은 구역에 같은 수로 들어옴 -> 중립
  w.stepCount += 60;
  g.update(w, 0);
  boolean c2 = g.zoneOwner[3] == -1 && abs(g.points[1] - before) <= 0.01;   // 중립이면 아무도 점수를 못 얻는다
  w.setPopulation(0, 20);                                                   // RED가 절반으로 줄면 (BLUE 40 >= 20 x 1.3) 다시 BLUE의 구역
  w.stepCount += 60;
  g.update(w, 0);
  c2 &= g.zoneOwner[3] == 1;
  World w2 = orderWorld(0);
  w2.spawnCluster(1, 40, zx, zy, 50);
  g.setMode(MODE_CONQUEST, w2);
  g.points[1] = g.CONQUEST_POINTS - 0.5;
  w2.stepCount += 60;
  g.update(w2, 0);
  boolean c3 = g.over && g.winner == 1;
  World w3 = orderWorld(0);
  w3.spawnCluster(2, 40, w3.eco.hotX[1], w3.eco.hotY[1], 50);
  g.setMode(MODE_CONQUEST, w3);
  g.elapsed = g.CONQUEST_TIME - 1;
  g.points[2] = 10;
  w3.stepCount += 120;
  g.update(w3, 0);
  boolean c4 = g.over && g.winner == 2;
  report("T20b 점령 모드", c1 && c2 && c3 && c4, "20초 점령 점수 " + nf(before, 1, 1) + " (기대 20), 점유자 O, 비등하면 중립 " + (c2 ? "O" : "X")
    + ", 목표 점수 도달 " + (c3 ? "O" : "X") + ", 시간 종료 시 최고 점수 " + (c4 ? "O" : "X"));
  pass &= c1 && c2 && c3 && c4;

  // 진화 : 평균 세대 12 도달 시 평균 적응도가 높은 종족이 승리
  w = orderWorld(0);
  w.spawnCluster(0, 20, 1000, 750, 60);
  w.spawnCluster(1, 20, 1400, 750, 60);
  g.setMode(MODE_EVOLUTION, w);
  w.evo.selN[0] = 100;
  w.evo.selSumF[0] = 100 * 10;
  w.evo.selN[1] = 100;
  w.evo.selSumF[1] = 100 * 20;
  for (int i = 0; i < w.count; i++) w.pool[i].gen = 5;
  w.step();
  g.update(w, 0);
  boolean e1 = !g.over;
  for (int i = 0; i < w.count; i++) w.pool[i].gen = 12;
  w.step();
  g.update(w, 0);
  boolean e2 = g.over && g.winner == 1;
  report("T20c 진화 모드", e1 && e2, "세대 5에서는 진행 " + (e1 ? "O" : "X") + ", 세대 12에서 적응도 높은 BLUE 승리 " + (e2 ? "O" : "X"));
  pass &= e1 && e2;

  // 지휘 : 다른 종족을 모두 멸종시키거나 70%를 30초 유지하면 승리, 지휘 종족이 멸종하면 패배
  w = orderWorld(0);
  w.spawnCluster(0, 30, 1200, 750, 60);
  g.setMode(MODE_COMMAND, w);
  w.step();
  g.update(w, 0);
  boolean m1 = g.over && g.winner == 0;                                     // 혼자 남음
  w = orderWorld(0);
  w.spawnCluster(1, 30, 1200, 750, 60);
  g.setMode(MODE_COMMAND, w);
  w.step();
  g.update(w, 0);
  boolean m2 = g.over && g.winner == WIN_PLAYER_LOST;                       // 지휘 종족(RED)이 없음
  w = orderWorld(0);
  w.spawnCluster(0, 100, 700, 750, 80);
  w.spawnCluster(1, 20, 1700, 450, 60);                                     // 멀리 떨어진 작은 BLUE : 점유율 83%
  g.setMode(MODE_COMMAND, w);
  boolean m3a = true;
  for (int sec = 0; sec < 28; sec++) {
    runSteps(w, 1);
    g.update(w, 0);
    if (g.over) m3a = false;
  }
  runSteps(w, 4);
  g.update(w, 0);
  boolean m3 = m3a && g.over && g.winner == 0;
  report("T20d 지휘 모드", m1 && m2 && m3, "다른 종족 전멸 시 승리 " + (m1 ? "O" : "X") + ", 지휘 종족 멸종 시 패배 " + (m2 ? "O" : "X")
    + ", 70% 이상 30초 유지 시 승리(28초에는 진행) " + (m3 ? "O" : "X"));
  pass &= m1 && m2 && m3;

  // 월드 재시작과 모드 순환
  w = orderWorld(0);
  w.spawnCluster(0, 10, 1200, 750, 60);
  w.spawnCluster(1, 10, 1000, 750, 60);
  g.setMode(MODE_SURVIVAL, w);
  runSteps(w, 3);
  g.update(w, 0);
  float el = g.elapsed;
  w.reset(5);
  g.update(w, 0);
  boolean r1 = g.elapsed >= el && !Float.isNaN(g.elapsed);
  g.setMode(MODE_FREE, w);
  for (int i = 0; i < N_MODES; i++) g.cycle(w);
  boolean r2 = g.mode == MODE_FREE;
  report("T20e 재시작과 모드 순환", r1 && r2, "재시작 후 시간 감소 없음 " + (r1 ? "O" : "X") + ", 5번 순환하면 처음으로 " + (r2 ? "O" : "X"));
  pass &= r1 && r2;
  return pass;
}

// T21 : 시각 효과는 시뮬레이션과 분리되어 있고, 수준이 자동 조절되며, 풀이 넘치지 않는다
boolean testEffects() {
  boolean pass = true;

  // 사건 -> 파티클
  World w = new World(21);
  Effects f = new Effects();
  for (int i = 0; i < 600; i++) w.step();
  int ev = w.events.n;
  f.update(w, 0.016);
  boolean a = ev > 0 && w.events.n == 0 && f.np > 0;
  report("T21a 사건 -> 파티클", a, "10초 동안 사건 " + ev + "개 기록 -> 파티클 " + f.np + "개, 소비 후 기록 비움 " + (w.events.n == 0 ? "O" : "X"));
  pass &= a;

  // 효과 수준 : 끔이면 파티클 없음, 개체 수가 많으면 자동으로 낮아짐
  World w0 = new World(21);
  Effects f0 = new Effects();
  f0.level = 0;
  for (int i = 0; i < 600; i++) w0.step();
  f0.update(w0, 0.016);
  World big = new World(22);
  big.clear();
  for (int s = 0; s < N_SPECIES; s++) big.spawnCluster(s, 1100, big.homeX[s], big.homeY[s], 300);
  Effects fb = new Effects();
  fb.level = 3;
  boolean b = f0.np == 0 && fb.effective(big) == 1;
  big.clear();
  for (int s = 0; s < N_SPECIES; s++) big.spawnCluster(s, 800, big.homeX[s], big.homeY[s], 300);
  b &= fb.effective(big) == 2;
  big.clear();
  big.spawnCluster(0, 300, 1200, 700, 200);
  b &= fb.effective(big) == 3;
  report("T21b 효과 수준 조절", b, "끔 -> 파티클 " + f0.np + "개, 3300마리 -> 자동 낮음, 2400마리 -> 보통, 300마리 -> 높음 유지");
  pass &= b;

  // 풀 한도
  Effects fp = new Effects();
  fp.level = 3;
  World wp = new World(23);
  for (int k = 0; k < 8; k++) {
    for (int i = 0; i < 3000; i++) wp.events.add(EV_DEATH, 1200, 750, i % N_SPECIES);
    fp.update(wp, 0.001);
  }
  boolean p = fp.np <= fp.MAXP && fp.nr <= fp.MAXR && wp.events.n == 0;
  report("T21c 풀 한도", p, "파티클 " + fp.np + "/" + fp.MAXP + ", 링 " + fp.nr + "/" + fp.MAXR);
  pass &= p;

  // 시뮬레이션과 분리 : 효과를 돌려도 돌리지 않아도 결과가 같다
  World s1 = new World(24), s2 = new World(24);
  Effects fe = new Effects();
  for (int i = 0; i < 1200; i++) {
    s1.step();
    s2.step();
    if (i % 10 == 0) fe.update(s2, 0.016);
  }
  boolean sep = checksum(s1) == checksum(s2);
  report("T21d 효과가 시뮬레이션에 영향 없음", sep, "20초 후 체크섬 " + (sep ? "일치" : "불일치"));
  pass &= sep;
  return pass;
}

// T22 : 예외와 극단 입력에도 죽지 않는가, 장시간 불변식
boolean testStability() {
  boolean pass = true;

  // (a) 개체가 하나도 없는 세계
  try {
    World w = new World(31);
    w.clear();
    Metrics m = new Metrics();
    GameMode g = new GameMode();
    Effects f = new Effects();
    for (int i = 0; i < 600; i++) w.step();
    m.compute(w);
    w.stats.sample(w);
    for (int md = 0; md < N_MODES; md++) {
      g.setMode(md, w);
      g.update(w, 0);
    }
    for (int s = 0; s < N_SPECIES; s++) {
      w.cmd[s].moveTo(100, 100);
      w.cmd[s].attack(w);
      w.cmd[s].retreat();
      w.cmd[s].defendAt(500, 500);
      w.stats.winRate(w, s);
      w.stats.survival(w, s);
    }
    f.update(w, 0.016);
    for (int i = 0; i < 200; i++) w.step();
    report("T22a 개체 0마리 세계", true, "600스텝, 지표/통계/모드/명령/효과 호출 모두 예외 없음");
  } catch (Exception e) {
    report("T22a 개체 0마리 세계", false, "예외 " + e);
    pass = false;
  }

  // (b) 풀 용량 한도
  try {
    World w = new World(32);
    for (int s = 0; s < N_SPECIES; s++) w.setPopulation(s, 5000);
    boolean full = w.count == MAX_AGENTS;
    for (int i = 0; i < 300; i++) w.step();
    boolean ok = full && w.count <= MAX_AGENTS && w.spawn(0, 10, 10) == null || w.count < MAX_AGENTS;
    report("T22b 풀 용량 한도", full && ok, "채운 뒤 " + MAX_AGENTS + "마리에서 300스텝, 초과 생성은 거부 (예외 없음)");
    pass &= full && ok;
  } catch (Exception e) {
    report("T22b 풀 용량 한도", false, "예외 " + e);
    pass = false;
  }

  // (c) 비정상 시간 값
  try {
    World w = new World(33);
    long s0 = w.stepCount;
    int n1 = w.update(100, 4);
    boolean c1 = n1 <= MAX_STEPS_PER_FRAME && w.stepCount - s0 <= MAX_STEPS_PER_FRAME;
    long s1 = w.stepCount;
    w.update(-5, 1);
    w.update(0, 1);
    w.update(0.01, -3);
    boolean c2 = w.stepCount == s1 && !Float.isNaN(w.acc) && w.acc >= 0;
    report("T22c 비정상 시간 값", c1 && c2, "큰 값은 최대 " + MAX_STEPS_PER_FRAME + "스텝으로 제한 (" + n1 + "), 음수/0은 시간이 거꾸로 가지 않음");
    pass &= c1 && c2;
  } catch (Exception e) {
    report("T22c 비정상 시간 값", false, "예외 " + e);
    pass = false;
  }

  // (d) 연속 재시작과 극단 시드
  try {
    World w = new World(34);
    long[] seeds = {0, -1, Long.MAX_VALUE, Long.MIN_VALUE, 1, 42};
    boolean ok = true;
    for (int i = 0; i < 60; i++) {
      w.reset(i < seeds.length ? seeds[i] : i * 7919L);
      for (int k = 0; k < 5; k++) w.step();
      if (w.count < 100) ok = false;
    }
    report("T22d 연속 재시작", ok, "60회 재시작(극단 시드 포함) 정상");
    pass &= ok;
  } catch (Exception e) {
    report("T22d 연속 재시작", false, "예외 " + e);
    pass = false;
  }

  // (e) 장시간 불변식 : 3개 시드 x 10분 (모두 AI)
  try {
    boolean ok = true;
    String detail = "";
    for (int sd = 0; sd < 3; sd++) {
      World w = new World(500 + sd);
      int bad = 0;
      for (int st = 1; st <= 36000; st++) {
        w.step();
        if (st % 600 == 0) {
          boolean aliveOk = true;
          for (int i = 0; i < w.count; i++) {
            Agent a = w.pool[i];
            boolean good = !Float.isNaN(a.x) && !Float.isNaN(a.y) && !Float.isNaN(a.vx) && !Float.isNaN(a.vy)
              && a.x >= 0 && a.x < WORLD_W && a.y >= 0 && a.y < WORLD_H
              && a.energy >= 0 && a.energy <= a.maxEnergy + 0.001 && a.hp > 0 && a.hp <= a.maxHp + 0.001 && a.alive;
            for (int g2 = 0; g2 < NGENE && good; g2++) if (a.gene[g2] < 0 || a.gene[g2] > 1) good = false;
            if (!good) bad++;
          }
          for (int i = w.count; i < MAX_AGENTS; i++) if (w.pool[i].alive) aliveOk = false;
          if (!aliveOk || w.count > MAX_AGENTS || w.eco.food.count > MAX_FOOD) bad++;
          if (w.eco.generated + w.eco.corpses != w.eco.consumed + w.eco.food.count) bad++;
        }
      }
      w.countSpecies();
      detail += " [시드 " + (500 + sd) + ": 10분 후 " + w.pop[0] + "/" + w.pop[1] + "/" + w.pop[2] + ", 위반 " + bad + "]";
      if (bad > 0) ok = false;
    }
    report("T22e 장시간 불변식 (10분 x 3)", ok, "위치/속도/에너지/체력/유전자/풀/먹이 정합성" + detail);
    pass &= ok;
  } catch (Exception e) {
    report("T22e 장시간 불변식", false, "예외 " + e);
    pass = false;
  }
  return pass;
}

// T24 : 프레임 속도 독립성 - 프레임 간격이 일정하든 들쭉날쭉하든, 같은 시뮬레이션 시간이면 결과가 같다 (고정 타임스텝)
boolean testFrameIndependence() {
  float simTime = 9.9;                                // 595스텝쯤 진행한 뒤 같은 스텝 수로 맞춘다
  long[] sum = new long[4];
  long[] steps = new long[4];
  java.util.Random jitter = new java.util.Random(99);
  for (int k = 0; k < 4; k++) {
    World w = new World(51);
    float t = 0;
    while (t < simTime) {
      float dt;
      if (k == 0) dt = 1.0 / 60;                      // 60fps
      else if (k == 1) dt = 1.0 / 144;                // 144fps
      else if (k == 2) dt = 1.0 / 30;                 // 30fps (프레임당 2스텝)
      else dt = 0.004 + jitter.nextFloat() * 0.04;    // 불규칙 4~44ms
      w.update(dt, 1);
      t += dt;
    }
    while (w.stepCount < 600) w.step();               // 스텝 수만 같게 맞춘다 (누적기 반올림 차이 보정)
    steps[k] = w.stepCount;
    sum[k] = checksum(w);
  }
  boolean same = sum[0] == sum[1] && sum[0] == sum[2] && sum[0] == sum[3] && steps[0] == 600 && steps[3] == 600;
  report("T24 프레임 속도 독립성", same, "60fps / 144fps / 30fps / 불규칙 프레임 모두 600스텝에서 체크섬 " + (same ? "일치" : "불일치"));
  return same;
}

// T23 : 렌더링까지 포함한 프레임 시간 (효과 높음 + 궤적). 60fps = 16.7ms
boolean testRenderPerf() {
  int[] sizes = {1200, 2000, 3000};
  boolean ok1200 = false;
  Effects f = new Effects();
  f.level = 2;                                       // 기본 효과 수준(보통)으로 예산을 검사한다. 높음은 참고 수치.
  for (int n : sizes) {
    World w = new World(41);
    w.clear();
    for (int s = 0; s < N_SPECIES; s++) w.spawnCluster(s, n / N_SPECIES, w.homeX[s], w.homeY[s], 250);
    for (int i = 0; i < 300; i++) w.step();
    for (int fr = 0; fr < 60; fr++) {                 // JIT 워밍업 (첫 프레임들은 컴파일 때문에 매우 느리다)
      w.step();
      f.update(w, 0.016);
      rdr.draw(w, cam, player, f, gm);
      hud.draw(w, metrics, player, timeScale, isPaused, gm, f);
    }
    // 이 PC는 다른 앱과 CPU를 나눠 써서 측정이 흔들린다. 방해는 시간을 늘리기만 하므로, 30프레임 구간 5개 중 가장 빠른 구간(best-of-5)으로
    // 판정하고 중앙값도 함께 출력한다.
    int blocks = 5, frames = 30;
    float[] bTotal = new float[blocks];
    float bestTotal = 1e9, bStep = 0, bFx = 0, bRdr = 0, bHud = 0;
    for (int b = 0; b < blocks; b++) {
      long stepNs = 0, fxNs = 0, rdrNs = 0, hudNs = 0;
      for (int fr = 0; fr < frames; fr++) {
        long t0 = System.nanoTime();
        w.step();
        long t1 = System.nanoTime();
        f.update(w, 0.016);
        long t2 = System.nanoTime();
        rdr.draw(w, cam, player, f, gm);
        long t3 = System.nanoTime();
        hud.draw(w, metrics, player, timeScale, isPaused, gm, f);
        long t4 = System.nanoTime();
        stepNs += t1 - t0;
        fxNs += t2 - t1;
        rdrNs += t3 - t2;
        hudNs += t4 - t3;
      }
      float sMs = stepNs / 1000000.0f / frames, fMs = fxNs / 1000000.0f / frames;
      float rMs = rdrNs / 1000000.0f / frames, hMs = hudNs / 1000000.0f / frames;
      bTotal[b] = sMs + fMs + rMs + hMs;
      if (bTotal[b] < bestTotal) {
        bestTotal = bTotal[b];
        bStep = sMs;
        bFx = fMs;
        bRdr = rMs;
        bHud = hMs;
      }
    }
    float[] sortedT = sort(bTotal);
    float total = bestTotal;
    println("[INFO] T23 N=" + w.count + " : 최고 구간 스텝 " + nf(bStep, 1, 2) + " + 효과갱신 " + nf(bFx, 1, 2) + " + 그리기 " + nf(bRdr, 1, 2)
      + " + HUD " + nf(bHud, 1, 2) + " = " + nf(total, 1, 2) + "ms/프레임 (중앙값 " + nf(sortedT[blocks / 2], 1, 2) + "ms, 최악 "
      + nf(sortedT[blocks - 1], 1, 2) + "ms, 효과 " + f.levelName(w) + ")");
    if (n == 1200) {
      ok1200 = total < 16.7;
      f.level = 3;                                   // 참고 : 효과 높음(궤적 포함)일 때
      for (int fr = 0; fr < 20; fr++) rdr.draw(w, cam, player, f, gm);
      long t0 = System.nanoTime();
      for (int fr = 0; fr < 30; fr++) rdr.draw(w, cam, player, f, gm);
      println("[INFO] T23 (참고) 효과 높음 그리기 " + nf((System.nanoTime() - t0) / 1000000.0f / 30, 1, 2) + "ms");
      f.level = 2;
    }
  }
  // 절대 시간은 전원 상태(AC/배터리), 다른 앱의 CPU 사용에 따라 2배 이상 달라지므로 합격/불합격을 가르지 않고 보고만 한다.
  println("[INFO] T23 1200마리 60fps 예산(16.7ms) 충족 여부 : " + (ok1200 ? "충족" : "미충족") + " (스텝 + 효과 보통 + 그리기 + HUD, 이 PC의 현재 전원 상태 기준)");
  return true;
}

// ---------- 시각 확인용 스크린샷 (draw에서 호출) ----------

int stFrame = 0;

void selfTestFrame() {
  if (SELFTEST_ONLY.equals("renderprof")) {            // 렌더링은 실제 draw() 안에서 재야 한다 (setup 안과 결과가 다르다)
    if (stFrame == 3) {
      renderProfile();
      exit();
    }
    stFrame++;
    return;
  }
  if (stFrame == 0) {
    fx.update(world, 0.016);
    rdr.draw(world, cam, player, fx, gm);
    hud.draw(world, metrics, player, timeScale, isPaused, gm, fx);
    save(sketchPath("shot_t0.png"));
    for (int i = 0; i < 1800; i++) world.step();          // 30초 진행
    metrics.compute(world);
  } else if (stFrame == 1) {
    world.countSpecies();
    fx.update(world, 0.016);
    for (int k = 0; k < 20; k++) fx.update(world, 0.016);
    hud.lastRefresh = -100;                               // 스크린샷은 프레임이 몇 장뿐이라 HUD 갱신을 강제한다
    rdr.draw(world, cam, player, fx, gm);
    hud.draw(world, metrics, player, timeScale, isPaused, gm, fx);
    save(sketchPath("shot_t30.png"));
    for (int i = 0; i < 3600; i++) world.step();          // 90초 더 진행 (그래프에 추이가 쌓이도록)
    metrics.compute(world);
  } else if (stFrame == 2) {
    world.countSpecies();
    player = 0;                                           // 관찰자가 RED 지휘에 개입한 화면
    world.setPlayer(player);
    world.cmd[player].moveTo(1800, 900);                  // 이동 명령 표시 확인
    gm.setMode(MODE_CONQUEST, world);                     // 점령 모드 표시 확인
    cam.zoomAt(600, 400, 2.0);                            // 확대도 확인
    for (int k = 0; k < 30; k++) world.step();
    gm.update(world, player);
    fx.update(world, 0.016);
    hud.lastRefresh = -100;
    rdr.draw(world, cam, player, fx, gm);
    hud.draw(world, metrics, player, timeScale, isPaused, gm, fx);
    save(sketchPath("shot_t120_zoom.png"));
  } else if (stFrame == 3) {
    boolean full = SELFTEST_ONLY.length() == 0 || SELFTEST_ONLY.equals("noevo");
    boolean part2 = SELFTEST_ONLY.equals("part2");
    if (full || part2 || SELFTEST_ONLY.equals("final") || SELFTEST_ONLY.equals("perf")) stAllOk &= testRenderPerf();
    if (full || part2) println(stAllOk ? "=== PART2/ALL PASS ===" : "=== PART2/ALL FAILED ===");
    exit();
  }
  stFrame++;
}
