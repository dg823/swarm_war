// V0.9 전장 연출 (화면 전용 - 시뮬레이션을 읽기만 한다)
//
//   전장 분석 (5Hz) : 200px 칸마다 종족별 개체 수/이동 방향, 교전 중인 개체가 가장 많은 곳(주요 교전), 오아시스 점령,
//                     최근 10초 처치 수
//   추적 카메라 (C)  : 자유 -> 주요 교전 추적(자동 확대) -> RED/BLUE/GREEN 본대 추적 -> 자유
//   전장 오버레이 (V) : 칸별 우세 종족 색(밀도에 비례), 우세 종족이 바뀌는 경계 = 전선, 오아시스 점령 고리
//   미니맵           : 왼쪽 아래. 클릭하면 그 위치로 이동 (5Hz로 버퍼에 그리고 시야 사각형만 매 프레임)

final int CAM_FREE = 0, CAM_BATTLE = 1, CAM_FOLLOW0 = 2;      // CAM_FOLLOW0 + s : 종족 s 추적
final int LOD_OVERVIEW = 0, LOD_NORMAL = 1, LOD_DETAIL = 2;
final int N_CAM_MODES = 2 + N_SPECIES;
final float VCELL = 200;
final int BIG_BATTLE = 40;                                      // 이 이상 교전하면 '주요 교전'으로 강조

class WarView {
  int cols = ceil(WORLD_W / VCELL), rows = ceil(WORLD_H / VCELL);
  int[][] cnt = new int[N_SPECIES][cols * rows];
  float[][] fvx = new float[N_SPECIES][cols * rows], fvy = new float[N_SPECIES][cols * rows];
  int[] fight = new int[cols * rows];                           // 칸별 교전 개체 수
  int[] owner = new int[cols * rows];                           // 칸별 우세 종족 (-1 비었음)

  // 주요 교전
  float hotX = WORLD_W / 2, hotY = WORLD_H / 2;
  int hotN;                                                     // 주변 3x3칸 교전 개체 수
  int hotA = -1, hotB = -1;                                     // 가장 많이 싸우는 두 종족
  int[] hotSp = new int[N_SPECIES];

  // 오아시스 점령
  final float ZONE_R = 180;
  int[] zoneOwner = new int[7];
  int[] zonesHeld = new int[N_SPECIES];

  // 최근 10초 처치 (1초 표본 원형 버퍼)
  int[][] killHist = new int[N_SPECIES][11];
  int histHead, lastSampleSec = -1;
  int[] fighting = new int[N_SPECIES];

  int camMode = CAM_FREE;
  boolean autoZoom = true;
  boolean overlay = false;
  int tick;

  // ---------- 분석 ----------

  void update(World w) {
    if (tick++ % 12 == 0) analyze(w);
    int sec = (int) (w.stepCount / 60);
    if (sec != lastSampleSec) {                                  // 1초마다 누적 처치 수 기록
      lastSampleSec = sec;
      histHead = (histHead + 1) % 11;
      for (int s = 0; s < N_SPECIES; s++) killHist[s][histHead] = w.kills[s];
    }
  }

  int kills10(int s) {
    int old = killHist[s][(histHead + 1) % 11];
    return max(0, killHist[s][histHead] - old);
  }

  int cell(float x, float y) {
    return constrain((int) (y / VCELL), 0, rows - 1) * cols + constrain((int) (x / VCELL), 0, cols - 1);
  }

  void analyze(World w) {
    for (int s = 0; s < N_SPECIES; s++) {
      java.util.Arrays.fill(cnt[s], 0);
      java.util.Arrays.fill(fvx[s], 0);
      java.util.Arrays.fill(fvy[s], 0);
      fighting[s] = 0;
    }
    java.util.Arrays.fill(fight, 0);
    for (int i = 0; i < w.count; i++) {
      Agent a = w.pool[i];
      int c = cell(a.x, a.y);
      cnt[a.species][c]++;
      fvx[a.species][c] += a.vx;
      fvy[a.species][c] += a.vy;
      if (a.state == AS_ATTACK || a.state == AS_FLEE || a.state == AS_RETREAT) {
        fight[c]++;
        fighting[a.species]++;
      }
    }
    for (int c = 0; c < cols * rows; c++) {
      int best = -1, bn = 0;
      for (int s = 0; s < N_SPECIES; s++) if (cnt[s][c] > bn) {
        bn = cnt[s][c];
        best = s;
      }
      owner[c] = best;
    }

    // 주요 교전 : 3x3칸 교전 개체 합이 가장 큰 곳, 위치는 그 안의 교전 개체 중심
    int bestC = -1, bestN = 0;
    for (int c = 0; c < cols * rows; c++) {
      int cx = c % cols, cy = c / cols, n = 0;
      for (int y = max(0, cy - 1); y <= min(rows - 1, cy + 1); y++)
        for (int x = max(0, cx - 1); x <= min(cols - 1, cx + 1); x++) n += fight[y * cols + x];
      if (n > bestN) {
        bestN = n;
        bestC = c;
      }
    }
    hotN = bestN;
    hotA = -1;
    hotB = -1;
    if (bestC >= 0) {
      int bx = bestC % cols, by = bestC / cols;
      float sx = 0, sy = 0;
      int n = 0;
      java.util.Arrays.fill(hotSp, 0);
      for (int i = 0; i < w.count; i++) {
        Agent a = w.pool[i];
        if (a.state != AS_ATTACK && a.state != AS_FLEE && a.state != AS_RETREAT) continue;
        int cx = constrain((int) (a.x / VCELL), 0, cols - 1), cy = constrain((int) (a.y / VCELL), 0, rows - 1);
        if (abs(cx - bx) > 1 || abs(cy - by) > 1) continue;
        sx += a.x;
        sy += a.y;
        n++;
        hotSp[a.species]++;
      }
      if (n > 0) {
        hotX = sx / n;
        hotY = sy / n;
      }
      for (int s = 0; s < N_SPECIES; s++) {
        if (hotSp[s] == 0) continue;
        if (hotA < 0 || hotSp[s] > hotSp[hotA]) {
          hotB = hotA;
          hotA = s;
        } else if (hotB < 0 || hotSp[s] > hotSp[hotB]) hotB = s;
      }
    }

    // 오아시스 점령 : 반경 180 안에서 8마리 이상이면서 60% 이상인 종족
    java.util.Arrays.fill(zonesHeld, 0);
    int[] zc = hotSp;                                             // 작업 배열 재사용 (위에서 다 썼다)
    for (int z = 0; z < zoneOwner.length; z++) {
      java.util.Arrays.fill(zc, 0);
      int tot = 0;
      for (int i = 0; i < w.count; i++) {
        Agent a = w.pool[i];
        float dx = a.x - w.eco.hotX[z], dy = a.y - w.eco.hotY[z];
        if (dx * dx + dy * dy < ZONE_R * ZONE_R) {
          zc[a.species]++;
          tot++;
        }
      }
      zoneOwner[z] = -1;
      for (int s = 0; s < N_SPECIES; s++) if (zc[s] >= 8 && zc[s] >= tot * 0.6) zoneOwner[z] = s;
      if (zoneOwner[z] >= 0) zonesHeld[zoneOwner[z]]++;
    }
  }

  // ---------- 카메라 ----------

  void cycleCamera() {
    camMode = (camMode + 1) % N_CAM_MODES;
    autoZoom = true;
  }

  String camName() {
    if (camMode == CAM_FREE) return "자유";
    if (camMode == CAM_BATTLE) return "주요 교전 추적";
    return SPECIES_NAMES[camMode - CAM_FOLLOW0] + " 추적";
  }

  // 추적 모드면 목표 쪽으로 부드럽게 이동 (초당 약 2.5배 속도로 다가간다). 주요 교전 모드는 교전이 크면 확대.
  void updateCamera(Camera cam, World w, float dt) {
    if (camMode == CAM_FREE) return;
    float tx, ty, tz = cam.minZoom;
    if (camMode == CAM_BATTLE) {
      if (hotN <= 0) return;
      tx = hotX;
      ty = hotY;
      tz = hotN >= BIG_BATTLE ? cam.minZoom * 2.4 : cam.minZoom * 1.6;
    } else {
      int s = camMode - CAM_FOLLOW0;
      if (w.pop[s] == 0) return;
      tx = w.cx[s];
      ty = w.cy[s];
      tz = cam.minZoom * 1.8;
    }
    float k = min(1, dt * 2.5);
    if (autoZoom) cam.zoom = constrain(cam.zoom + (tz - cam.zoom) * k, cam.minZoom, cam.maxZoom);
    cam.cx += (tx - cam.cx) * k;
    cam.cy += (ty - cam.cy) * k;
    cam.clampCenter();
  }

  // ---------- 월드 위 그리기 ----------

  // 오버레이 : 칸별 우세 종족 색 (밀도에 비례) + 전선 + 오아시스 점령
  void drawOverlay(World w, Renderer r) {
    noStroke();
    for (int c = 0; c < cols * rows; c++) {
      int o = owner[c];
      if (o < 0) continue;
      float x = (c % cols) * VCELL, y = (c / cols) * VCELL;
      if (x + VCELL < r.vl || x > r.vr || y + VCELL < r.vt || y > r.vb) continue;
      float k = min(0.22, cnt[o][c] / 80.0 * 0.22);
      int col = w.species[o].col;
      fill(6 + red(col) * k, 8 + green(col) * k, 14 + blue(col) * k);   // 배경과 섞은 불투명 색
      rect(x, y, VCELL, VCELL);
    }
    // 전선 : 서로 다른 종족이 우세한 칸의 경계
    stroke(255, 225, 120);
    strokeWeight(3);
    for (int c = 0; c < cols * rows; c++) {
      int o = owner[c];
      if (o < 0) continue;
      int cx = c % cols, cy = c / cols;
      float x = cx * VCELL, y = cy * VCELL;
      if (cx + 1 < cols && owner[c + 1] >= 0 && owner[c + 1] != o) line(x + VCELL, y, x + VCELL, y + VCELL);
      if (cy + 1 < rows && owner[c + cols] >= 0 && owner[c + cols] != o) line(x, y + VCELL, x + VCELL, y + VCELL);
    }
    // 오아시스 점령
    noFill();
    strokeWeight(2);
    for (int z = 0; z < zoneOwner.length; z++) {
      int o = zoneOwner[z];
      int col = o >= 0 ? w.species[o].col : color(110);
      stroke(col);
      ellipse(w.eco.hotX[z], w.eco.hotY[z], ZONE_R * 2, ZONE_R * 2);
    }
    strokeWeight(1);
  }

  // 전체 보기의 이동 방향 : 칸별 종족 평균 속도 화살표 (5마리 이상인 칸)
  void drawFlow(World w) {
    strokeWeight(2);
    for (int s = 0; s < N_SPECIES; s++) {
      int col = w.species[s].col;
      stroke(red(col) * 0.75 + 6, green(col) * 0.75 + 8, blue(col) * 0.75 + 14);
      for (int c = 0; c < cols * rows; c++) {
        int n = cnt[s][c];
        if (n < 5) continue;
        float vx = fvx[s][c] / n, vy = fvy[s][c] / n;
        float m = sqrt(vx * vx + vy * vy);
        if (m < 15) continue;
        float L = constrain(m * 0.5, 20, 70) * min(1.6, 0.6 + n / 40.0);
        float ux = vx / m, uy = vy / m;
        float ox = (c % cols + 0.5) * VCELL + (s - 1) * 14, oy = (c / cols + 0.5) * VCELL;
        float ex = ox + ux * L, ey = oy + uy * L;
        line(ox, oy, ex, ey);
        line(ex, ey, ex - ux * 12 - uy * 7, ey - uy * 12 + ux * 7);
        line(ex, ey, ex - ux * 12 + uy * 7, ey - uy * 12 - ux * 7);
      }
    }
    strokeWeight(1);
  }

  // 주요 교전 표시 : 맥동하는 고리
  void drawHotspot() {
    if (hotN < BIG_BATTLE) return;
    float p = 0.5 + 0.5 * sin(frameCount * 0.15);
    noFill();
    stroke(255, 225, 120);
    strokeWeight(2);
    float r = 120 + 30 * p;
    ellipse(hotX, hotY, r * 2, r * 2);
    strokeWeight(1);
  }
}

final String[] SPECIES_NAMES = {"RED", "BLUE", "GREEN"};

// ---------- 미니맵 ----------

class Minimap {
  final float W = 240, H = 150, STAT_H = 62;
  float x0 = 8, y0;                                             // 화면 위치 (왼쪽 아래)
  PGraphics buf;
  int lastFrame = -100;

  void place() {
    y0 = height - 44 - H - STAT_H - 6;
  }

  boolean hits(float mx, float my) {
    place();
    return mx >= x0 && mx <= x0 + W && my >= y0 && my <= y0 + H + STAT_H;
  }

  boolean hitsMap(float mx, float my) {
    place();
    return mx >= x0 && mx <= x0 + W && my >= y0 && my <= y0 + H;
  }

  float toWorldX(float mx) { return (mx - x0) / W * WORLD_W; }
  float toWorldY(float my) { return (my - y0) / H * WORLD_H; }
  float toMiniX(float wx) { return x0 + wx / WORLD_W * W; }
  float toMiniY(float wy) { return y0 + wy / WORLD_H * H; }

  // 미니맵을 클릭하면 그 위치로 카메라를 옮기고 자유 모드로
  void click(float mx, float my, Camera cam, WarView v) {
    cam.cx = toWorldX(mx);
    cam.cy = toWorldY(my);
    cam.clampCenter();
    v.camMode = CAM_FREE;
  }

  void draw(World w, WarView v, Camera cam) {
    place();
    if (buf == null) buf = createGraphics((int) W, (int) (H + STAT_H));
    if (frameCount - lastFrame >= 12) {                          // 5Hz로 다시 그린다 (text가 비싸다)
      lastFrame = frameCount;
      PGraphics saved = g;
      g = buf;
      buf.beginDraw();
      buf.clear();
      buf.textFont(uiFont);
      noStroke();
      fill(8, 10, 16, 235);
      rect(0, 0, W, H + STAT_H, 5);
      float sx = W / WORLD_W, sy = H / WORLD_H;
      fill(30, 33, 40);
      for (int o = 0; o < w.nObs; o++) ellipse(w.obX[o] * sx, w.obY[o] * sy, w.obR[o] * 2 * sx, w.obR[o] * 2 * sy);
      noFill();
      strokeWeight(1);
      for (int z = 0; z < v.zoneOwner.length; z++) {
        int o = v.zoneOwner[z];
        stroke(o >= 0 ? w.species[o].col : color(90));
        ellipse(w.eco.hotX[z] * sx, w.eco.hotY[z] * sy, v.ZONE_R * 2 * sx, v.ZONE_R * 2 * sy);
      }
      strokeWeight(2);
      for (int s = 0; s < N_SPECIES; s++) {
        stroke(w.species[s].col);
        beginShape(POINTS);
        for (int i = 0; i < w.count; i++) {
          Agent a = w.pool[i];
          if (a.species == s) vertex(a.x * sx, a.y * sy);
        }
        endShape();
      }
      if (v.hotN >= BIG_BATTLE) {
        noFill();
        stroke(255, 225, 120);
        strokeWeight(1.5);
        ellipse(v.hotX * sx, v.hotY * sy, 22, 22);
      }
      // 전투 통계 (종족 색 사각형 + 교전 중 개체 / 최근 10초 처치 / 전선 칸 수 / 점령 오아시스)
      textSize(11);
      textAlign(LEFT, TOP);
      noStroke();
      for (int s = 0; s < N_SPECIES; s++) {
        fill(w.species[s].col);
        rect(8, H + 7 + s * 18, 8, 8);
        fill(215);
        text("교전 " + v.fighting[s] + "  10초처치 " + v.kills10(s) + "  전선 " + w.influence.frontCells[s] + "  거점 " + v.zonesHeld[s],
          22, H + 4 + s * 18);
      }
      buf.endDraw();
      g = saved;
    }
    image(buf, x0, y0);
    // 시야 사각형 (매 프레임)
    noFill();
    stroke(255, 200);
    strokeWeight(1);
    float l = max(0, cam.left(0)), r = min(WORLD_W, cam.right(0)), t = max(0, cam.top(0)), b = min(WORLD_H, cam.bottom(0));
    rect(toMiniX(l), toMiniY(t), (r - l) / WORLD_W * W, (b - t) / WORLD_H * H);
  }
}

// 주요 교전 배너 (화면 상단 가운데)
void drawBattleBanner(World w, WarView v) {
  if (v.hotN < BIG_BATTLE || v.hotA < 0) return;
  String t = "주요 교전  " + w.species[v.hotA].name + (v.hotB >= 0 ? " vs " + w.species[v.hotB].name : "") + "  ·  " + v.hotN + "마리";
  textSize(15);
  textAlign(CENTER, TOP);
  float tw = textWidth(t) + 24;
  noStroke();
  fill(0, 150);
  rect(width / 2 - tw / 2, 100, tw, 26, 6);
  fill(255, 225, 120);
  text(t, width / 2, 104);
}
