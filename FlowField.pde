// V0.7 Flow Field (공유 경로)
//
// 목표 지점 하나마다 격자(50px)에 '목표까지의 최단 비용'을 한 번 계산하고, 각 칸에 목표 쪽 진행 방향을 저장한다.
// 같은 목표를 향하는 개체/분대는 이 장을 함께 쓴다 (개체마다 길찾기를 하지 않는다).
//  - 장애물(+여유 간격)에 걸린 칸은 막힌 칸이다. 8방향 다익스트라이고 대각선은 모서리를 자르지 않는다.
//  - 개체는 목표로 가는 직선이 장애물에 막혔을 때만 장을 쓴다 (평소 동작은 그대로, 오목한 장애물 앞에서만 길을 돌아간다).
//  - 장은 장애물 배치가 바뀌면(obVer) 버리고, 목표 칸 기준으로 FF_CACHE개를 LRU로 보관한다.
// 난수를 쓰지 않으므로 시드 재현성에 영향이 없다.

final float FF_CELL = 50;                       // 칸 크기
final float FF_CLEAR = 36;                      // 장애물 가장자리에서 띄우는 여유 간격 (개체 크기 + 회피 여유)
final int FF_NX = (int) ceil(WORLD_W / FF_CELL);
final int FF_NY = (int) ceil(WORLD_H / FF_CELL);
final int FF_CACHE = 48;                        // 분대 36개(종족 3 x 12)가 서로 다른 목표를 가질 수 있다

// 힙은 모든 장이 공유한다 (한 번에 하나만 만든다)
int[] ffHeap = new int[FF_NX * FF_NY * 8];
float[] ffHeapKey = new float[FF_NX * FF_NY * 8];
int ffHeapN;

class FlowField {
  float[] cost = new float[FF_NX * FF_NY];
  float[] dx = new float[FF_NX * FF_NY];
  float[] dy = new float[FF_NX * FF_NY];
  boolean[] blocked = new boolean[FF_NX * FF_NY];
  int goal = -1;                                // 실제 목표 칸 (요청 칸이 막혔으면 옮겨진 칸, -1 = 비어 있음)
  int reqCell = -1;                             // 요청된 목표 칸 (캐시 키)
  int ver = -1;                                 // 만들 때의 장애물 버전
  long stamp;                                   // LRU

  void push(int c, float k) {
    int i = ffHeapN++;
    while (i > 0) {
      int p = (i - 1) >> 1;
      if (ffHeapKey[p] <= k) break;
      ffHeap[i] = ffHeap[p];
      ffHeapKey[i] = ffHeapKey[p];
      i = p;
    }
    ffHeap[i] = c;
    ffHeapKey[i] = k;
  }

  int pop() {                                   // 가장 작은 비용의 칸. ffHeapKey[0] 전에 호출자가 비용을 읽는다.
    int top = ffHeap[0];
    ffHeapN--;
    if (ffHeapN > 0) {
      int c = ffHeap[ffHeapN];
      float k = ffHeapKey[ffHeapN];
      int i = 0;
      while (true) {
        int l = i * 2 + 1;
        if (l >= ffHeapN) break;
        int r = l + 1;
        int m = (r < ffHeapN && ffHeapKey[r] < ffHeapKey[l]) ? r : l;
        if (ffHeapKey[m] >= k) break;
        ffHeap[i] = ffHeap[m];
        ffHeapKey[i] = ffHeapKey[m];
        i = m;
      }
      ffHeap[i] = c;
      ffHeapKey[i] = k;
    }
    return top;
  }

  // 목표 (tx, ty)로 가는 장을 만든다. 목표 칸이 막혀 있으면 가장 가까운 열린 칸으로 옮긴다.
  void build(World w, float tx, float ty) {
    int n = FF_NX * FF_NY;
    for (int c = 0; c < n; c++) {
      int cx = c % FF_NX, cy = c / FF_NX;
      float x = (cx + 0.5) * FF_CELL, y = (cy + 0.5) * FF_CELL;
      boolean b = false;
      for (int o = 0; o < w.nObs; o++) {
        float ddx = x - w.obX[o], ddy = y - w.obY[o];
        float rr = w.obR[o] + FF_CLEAR;
        if (ddx * ddx + ddy * ddy < rr * rr) {
          b = true;
          break;
        }
      }
      blocked[c] = b;
      cost[c] = 1e9;
      dx[c] = 0;
      dy[c] = 0;
    }
    int g = cellOf(tx, ty);
    if (blocked[g]) g = nearestOpen(g);
    goal = g;
    ver = w.obVer;
    if (g < 0) return;

    ffHeapN = 0;
    cost[g] = 0;
    push(g, 0);
    while (ffHeapN > 0) {
      float k = ffHeapKey[0];
      int c = pop();
      if (k > cost[c]) continue;                // 낡은 항목
      int cx = c % FF_NX, cy = c / FF_NX;
      for (int oy = -1; oy <= 1; oy++) {
        for (int ox = -1; ox <= 1; ox++) {
          if (ox == 0 && oy == 0) continue;
          int nx = cx + ox, ny = cy + oy;
          if (nx < 0 || ny < 0 || nx >= FF_NX || ny >= FF_NY) continue;
          int m = ny * FF_NX + nx;
          if (blocked[m]) continue;
          if (ox != 0 && oy != 0 && (blocked[cy * FF_NX + nx] || blocked[ny * FF_NX + cx])) continue;   // 모서리 자르기 금지
          float nc = k + (ox != 0 && oy != 0 ? 1.4142 : 1.0);
          if (nc < cost[m]) {
            cost[m] = nc;
            push(m, nc);
          }
        }
      }
    }

    // 방향 : 비용이 가장 낮은 이웃 쪽 (대각선 모서리 규칙 동일)
    for (int c = 0; c < n; c++) {
      if (blocked[c] || cost[c] >= 1e8 || c == g) continue;
      int cx = c % FF_NX, cy = c / FF_NX;
      float best = cost[c];
      float bx = 0, by = 0;
      for (int oy = -1; oy <= 1; oy++) {
        for (int ox = -1; ox <= 1; ox++) {
          if (ox == 0 && oy == 0) continue;
          int nx = cx + ox, ny = cy + oy;
          if (nx < 0 || ny < 0 || nx >= FF_NX || ny >= FF_NY) continue;
          int m = ny * FF_NX + nx;
          if (blocked[m]) continue;
          if (ox != 0 && oy != 0 && (blocked[cy * FF_NX + nx] || blocked[ny * FF_NX + cx])) continue;
          if (cost[m] < best) {
            best = cost[m];
            bx = ox;
            by = oy;
          }
        }
      }
      float l = sqrt(bx * bx + by * by);
      if (l > 0) {
        dx[c] = bx / l;
        dy[c] = by / l;
      }
    }
  }

  int cellOf(float x, float y) {
    int cx = constrain((int) (x / FF_CELL), 0, FF_NX - 1);
    int cy = constrain((int) (y / FF_CELL), 0, FF_NY - 1);
    return cy * FF_NX + cx;
  }

  // 막힌 칸 g에서 가장 가까운 열린 칸 (칸 거리, 없으면 -1). 같은 거리에서는 칸 번호가 작은 쪽 (결정적).
  int nearestOpen(int g) {
    int gx = g % FF_NX, gy = g / FF_NX;
    int best = -1, bestD = Integer.MAX_VALUE;
    for (int c = 0; c < FF_NX * FF_NY; c++) {
      if (blocked[c]) continue;
      int ddx = c % FF_NX - gx, ddy = c / FF_NX - gy;
      int d = ddx * ddx + ddy * ddy;
      if (d < bestD) {
        bestD = d;
        best = c;
      }
    }
    return best;
  }

  // 위치 (x, y)에서 목표로 가는 방향 (결과는 outX, outY). 네 칸 중심의 방향을 이중선형으로 섞되 막힌 칸은 뺀다.
  // 길이 없으면 false.
  float outX, outY;
  boolean sample(float x, float y) {
    float fx = x / FF_CELL - 0.5, fy = y / FF_CELL - 0.5;
    int x0 = (int) floor(fx), y0 = (int) floor(fy);
    float tx = fx - x0, ty = fy - y0;
    float sx = 0, sy = 0, sw = 0;
    for (int j = 0; j < 2; j++) {
      for (int i = 0; i < 2; i++) {
        int cx = constrain(x0 + i, 0, FF_NX - 1), cy = constrain(y0 + j, 0, FF_NY - 1);
        int c = cy * FF_NX + cx;
        if (blocked[c] || cost[c] >= 1e8) continue;
        float wgt = (i == 0 ? 1 - tx : tx) * (j == 0 ? 1 - ty : ty);
        sx += dx[c] * wgt;
        sy += dy[c] * wgt;
        sw += wgt;
      }
    }
    if (sw < 1e-4) {                                         // 네 칸이 다 막힘 (장애물 가장자리 안쪽) : 가장 가까운 칸으로
      int c = cellOf(x, y);
      sx = dx[c];
      sy = dy[c];
    }
    float l = sqrt(sx * sx + sy * sy);
    if (l < 1e-4) return false;
    outX = sx / l;
    outY = sy / l;
    return true;
  }

  // 위치에서 목표까지의 비용 (칸 수). 닿을 수 없으면 큰 값.
  float costAt(float x, float y) {
    return cost[cellOf(x, y)];
  }
}

// 목표별 장 보관소 : 목표 칸이 같으면 재사용, 장애물이 바뀌면 폐기.
class FlowSystem {
  FlowField[] f = new FlowField[FF_CACHE];
  long clock;
  int builds, hits;                             // 검증용
  long uses;                                    // 개체가 장을 따른 횟수 (검증용)
  long nsBuild;

  FlowSystem() {
    for (int i = 0; i < FF_CACHE; i++) f[i] = new FlowField();
  }

  void reset() {
    for (int i = 0; i < FF_CACHE; i++) {
      f[i].goal = -1;
      f[i].reqCell = -1;
      f[i].ver = -1;
    }
    builds = 0;
    hits = 0;
    uses = 0;
    nsBuild = 0;
  }

  FlowField get(World w, float tx, float ty) {
    clock++;
    int g = f[0].cellOf(tx, ty);
    int victim = 0;
    for (int i = 0; i < FF_CACHE; i++) {
      FlowField q = f[i];
      if (q.ver == w.obVer && q.reqCell == g) {
        q.stamp = clock;
        hits++;
        return q;
      }
      if (q.stamp < f[victim].stamp) victim = i;
    }
    FlowField q = f[victim];
    long t0 = System.nanoTime();
    q.build(w, tx, ty);
    nsBuild += System.nanoTime() - t0;
    q.reqCell = g;
    q.stamp = clock;
    builds++;
    return q;
  }
}
