// 시각 효과. 시뮬레이션과 분리되어 있다 : 시뮬레이션은 사건(타격, 사망, 번식)을 EventLog에 기록만 하고,
// 효과는 화면에서 그 기록을 읽어 파티클을 만든다. 효과를 꺼도 시뮬레이션 결과는 같다.
// 개체 수가 많으면 효과 수준이 자동으로 내려가 화면이 복잡해지지 않는다.

final int EV_HIT = 0, EV_DEATH = 1, EV_BIRTH = 2;

class EventLog {
  final int CAP = 2048;
  float[] x = new float[CAP];
  float[] y = new float[CAP];
  int[] type = new int[CAP];
  int[] sp = new int[CAP];
  int n;

  void add(int t, float px, float py, int s) {
    if (n >= CAP) return;                       // 가득 차면 버린다 (장식이라 잃어도 된다)
    x[n] = px;
    y[n] = py;
    type[n] = t;
    sp[n] = s;
    n++;
  }

  void clear() {
    n = 0;
  }
}

class Effects {
  int level = 2;                                // 0 끔, 1 낮음, 2 보통, 3 높음

  // 파티클 풀
  final int MAXP = 2500;
  float[] px = new float[MAXP], py = new float[MAXP], pvx = new float[MAXP], pvy = new float[MAXP];
  float[] plife = new float[MAXP], pmax = new float[MAXP], psize = new float[MAXP];
  int[] pcol = new int[MAXP];
  int np;

  // 확산 링 (번식)
  final int MAXR = 240;
  float[] rx = new float[MAXR], ry = new float[MAXR], rlife = new float[MAXR];
  int[] rcol = new int[MAXR];
  int nr;

  // 군집 중심 후광 (종족마다 가장 큰 무리 2개)
  final int HALOS = 2;
  float[][] haloX = new float[N_SPECIES][HALOS], haloY = new float[N_SPECIES][HALOS], haloN = new float[N_SPECIES][HALOS];
  float[][] haloDX = new float[N_SPECIES][HALOS], haloDY = new float[N_SPECIES][HALOS];
  int ccols = ceil(WORLD_W / 200.0), crows = ceil(WORLD_H / 200.0);
  int[] ccnt = new int[ccols * crows];
  float[] csx = new float[ccols * crows], csy = new float[ccols * crows];
  int haloTick;

  // 배경 입자
  float[] dustX = new float[60], dustY = new float[60], dustV = new float[60];

  Effects() {
    for (int i = 0; i < dustX.length; i++) {
      dustX[i] = random(WORLD_W);
      dustY[i] = random(WORLD_H);
      dustV[i] = random(3, 12);
    }
  }

  void cycleLevel() {
    level = (level + 1) % 4;
  }

  // 개체 수가 많을수록 효과를 줄인다
  int effective(World w) {
    int l = level;
    if (w.count > 3200) l = min(l, 1);
    else if (w.count > 2200) l = min(l, 2);
    return l;
  }

  String levelName(World w) {
    String[] n = {"끔", "낮음", "보통", "높음"};
    int e = effective(w);
    return n[level] + (e != level ? " (자동 " + n[e] + ")" : "");
  }

  void addParticle(float x, float y, float vx, float vy, float life, float size, int col) {
    if (np >= MAXP) return;
    px[np] = x;
    py[np] = y;
    pvx[np] = vx;
    pvy[np] = vy;
    plife[np] = life;
    pmax[np] = life;
    psize[np] = size;
    pcol[np] = col;
    np++;
  }

  // 시뮬레이션이 남긴 사건을 파티클로 바꾸고, 파티클과 후광을 갱신한다. 프레임마다 한 번 호출.
  void update(World w, float dt) {
    int L = effective(w);
    int n = w.events.n;
    if (L > 0 && n > 0) {
      int budget = L == 1 ? 25 : (L == 2 ? 70 : 160);          // 프레임당 처리할 사건 수 (넘치면 건너뛰며 표본 추출)
      int step = max(1, n / budget);
      for (int i = 0; i < n; i += step) spawnFromEvent(w, i, L);
    }
    w.events.clear();

    for (int i = np - 1; i >= 0; i--) {
      plife[i] -= dt;
      if (plife[i] <= 0) {
        np--;
        px[i] = px[np];
        py[i] = py[np];
        pvx[i] = pvx[np];
        pvy[i] = pvy[np];
        plife[i] = plife[np];
        pmax[i] = pmax[np];
        psize[i] = psize[np];
        pcol[i] = pcol[np];
        continue;
      }
      px[i] += pvx[i] * dt;
      py[i] += pvy[i] * dt;
      pvx[i] *= 0.95;
      pvy[i] *= 0.95;
    }
    for (int i = nr - 1; i >= 0; i--) {
      rlife[i] -= dt;
      if (rlife[i] <= 0) {
        nr--;
        rx[i] = rx[nr];
        ry[i] = ry[nr];
        rlife[i] = rlife[nr];
        rcol[i] = rcol[nr];
      }
    }

    if (L >= 2 && ++haloTick >= 20) {
      haloTick = 0;
      findHalos(w);
    }
    for (int s = 0; s < N_SPECIES; s++) {                       // 후광은 부드럽게 따라간다
      for (int h = 0; h < HALOS; h++) {
        haloX[s][h] += (haloDX[s][h] - haloX[s][h]) * min(1, dt * 4);
        haloY[s][h] += (haloDY[s][h] - haloY[s][h]) * min(1, dt * 4);
      }
    }
    for (int i = 0; i < dustX.length; i++) {
      dustY[i] -= dustV[i] * dt;
      if (dustY[i] < 0) {
        dustY[i] = WORLD_H;
        dustX[i] = random(WORLD_W);
      }
    }
  }

  void spawnFromEvent(World w, int i, int L) {
    float x = w.events.x[i], y = w.events.y[i];
    int sp = w.events.sp[i];
    color col = w.species[sp].col;
    int type = w.events.type[i];
    if (type == EV_HIT) {
      int k = L >= 3 ? 4 : 2;
      for (int j = 0; j < k; j++) {
        float a = random(TWO_PI), s = random(60, 160);
        addParticle(x, y, cos(a) * s, sin(a) * s, random(0.15, 0.35), random(2, 3.5), color(255, 240, 200));
      }
    } else if (type == EV_DEATH) {
      int k = L >= 3 ? 8 : 5;
      for (int j = 0; j < k; j++) {
        float a = random(TWO_PI), s = random(40, 140);
        addParticle(x, y, cos(a) * s, sin(a) * s, random(0.4, 0.9), random(2, 5), col);
      }
    } else if (type == EV_BIRTH && nr < MAXR) {
      rx[nr] = x;
      ry[nr] = y;
      rlife[nr] = 0.6;
      rcol[nr] = col;
      nr++;
    }
  }

  // 종족마다 개체가 가장 많이 모인 200px 칸 2곳의 중심
  void findHalos(World w) {
    for (int s = 0; s < N_SPECIES; s++) {
      java.util.Arrays.fill(ccnt, 0);
      java.util.Arrays.fill(csx, 0);
      java.util.Arrays.fill(csy, 0);
      for (int i = 0; i < w.count; i++) {
        Agent a = w.pool[i];
        if (a.species != s) continue;
        int c = constrain((int) (a.y / 200), 0, crows - 1) * ccols + constrain((int) (a.x / 200), 0, ccols - 1);
        ccnt[c]++;
        csx[c] += a.x;
        csy[c] += a.y;
      }
      for (int h = 0; h < HALOS; h++) {
        int best = -1, bn = 25;                                  // 25마리 이상 모인 곳만
        for (int c = 0; c < ccnt.length; c++) {
          if (ccnt[c] > bn) {
            bn = ccnt[c];
            best = c;
          }
        }
        if (best < 0) {
          haloN[s][h] = 0;
          continue;
        }
        if (haloN[s][h] == 0) {                                  // 처음 생기면 제자리에서 시작
          haloX[s][h] = csx[best] / ccnt[best];
          haloY[s][h] = csy[best] / ccnt[best];
        }
        haloDX[s][h] = csx[best] / ccnt[best];
        haloDY[s][h] = csy[best] / ccnt[best];
        haloN[s][h] = ccnt[best];
        ccnt[best] = 0;                                          // 다음 후보를 찾기 위해 제외
      }
    }
  }

  // ---------- 그리기 (월드 좌표계 안에서 호출) ----------

  // 개체 아래 : 배경 입자, 군집 중심 후광
  void drawBelow(World w) {
    int L = effective(w);
    if (L < 2) return;                            // 배경 입자와 군집 후광은 "보통" 이상에서만
    stroke(26, 28, 33);                           // 불투명 (배경과 미리 섞은 색)
    strokeWeight(3);
    beginShape(POINTS);
    for (int i = 0; i < dustX.length; i++) vertex(dustX[i], dustY[i]);
    endShape();
    noFill();
    float pulse = 0.5 + 0.5 * sin(frameCount * 0.05);
    for (int s = 0; s < N_SPECIES; s++) {
      color c = w.species[s].col;
      for (int h = 0; h < HALOS; h++) {
        if (haloN[s][h] <= 0) continue;
        float r = 50 + sqrt(haloN[s][h]) * 9;
        float k = 0.16 + 0.10 * pulse;
        stroke(red(c) * k + 5, green(c) * k + 7, blue(c) * k + 12);      // 불투명 (배경과 미리 섞은 색)
        strokeWeight(2);
        ellipse(haloX[s][h], haloY[s][h], r * 2, r * 2);
        stroke(red(c) * 0.08 + 6, green(c) * 0.08 + 8, blue(c) * 0.08 + 13);
        ellipse(haloX[s][h], haloY[s][h], r * 2.5, r * 2.5);
      }
    }
    strokeWeight(1);
  }

  // 개체 위 : 파티클, 번식 링
  void drawAbove(World w) {
    if (effective(w) == 0) return;
    noStroke();
    for (int i = 0; i < np; i++) {
      float a = 255 * plife[i] / pmax[i];
      fill(red(pcol[i]), green(pcol[i]), blue(pcol[i]), a);
      ellipse(px[i], py[i], psize[i], psize[i]);
    }
    noFill();
    for (int i = 0; i < nr; i++) {
      float t = 1 - rlife[i] / 0.6;
      stroke(red(rcol[i]), green(rcol[i]), blue(rcol[i]), 200 * (1 - t));
      strokeWeight(2);
      ellipse(rx[i], ry[i], 12 + 40 * t, 12 + 40 * t);
    }
    strokeWeight(1);
  }
}
