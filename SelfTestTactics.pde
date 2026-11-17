// V0.7 전술 AI 검증 (-Only tac)
//   TA1 영향력 격자   TA2 계획 선택   TA3 포위   TA4 측면+돌파   TA5 분대 후퇴와 재집결   TA6 재현성/성능

boolean testTactics() {
  boolean ok = true;
  ok &= testInfluence();
  ok &= testPlanChoice();
  ok &= testEncircle();
  ok &= testFlank();
  ok &= testSquadRetreat();
  ok &= testTacCompat();
  println(ok ? "=== TACTICS PASS ===" : "=== TACTICS FAILED ===");
  return ok;
}

// 전술 시험용 월드 : 먹이/번식 없음, 지정한 종족만 AI
World tacWorld(long seed) {
  World w = new World(seed);
  w.eco.enabled = false;
  w.clear();
  w.setPlayer(-1);
  return w;
}

// TA1 : 칸별 개체 수/전투력이 전수 계산과 같다, 전선 칸이 맞닿은 곳에만 생긴다
boolean testInfluence() {
  World w = tacWorld(81);
  w.spawnCluster(0, 200, 500, 500, 150);
  w.spawnCluster(1, 200, 800, 500, 150);
  w.spawnCluster(2, 100, 2000, 1200, 100);
  w.refreshSpeciesStats();
  w.influence.update(w);
  InfluenceMap im = w.influence;
  int bad = 0;
  for (int s = 0; s < N_SPECIES; s++) {
    int tot = 0;
    for (int c = 0; c < im.cols * im.rows; c++) tot += im.cnt[s][c];
    if (tot != w.pop[s]) bad++;
  }
  float p = 0;
  for (int i = 0; i < w.count; i++) if (w.pool[i].species == 0) p += w.pool[i].power;
  float pm = 0;
  for (int c = 0; c < im.cols * im.rows; c++) pm += im.pow[0][c];
  boolean powOk = abs(p - pm) < p * 1e-3;
  boolean front = im.frontCells[0] > 0 && im.frontCells[1] > 0 && im.frontCells[2] == 0;   // GREEN은 떨어져 있다
  boolean pass = bad == 0 && powOk && front;
  report("TA1 영향력 격자", pass, "칸별 개체 수 합 일치 " + (bad == 0 ? "O" : "X") + ", 전투력 합 일치 " + (powOk ? "O" : "X")
    + ", 전선 칸 RED " + im.frontCells[0] + " / BLUE " + im.frontCells[1] + " / GREEN " + im.frontCells[2] + " (GREEN은 0이어야 함)");
  return pass;
}

// TA2 : 계획 선택 규칙
boolean testPlanChoice() {
  boolean a = choosePlan(4, 3.0) == PLAN_ENCIRCLE;
  boolean b = choosePlan(4, 1.2) == PLAN_FLANK;
  boolean c = choosePlan(2, 5.0) == PLAN_FOCUS;
  boolean pass = a && b && c;
  report("TA2 계획 선택", pass, "분대 4 + 3배 우세 -> 포위 " + (a ? "O" : "X") + ", 분대 4 + 1.2배 -> 측면 " + (b ? "O" : "X") + ", 분대 2 -> 집중 " + (c ? "O" : "X"));
  return pass;
}

// 종족 s의 분대들이 점(x, y) 둘레를 얼마나 감싸는가 : 반경 600 안 분대가 차지한 45도 구간 수
int sectorsAround(World w, int s, float x, float y) {
  boolean[] sec = new boolean[8];
  int n = 0;
  for (int j = 0; j < w.squads.k[s]; j++) {
    Squad q = w.squads.sq[s * SQUAD_STRIDE + j];
    if (q.n == 0 || dist(q.cx, q.cy, x, y) > 600) continue;
    int k = ((int) floor((atan2(q.cy - y, q.cx - x) + PI) / (TWO_PI / 8))) % 8;
    if (!sec[k]) n++;
    sec[k] = true;
  }
  return n;
}

// TA3 : 크게 유리하면 포위 - RED 분대가 GREEN 무리의 여러 방향으로 돌아 들어간다
boolean testEncircle() {
  World w = tacWorld(82);
  w.spawnCluster(0, 300, 500, 750, 160);       // RED 300 (분대 5)
  w.spawnCluster(2, 90, 1500, 750, 90);        // GREEN 90
  w.cmd[2].isPlayer = true;                    // GREEN은 명령 없이 자율 (도망은 친다)
  w.cmd[1].isPlayer = true;
  int bestSec = 0, planSeen = 0;
  for (int i = 0; i < 900; i++) {              // 15초
    w.step();
    if (w.tactics.plan[0] == PLAN_ENCIRCLE) planSeen++;
    if (i % 30 == 0 && w.pop[2] > 10) {
      w.refreshSpeciesStats();
      bestSec = max(bestSec, sectorsAround(w, 0, w.cx[2], w.cy[2]));
    }
  }
  w.countSpecies();
  boolean pass = planSeen > 60 && bestSec >= 4;
  report("TA3 포위", pass, "포위 계획 " + nf(planSeen / 60.0, 1, 1) + "초, RED 분대가 GREEN 둘레 8방위 중 최대 " + bestSec + "곳 차지 (기준 4), 15초 뒤 GREEN " + w.pop[2] + "/90");
  return pass;
}

// TA4 : 비등한 상대에게는 측면 + 돌파 - 양 끝 분대가 측면으로 벌어지고 가운데는 약한 지점으로
boolean testFlank() {
  World w = tacWorld(83);
  w.spawnCluster(0, 280, 600, 750, 160);       // RED 280 (분대 4) : BLUE 상대 유효 전력비 약 1 (포위할 만큼은 아님)
  w.spawnCluster(1, 200, 1700, 750, 140);      // BLUE 200
  w.cmd[1].isPlayer = true;                    // BLUE는 자율
  w.cmd[2].isPlayer = true;
  int planSeen = 0, flankRoles = 0, breachRoles = 0;
  float maxSpread = 0;
  for (int i = 0; i < 600; i++) {              // 10초
    w.step();
    if (w.tactics.plan[0] == PLAN_FLANK) planSeen++;
    if (i % 12 == 0) {
      for (int j = 0; j < w.squads.k[0]; j++) {
        Squad q = w.squads.sq[j];
        if (q.role == ROLE_FLANK) flankRoles++;
        if (q.role == ROLE_BREACH) breachRoles++;
      }
      // RED 분대들의 진행 축 수직(세로) 퍼짐 (측면으로 벌어졌는가)
      float lo = 1e9, hi = -1e9;
      for (int j = 0; j < w.squads.k[0]; j++) {
        Squad q = w.squads.sq[j];
        lo = min(lo, q.cy);
        hi = max(hi, q.cy);
      }
      if (w.squads.k[0] > 0) maxSpread = max(maxSpread, hi - lo);
    }
  }
  boolean pass = planSeen > 60 && flankRoles > 0 && breachRoles > 0 && maxSpread > 450;
  report("TA4 측면 + 돌파", pass, "RED 측면 계획 " + nf(planSeen / 60.0, 1, 1) + "초, 측면 역할 " + flankRoles + " / 돌파 역할 " + breachRoles
    + ", 분대 간 최대 세로 폭 " + round(maxSpread) + "px (기준 450)");
  return pass;
}

// TA5 : 불리한 분대만 물러났다 재집결 - 전술이 없을 때보다 덜 잃는다
boolean testSquadRetreat() {
  int[] left = new int[2];
  int rets = 0, regs = 0;
  for (int mode = 0; mode < 2; mode++) {
    World w = tacWorld(84);
    w.spawnCluster(0, 210, 900, 750, 140);     // RED 210 (분대 3), GREEN을 노린다
    w.spawnCluster(2, 60, 1500, 600, 70);
    w.spawnCluster(1, 260, 1500, 950, 120);    // 그 옆에 BLUE 대군 (RED의 천적)
    w.cmd[1].isPlayer = true;
    w.cmd[2].isPlayer = true;
    if (mode == 0) {                           // 비교군 : 전술 없이 RED에 공격 명령만 고정
      w.cmd[0].isPlayer = true;
      w.cmd[0].formSet = FM_NONE;
      w.cmd[0].order = ORD_ATTACK;
      w.cmd[0].tx = 1500;
      w.cmd[0].ty = 600;
    }
    for (int i = 0; i < 1200; i++) {           // 20초
      w.step();
      if (mode == 1 && SELFTEST_ONLY.equals("tacdbg") && i % 60 == 0) {
        String r = "";
        for (int j = 0; j < w.squads.k[0]; j++) { Squad q = w.squads.sq[j]; r += roleName(q.role) + "/" + q.order + "@" + round(q.cx) + "," + round(q.cy) + " "; }
        println("[DBG] t=" + i / 60 + " RED " + w.pop[0] + " BLUE " + w.pop[1] + " GREEN " + w.pop[2] + " order " + w.cmd[0].order + " eff " + nf(w.cmd[0].lastEff, 1, 2) + " plan " + planName(w.tactics.plan[0]) + " tgt " + round(w.cmd[0].tx) + "," + round(w.cmd[0].ty) + " | " + r);
      }
    }
    w.countSpecies();
    left[mode] = w.pop[0];
    if (mode == 1) {
      rets = w.tactics.retreats;
      regs = w.tactics.regroups;
    }
  }
  boolean pass = left[1] > left[0] && (rets > 0 || regs > 0);
  report("TA5 불리하면 후퇴 후 재집결", pass, "RED 210 -> 20초 뒤 전술 AI " + left[1] + " vs 돌격 고정 " + left[0]
    + ", 분대 후퇴 " + rets + "회 / 재집결 " + regs + "회");
  return pass;
}

// TA6 : 장애물 + 전 종족 AI 기본 월드의 재현성, 전술 처리 시간
boolean testTacCompat() {
  boolean saved = worldObstacles;
  worldObstacles = true;
  long[] cs = new long[2];
  float tacMs = 0;
  int[] planSteps = new int[6];
  for (int r = 0; r < 2; r++) {
    World w = new World(85);
    w.setPlayer(-1);
    w.nsTac = 0;
    for (int i = 0; i < 3600; i++) {           // 60초
      w.step();
      if (r == 0) for (int s = 0; s < N_SPECIES; s++) planSteps[w.tactics.plan[s]]++;
    }
    cs[r] = checksum(w);
    if (r == 0) tacMs = w.nsTac / 1e6 / 3600;
  }
  worldObstacles = saved;
  boolean det = cs[0] == cs[1];
  String used = "";
  for (int p = 1; p < 6; p++) used += planName(p) + " " + nf(planSteps[p] / 60.0, 1, 0) + "s ";
  boolean pass = det;
  report("TA6 재현성/성능", pass, "기본 월드 60초 재현성 " + (det ? "O" : "X") + ", 전술 처리 " + nf(tacMs, 1, 3) + "ms/스텝, 계획 사용 시간(종족 합) " + used);
  return pass;
}
