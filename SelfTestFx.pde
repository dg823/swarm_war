// V0.8 전장 효과 검증 (-Only fx)
//   FX1 시뮬레이션 불변   FX2 풀 한도   FX3 공격 방향   FX4 종족별 효과   FX5 그을음 수명   (+ 스크린샷 shot_fx*.png)

boolean testFx() {
  boolean ok = true;
  ok &= testFxSimIndependent();
  ok &= testFxPools();
  ok &= testFxDirection();
  ok &= testFxSpecies();
  ok &= testFxDecals();
  println(ok ? "=== FX PASS ===" : "=== FX FAILED ===");
  return ok;
}

// FX1 : 효과를 최고 수준으로 돌려도 시뮬레이션 결과가 같다
boolean testFxSimIndependent() {
  long[] cs = new long[2];
  int maxT = 0;
  for (int r = 0; r < 2; r++) {
    World w = new World(91);
    Effects e = new Effects();
    e.level = 3;
    for (int i = 0; i < 1800; i++) {             // 30초
      w.step();
      if (r == 1) {
        e.update(w, DT);
        maxT = max(maxT, e.battle.nt);
      } else {
        w.events.clear();
      }
    }
    cs[r] = checksum(w);
  }
  boolean pass = cs[0] == cs[1] && maxT > 0;
  report("FX1 시뮬레이션 불변", pass, "효과 끔/최고 30초 체크섬 " + (cs[0] == cs[1] ? "일치" : "불일치") + ", 동시 투사체 최대 " + maxT);
  return pass;
}

// FX2 : 사건이 넘쳐도 풀 한도를 넘지 않는다
boolean testFxPools() {
  World w = new World(92);
  Effects e = new Effects();
  e.level = 3;
  int maxT = 0, maxW = 0, maxS = 0, maxF = 0, maxP = 0;
  for (int f = 0; f < 120; f++) {
    for (int k = 0; k < 1000; k++) w.events.add(EV_HIT, 1200 + k % 40, 750, k % N_SPECIES, 1180, 740);
    for (int k = 0; k < 1000; k++) w.events.add(EV_DEATH, 1200, 750 + k % 30, k % N_SPECIES);
    e.update(w, DT);
    maxT = max(maxT, e.battle.nt);
    maxW = max(maxW, e.battle.nw);
    maxS = max(maxS, e.battle.ns);
    maxF = max(maxF, e.battle.nf);
    maxP = max(maxP, e.np);
  }
  BattleFx b = e.battle;
  boolean pass = maxT <= b.MAXT && maxW <= b.MAXW && maxS <= b.MAXS && maxF <= b.MAXF && maxP <= e.MAXP && b.nd <= b.MAXD && b.dropped > 0;
  report("FX2 풀 한도", pass, "2초간 프레임당 사건 2000개 : 투사체 " + maxT + "/" + b.MAXT + ", 충격파 " + maxW + "/" + b.MAXW + ", 연기 " + maxS + "/" + b.MAXS
    + ", 섬광 " + maxF + "/" + b.MAXF + ", 파티클 " + maxP + "/" + e.MAXP + ", 그을음 " + b.nd + "/" + b.MAXD + ", 버린 효과 " + b.dropped);
  return pass;
}

// FX3 : 투사체가 공격자에서 피격자로 날아가고, 불꽃이 공격 방향으로 튄다
boolean testFxDirection() {
  World w = new World(93);
  Effects e = new Effects();
  e.level = 3;
  w.events.add(EV_HIT, 1100, 750, 0, 1000, 750);         // 왼쪽 -> 오른쪽
  e.update(w, 0.001);
  boolean spawned = e.battle.nt == 1;
  float midX = lerp(e.battle.tax[0], e.battle.tbx[0], 0.5);
  int np0 = e.np;
  for (int i = 0; i < 10; i++) e.update(w, DT);          // 0.17초 : RED 예광(0.07초)은 도착
  boolean arrived = e.battle.nt == 0;
  int right = 0, tot = 0;
  for (int i = 0; i < e.np; i++) {
    tot++;
    if (e.pvx[i] > 0) right++;
  }
  boolean pass = spawned && arrived && tot > np0 && right == tot && midX > 1000 && midX < 1100;
  report("FX3 공격 방향", pass, "예광 생성 " + (spawned ? "O" : "X") + ", 0.17초 안에 도착 " + (arrived ? "O" : "X") + ", 도착 불꽃 중 공격 방향(+x) " + right + "/" + tot);
  return pass;
}

// FX4 : 종족마다 다른 효과 (사망 충격파 크기, 예광 속도)
boolean testFxSpecies() {
  BattleFx b = new BattleFx();
  float[] r = new float[N_SPECIES], dur = new float[N_SPECIES];
  for (int s = 0; s < N_SPECIES; s++) {
    b.reset();
    b.onDeath(500, 500, s, 3);
    r[s] = b.wr[0];
    b.projectile(0, 0, 10, 0, s);
    dur[s] = b.tdur[0];
  }
  boolean distinct = r[0] != r[1] && r[1] != r[2] && r[0] != r[2] && dur[0] != dur[1] && dur[1] != dur[2];
  b.reset();
  b.onDeath(500, 500, 1, 3);
  boolean blueDouble = b.nw == 2;
  boolean pass = distinct && blueDouble;
  report("FX4 종족별 효과", pass, "사망 충격파 반경 RED " + r[0] + " / BLUE " + r[1] + " / GREEN " + r[2] + ", 예광 시간 " + dur[0] + "/" + dur[1] + "/" + dur[2]
    + ", BLUE 이중 고리 " + (blueDouble ? "O" : "X"));
  return pass;
}

// FX5 : 그을음은 쌓이고 90초에 걸쳐 사라진다 (전장 분위기 변화). 가득 차면 오래된 것부터 덮어쓴다
boolean testFxDecals() {
  BattleFx b = new BattleFx();
  for (int i = 0; i < 10; i++) b.decal(100 + i, 100, 10, color(40, 10, 10));
  boolean added = b.nd == 10;
  for (int i = 0; i < 100; i++) b.update(1, new Effects());
  boolean faded = b.dage[0] >= b.DECAL_LIFE;
  for (int i = 0; i < b.MAXD + 5; i++) b.decal(i, 200, 10, color(40, 10, 10));
  boolean capped = b.nd == b.MAXD && b.dage[4] == 0 && b.dx[4] == b.MAXD - 10 + 4;   // 10개가 이미 있었으므로 295번째 호출(x=294)이 슬롯 4를 덮는다
  boolean pass = added && faded && capped;
  report("FX5 그을음 수명", pass, "쌓임 " + (added ? "O" : "X") + ", 90초 뒤 사라짐 " + (faded ? "O" : "X") + ", 가득 차면 오래된 것부터 덮어씀 " + (capped ? "O" : "X"));
  return pass;
}

// ---------- 스크린샷 (selfTestFrame) : 전투 장면 확대 + 전체 ----------

void fxShots() {
  boolean saved = worldObstacles;
  worldObstacles = true;
  World w = new World(94);
  worldObstacles = saved;
  w.setPlayer(-1);
  fx.level = 3;
  fx.battle.reset();
  float bx = 1200, by = 750;
  int best = 0;
  for (int i = 0; i < 3600; i++) {                     // 60초 진행하며 효과를 쌓는다 (그을음)
    w.step();
    fx.update(w, DT);
    if (i > 3300 && i % 6 == 0) {                      // 마지막 5초 중 전투가 가장 많은 순간을 고른다
      int n = 0;
      float sx = 0, sy = 0;
      for (int k = 0; k < w.count; k++) {
        Agent a = w.pool[k];
        if (a.state == AS_ATTACK) {
          n++;
          sx += a.x;
          sy += a.y;
        }
      }
      if (n > best) {
        best = n;
        bx = sx / n;
        by = sy / n;
      }
    }
  }
  cam.fit(width, height);
  rdr.draw(w, cam, -1, fx, gm);
  save(sketchPath("shot_fx_wide.png"));
  // 전투 지점 확대 : 몇 스텝 더 진행해 예광이 화면에 있도록
  for (int i = 0; i < 4; i++) {
    w.step();
    fx.update(w, DT);
  }
  float px = cam.toScreenX(bx), py = cam.toScreenY(by);
  cam.zoomAt(px, py, 2.6);
  cam.cx = bx;
  cam.cy = by;
  rdr.draw(w, cam, -1, fx, gm);
  save(sketchPath("shot_fx_zoom.png"));
  println("[INFO] FX 스크린샷 : 마지막 5초 최대 교전 " + best + "마리 @ " + round(bx) + "," + round(by) + ", 그을음 " + fx.battle.nd);
}
