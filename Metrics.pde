// 군집 지표. 군집이 실제로 형성되었는지를 숫자로 확인한다.
//   정렬도(전역) : |Σv| / Σ|v|  (0 = 제각각, 1 = 종족 전체가 같은 방향). 군집이 여러 개면 낮아진다.
//   국소 정렬도 : 각 개체의 속도와 같은 종족 이웃 평균 속도의 코사인 유사도 평균 (군집 내부의 질서)
//   NN     : 같은 종족 최근접 이웃까지의 평균 거리 (작을수록 조밀)
//   군집   : 같은 종족끼리 LINK 거리 안에 이어진 덩어리 중 5마리 이상인 것의 수

class Metrics {
  final float LINK = 45;

  float[] polarization = new float[N_SPECIES];
  float[] localAlign = new float[N_SPECIES];
  float[] meanNN = new float[N_SPECIES];
  int[] clusters = new int[N_SPECIES];
  int[] largest = new int[N_SPECIES];
  int[] isolated = new int[N_SPECIES];

  int[] parent = new int[MAX_AGENTS];
  int[] compSize = new int[MAX_AGENTS];
  float[] sumVx = new float[N_SPECIES];
  float[] sumVy = new float[N_SPECIES];
  float[] sumSp = new float[N_SPECIES];
  float[] sumNN = new float[N_SPECIES];
  int[] cntNN = new int[N_SPECIES];
  float[] sumAlign = new float[N_SPECIES];
  int[] cntAlign = new int[N_SPECIES];

  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  void union(int a, int b) {
    int ra = find(a), rb = find(b);
    if (ra != rb) parent[ra] = rb;
  }

  void compute(World w) {
    Agent[] a = w.pool;
    int n = w.count;
    SpatialGrid g = w.grid;
    g.build(a, n);                  // 위치가 바뀌었을 수 있으니 격자를 새로 만든다

    for (int s = 0; s < N_SPECIES; s++) {
      sumVx[s] = 0;
      sumVy[s] = 0;
      sumSp[s] = 0;
      sumNN[s] = 0;
      cntNN[s] = 0;
      sumAlign[s] = 0;
      cntAlign[s] = 0;
      clusters[s] = 0;
      largest[s] = 0;
      isolated[s] = 0;
    }
    float link2 = LINK * LINK;

    for (int i = 0; i < n; i++) {
      parent[i] = i;
      compSize[i] = 0;
    }

    for (int i = 0; i < n; i++) {
      Agent me = a[i];
      int s = me.species;
      sumVx[s] += me.vx;
      sumVy[s] += me.vy;
      sumSp[s] += sqrt(me.vx * me.vx + me.vy * me.vy);

      float best = 1e18;
      boolean linked = false;
      float nvx = 0, nvy = 0;
      int nn = 0;
      int cx = g.cellX(me.x), cy = g.cellY(me.y);
      for (int gy = max(0, cy - 1); gy <= min(g.rows - 1, cy + 1); gy++) {
        for (int gx = max(0, cx - 1); gx <= min(g.cols - 1, cx + 1); gx++) {
          int c = gy * g.cols + gx;
          for (int k = g.cellStart[c]; k < g.cellStart[c + 1]; k++) {
            int j = g.order[k];
            if (j == i || a[j].species != s) continue;
            float dx = me.x - a[j].x, dy = me.y - a[j].y;
            float d2 = dx * dx + dy * dy;
            if (d2 < best) best = d2;
            if (d2 < link2) {
              union(i, j);
              linked = true;
              nvx += a[j].vx;
              nvy += a[j].vy;
              nn++;
            }
          }
        }
      }
      if (best < 1e17) {
        sumNN[s] += sqrt(best);
        cntNN[s]++;
      }
      if (!linked) isolated[s]++;
      if (nn > 0) {
        float ms = sqrt(nvx * nvx + nvy * nvy);
        float mv = sqrt(me.vx * me.vx + me.vy * me.vy);
        if (ms > 1e-6 && mv > 1e-6) {
          sumAlign[s] += (me.vx * nvx + me.vy * nvy) / (mv * ms);
          cntAlign[s]++;
        }
      }
    }

    for (int i = 0; i < n; i++) compSize[find(i)]++;
    for (int i = 0; i < n; i++) {
      if (parent[i] == i && compSize[i] >= 5) {
        int s = a[i].species;
        clusters[s]++;
        if (compSize[i] > largest[s]) largest[s] = compSize[i];
      }
    }

    for (int s = 0; s < N_SPECIES; s++) {
      polarization[s] = sumSp[s] > 1e-6 ? sqrt(sumVx[s] * sumVx[s] + sumVy[s] * sumVy[s]) / sumSp[s] : 0;
      meanNN[s] = cntNN[s] > 0 ? sumNN[s] / cntNN[s] : 0;
      localAlign[s] = cntAlign[s] > 0 ? sumAlign[s] / cntAlign[s] : 0;
    }
  }
}
