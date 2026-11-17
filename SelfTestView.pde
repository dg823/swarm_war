// V0.9 전장 연출 검증 (-Only view)
//   VW1 미니맵 좌표/클릭   VW2 주요 교전 탐지   VW3 추적 카메라   VW4 오아시스 점령   VW5 배율별 표현(LOD)   VW6 시뮬레이션 불변
//   (+ 스크린샷 shot_view_*.png)

boolean testView() {
  boolean ok = true;
  ok &= testMinimap();
  ok &= testHotspot();
  ok &= testTrackCamera();
  ok &= testOccupation();
  ok &= testLod();
  ok &= testViewSimIndependent();
  println(ok ? "=== VIEW PASS ===" : "=== VIEW FAILED ===");
  return ok;
}

boolean testMinimap() {
  Minimap m = new Minimap();
  m.place();
  float wx = 1730, wy = 410;
  float rx = m.toWorldX(m.toMiniX(wx)), ry = m.toWorldY(m.toMiniY(wy));
  boolean round = abs(rx - wx) < 0.01 && abs(ry - wy) < 0.01;
  Camera c = new Camera();
  c.fit(width, height);
  c.zoom = c.minZoom * 3;
  WarView v = new WarView();
  v.camMode = CAM_BATTLE;
  m.click(m.toMiniX(600), m.toMiniY(500), c, v);
  boolean moved = abs(c.cx - 600) < 1 && abs(c.cy - 500) < 1 && v.camMode == CAM_FREE;
  boolean inside = m.hits(m.x0 + 10, m.y0 + 10) && !m.hits(m.x0 + m.W + 5, m.y0) && m.hitsMap(m.x0 + 5, m.y0 + 5) && !m.hitsMap(m.x0 + 5, m.y0 + m.H + 10);
  boolean pass = round && moved && inside;
  report("VW1 미니맵", pass, "월드<->미니맵 왕복 " + (round ? "O" : "X") + ", 클릭하면 그 위치로 이동 + 자유 모드 " + (moved ? "O" : "X") + ", 영역 판정 " + (inside ? "O" : "X"));
  return pass;
}

// 교전 월드 : (1600, 500)에서 RED와 GREEN이 맞붙고, BLUE는 멀리 떨어져 있다
World battleWorld() {
  World w = new World(101);
  w.eco.enabled = false;
  w.clear();
  w.setPlayer(-1);
  for (int s = 0; s < N_SPECIES; s++) w.cmd[s].isPlayer = true;      // AI 명령 없이 자율 교전
  w.spawnCluster(0, 150, 1560, 500, 70);
  w.spawnCluster(2, 150, 1660, 500, 70);
  w.spawnCluster(1, 150, 400, 1200, 100);
  return w;
}

boolean testHotspot() {
  World w = battleWorld();
  for (int i = 0; i < 90; i++) w.step();
  WarView v = new WarView();
  v.analyze(w);
  float d = dist(v.hotX, v.hotY, 1610, 500);
  boolean pair = (v.hotA == 0 && v.hotB == 2) || (v.hotA == 2 && v.hotB == 0);
  boolean pass = d < 250 && pair && v.hotN >= BIG_BATTLE;
  report("VW2 주요 교전 탐지", pass, "교전 중심 (" + round(v.hotX) + "," + round(v.hotY) + ") - 실제 (1610,500)에서 " + round(d) + "px, 교전 " + v.hotN + "마리, 종족 "
    + (v.hotA >= 0 ? SPECIES_NAMES[v.hotA] : "-") + " vs " + (v.hotB >= 0 ? SPECIES_NAMES[v.hotB] : "-"));
  return pass;
}

boolean testTrackCamera() {
  World w = battleWorld();
  for (int i = 0; i < 90; i++) w.step();
  WarView v = new WarView();
  v.analyze(w);
  Camera c = new Camera();
  c.fit(width, height);
  v.camMode = CAM_BATTLE;
  for (int i = 0; i < 180; i++) v.updateCamera(c, w, DT);          // 3초
  float d = dist(c.cx, c.cy, v.hotX, v.hotY);
  boolean battle = d < 60 && c.zoom > c.minZoom * 2;
  float battleZoom = c.zoom / c.minZoom;
  // 종족 추적 : BLUE 본대로
  v.camMode = CAM_FOLLOW0 + 1;
  w.refreshSpeciesStats();
  for (int i = 0; i < 180; i++) v.updateCamera(c, w, DT);
  float hw = c.viewW / (2 * c.zoom), hh = c.viewH / (2 * c.zoom);   // BLUE가 구석에 있어 화면이 월드 밖으로 못 나가는 만큼 덜 간다
  float ex = constrain(w.cx[1], hw, WORLD_W - hw), ey = constrain(w.cy[1], hh, WORLD_H - hh);
  float d2 = dist(c.cx, c.cy, ex, ey);
  boolean follow = d2 < 20;
  // 자유 모드는 움직이지 않는다
  v.camMode = CAM_FREE;
  float fx0 = c.cx;
  for (int i = 0; i < 60; i++) v.updateCamera(c, w, DT);
  boolean free = c.cx == fx0;
  boolean pass = battle && follow && free;
  report("VW3 추적 카메라", pass, "주요 교전 추적 3초 뒤 거리 " + round(d) + "px, 배율 x" + nf(battleZoom, 1, 1) + " (전투가 크면 확대)"
    + ", BLUE 추적 (월드 가장자리 보정 위치까지) 거리 " + round(d2) + "px, 자유 모드 고정 " + (free ? "O" : "X"));
  return pass;
}

boolean testOccupation() {
  World w = new World(102);
  w.eco.enabled = false;
  w.clear();
  float[] hx = w.eco.hotX, hy = w.eco.hotY;
  w.spawnCluster(0, 30, hx[0], hy[0], 60);
  w.spawnCluster(1, 30, hx[1], hy[1], 60);
  w.spawnCluster(0, 15, hx[2], hy[2], 60);
  w.spawnCluster(2, 15, hx[2], hy[2], 60);
  w.spawnCluster(2, 4, hx[3], hy[3], 40);
  WarView v = new WarView();
  v.analyze(w);
  boolean pass = v.zoneOwner[0] == 0 && v.zoneOwner[1] == 1 && v.zoneOwner[2] == -1 && v.zoneOwner[3] == -1 && v.zonesHeld[0] == 1;
  report("VW4 오아시스 점령", pass, "RED 단독 -> " + v.zoneOwner[0] + ", BLUE 단독 -> " + v.zoneOwner[1] + ", 반반 -> " + v.zoneOwner[2] + " (중립 -1), 4마리 -> " + v.zoneOwner[3] + " (중립 -1)");
  return pass;
}

boolean testLod() {
  Camera c = new Camera();
  c.fit(width, height);
  boolean a = rdr.lodFor(c) == LOD_OVERVIEW;
  c.zoom = 1.0;
  boolean b = rdr.lodFor(c) == LOD_NORMAL;
  c.zoom = 2.0;
  boolean d = rdr.lodFor(c) == LOD_DETAIL;
  boolean pass = a && b && d;
  report("VW5 배율별 표현", pass, "전체 보기(x" + nf(c.minZoom, 1, 2) + ") -> 방향선+흐름 " + (a ? "O" : "X") + ", x1.0 -> 삼각형 " + (b ? "O" : "X") + ", x2.0 -> 삼각형+체력 막대 " + (d ? "O" : "X"));
  return pass;
}

boolean testViewSimIndependent() {
  long[] cs = new long[2];
  for (int r = 0; r < 2; r++) {
    World w = new World(103);
    WarView v = new WarView();
    Camera c = new Camera();
    c.fit(width, height);
    v.camMode = CAM_BATTLE;
    for (int i = 0; i < 1200; i++) {
      w.step();
      if (r == 1) {
        v.update(w);
        v.updateCamera(c, w, DT);
      }
    }
    cs[r] = checksum(w);
  }
  boolean pass = cs[0] == cs[1];
  report("VW6 시뮬레이션 불변", pass, "전장 분석/카메라를 돌려도 20초 체크섬 " + (pass ? "일치" : "불일치"));
  return pass;
}

// ---------- 스크린샷 (selfTestFrame) ----------

void viewShots() {
  boolean saved = worldObstacles;
  worldObstacles = true;
  World w = new World(104);
  worldObstacles = saved;
  w.setPlayer(-1);
  fx.level = 2;
  fx.battle.reset();
  view = new WarView();
  for (int i = 0; i < 2700; i++) {                    // 45초
    w.step();
    fx.update(w, DT);
    view.update(w);
  }
  view.analyze(w);
  // 1) 전체 보기 + 오버레이 + 미니맵
  cam.fit(width, height);
  view.overlay = true;
  rdr.draw(w, cam, -1, fx, gm);
  hud.lastRefresh = -100;
  hud.draw(w, metrics, -1, 1, false, gm, fx);
  minimap.lastFrame = -100;
  minimap.draw(w, view, cam);
  drawBattleBanner(w, view);
  save(sketchPath("shot_view_overview.png"));
  // 2) 주요 교전 추적 (확대, 체력 막대)
  view.overlay = false;
  view.camMode = CAM_BATTLE;
  for (int i = 0; i < 240; i++) view.updateCamera(cam, w, DT);
  rdr.draw(w, cam, -1, fx, gm);
  hud.lastRefresh = -100;
  hud.draw(w, metrics, -1, 1, false, gm, fx);
  minimap.lastFrame = -100;
  minimap.draw(w, view, cam);
  drawBattleBanner(w, view);
  save(sketchPath("shot_view_battle.png"));
  println("[INFO] VIEW 스크린샷 : 주요 교전 " + view.hotN + "마리 @ " + round(view.hotX) + "," + round(view.hotY) + ", 배율 x" + nf(cam.zoom / cam.minZoom, 1, 1) + " (LOD " + rdr.lodFor(cam) + ")");
}
