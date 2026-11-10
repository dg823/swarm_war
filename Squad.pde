// V0.6 분대. 종족마다 인원에 맞춰 1~12개 분대로 나누고, 분대마다 진형 슬롯을 배정한다.
//
// 갱신 주기
//   매 스텝 : 분대 중심과 평균 속도 (O(n), 슬롯이 분대를 늦지 않게 따라가도록)
//   5Hz     : 분대 수 조정 -> 소속 배정(가장 가까운 중심, k-means 1회 + 히스테리시스) -> 방향 보간
//             -> 슬롯 배정(앞뒤 순으로 줄을 나누고 줄 안은 좌우 순) -> 교전 비율 이동평균
// 난수는 쓰지 않는다 (시드 재현성, RNG 소비량 불변). 할당도 없다 (작업 배열 재사용).

class Squad {
  int species = -1;
  boolean active;
  int form = FM_NONE;
  float blend = 1;                  // 진형 전환 블렌드 (0 -> 1, FORM_BLEND_TIME초)
  float engaged;                    // 교전 비율 이동평균 (0~1)
  float cx, cy;                     // 소속 개체 중심 (매 스텝)
  float vx, vy;                     // 소속 개체 평균 속도 (매 스텝)
  float dirX = 1, dirY = 0;         // 진형 방향 (단위 벡터)
  float tgtX, tgtY;                 // 명령 목표 + 분대 위치 보정
  int n;                            // 소속 인원 (5Hz)
  float gap;                        // 슬롯 간격
  // 매 스텝 누적용
  float sx, sy, svx, svy;
  int cnt;
}

class SquadSystem {
  Squad[] sq = new Squad[MAX_SQUADS];
  int[] k = new int[N_SPECIES];                 // 종족별 활성 분대 수
  long updates;                                 // 5Hz 갱신 횟수 (검증용)

  // 작업 배열 (재사용)
  int[] sqCount = new int[MAX_SQUADS + 1];
  int[] sqStart = new int[MAX_SQUADS + 1];
  int[] byIdx = new int[MAX_AGENTS];            // 분대별로 모은 풀 인덱스
  float[] keyA = new float[MAX_AGENTS];
  float[] su = new float[MAX_AGENTS], sv = new float[MAX_AGENTS];
  int[] slotOrd = new int[MAX_AGENTS];
  int[] memOrd = new int[MAX_AGENTS];
  float[] memU = new float[MAX_AGENTS], memV = new float[MAX_AGENTS];
  float[] seedX = new float[MAX_SQUADS], seedY = new float[MAX_SQUADS];

  SquadSystem() {
    for (int i = 0; i < MAX_SQUADS; i++) sq[i] = new Squad();
  }

  void reset() {
    for (int i = 0; i < MAX_SQUADS; i++) {
      sq[i].active = false;
      sq[i].n = 0;
      sq[i].form = FM_NONE;
      sq[i].blend = 1;
      sq[i].engaged = 0;
      sq[i].dirX = 1;
      sq[i].dirY = 0;
    }
    for (int s = 0; s < N_SPECIES; s++) k[s] = 0;
    updates = 0;
  }

  // 개체가 속한 활성 분대 (없으면 null)
  Squad of(Agent a) {
    if (a.squad < 0) return null;
    Squad q = sq[a.squad];
    return q.active && q.species == a.species ? q : null;
  }

  // 이 개체에 지금 걸리는 진형 강도 (0이면 진형 힘 없음)
  // 배고픈 개체는 대열보다 먹이가 먼저다 : 에너지 50% 이상이면 그대로, 25% 이하면 진형 힘 0
  float strength(Agent a, Squad q) {
    if (q == null || q.form == FM_NONE) return 0;
    float hunger = constrain((a.energy / a.maxEnergy - 0.25) / 0.25, 0, 1);
    return q.blend * (1 - 0.85 * q.engaged) * a.formK * hunger;
  }

  // ---------- 매 스텝 ----------

  void step(World w) {
    if (w.stepCount % SQUAD_PERIOD == 0) assign(w);
    centroids(w);
    for (int i = 0; i < MAX_SQUADS; i++) {
      Squad q = sq[i];
      if (q.active && q.blend < 1) q.blend = min(1, q.blend + DT / FORM_BLEND_TIME);
    }
  }

  void centroids(World w) {
    for (int i = 0; i < MAX_SQUADS; i++) {
      Squad q = sq[i];
      q.sx = 0;
      q.sy = 0;
      q.svx = 0;
      q.svy = 0;
      q.cnt = 0;
    }
    for (int i = 0; i < w.count; i++) {
      Agent a = w.pool[i];
      Squad q = of(a);
      if (q == null) continue;
      q.sx += a.x;
      q.sy += a.y;
      q.svx += a.vx;
      q.svy += a.vy;
      q.cnt++;
    }
    for (int i = 0; i < MAX_SQUADS; i++) {
      Squad q = sq[i];
      if (!q.active || q.cnt == 0) continue;
      q.cx = q.sx / q.cnt;
      q.cy = q.sy / q.cnt;
      q.vx = q.svx / q.cnt;
      q.vy = q.svy / q.cnt;
    }
  }

  // ---------- 5Hz ----------

  void assign(World w) {
    updates++;
    w.countSpecies();
    for (int s = 0; s < N_SPECIES; s++) {
      Commander cm = w.cmd[s];
      int form = cm.resolvedForm();
      if (form == FM_NONE) {                                 // 진형을 쓰지 않으면 분대도 없다 (V0.5와 같은 동작과 비용)
        for (int j = 0; j < k[s]; j++) sq[s * SQUAD_STRIDE + j].active = false;
        k[s] = 0;
        continue;
      }
      adjustCount(w, s);
      assignMembers(w, s);
      Species sp = w.species[s];
      for (int j = 0; j < k[s]; j++) {
        Squad q = sq[s * SQUAD_STRIDE + j];
        if (q.form != form) {
          q.form = form;
          q.blend = 0;                                       // 진형이 바뀌면 2초에 걸쳐 섞는다
        }
        q.gap = sp.sepRadius() * 1.05;
        updateDirection(w, q, cm);
      }
      assignSlots(w, s);
    }
  }

  // 분대 수 = clamp(ceil(인원 / 70), 1, 12). 경계에서 떨리지 않도록 +-8명 여유를 둔다.
  void adjustCount(World w, int s) {
    int pop = w.pop[s];
    int want = constrain(ceil(pop / (float) SQUAD_SIZE), 1, MAX_SQUADS_PER_SPECIES);
    if (pop == 0) want = 0;
    int cur = k[s];
    if (cur > 0 && want > cur && pop <= cur * SQUAD_SIZE + 8) want = cur;
    if (cur > 0 && want < cur && want > 0 && pop >= (cur - 1) * SQUAD_SIZE - 8) want = cur;
    if (want == cur) return;
    for (int j = 0; j < MAX_SQUADS_PER_SPECIES; j++) {
      Squad q = sq[s * SQUAD_STRIDE + j];
      boolean on = j < want;
      if (on && !q.active) {                                 // 새 분대 : 종족 개체를 고르게 건너뛰며 고른 위치에서 시작
        q.active = true;
        q.species = s;
        q.n = 0;
        q.engaged = 0;
        q.blend = 0;
        q.form = FM_NONE;
        seedFromSpread(w, s, j, want, q);
      } else if (!on && q.active) {
        q.active = false;
        q.n = 0;
      }
    }
    k[s] = want;
  }

  // 종족 s의 (j * pop / K)번째 개체 위치를 분대 j의 시작 중심으로 (풀 순서는 시드로 결정되므로 재현된다)
  void seedFromSpread(World w, int s, int j, int K, Squad q) {
    int target = (int) ((long) j * w.pop[s] / max(1, K));
    int seen = 0;
    for (int i = 0; i < w.count; i++) {
      Agent a = w.pool[i];
      if (a.species != s) continue;
      if (seen == target) {
        q.cx = a.x;
        q.cy = a.y;
        q.vx = a.vx;
        q.vy = a.vy;
        float m = sqrt(a.vx * a.vx + a.vy * a.vy);
        if (m > 1e-3) {
          q.dirX = a.vx / m;
          q.dirY = a.vy / m;
        }
        return;
      }
      seen++;
    }
    q.cx = w.homeX[s];
    q.cy = w.homeY[s];
  }

  // 가장 가까운 분대 중심에 배정 (현재 분대가 충분히 가까우면 유지) -> 중심 재계산 (k-means 1회)
  void assignMembers(World w, int s) {
    int base = s * SQUAD_STRIDE, K = k[s];
    if (K == 0) return;
    for (int j = 0; j < K; j++) {
      seedX[base + j] = sq[base + j].cx;
      seedY[base + j] = sq[base + j].cy;
      sq[base + j].sx = 0;
      sq[base + j].sy = 0;
      sq[base + j].n = 0;
    }
    for (int i = 0; i < w.count; i++) {
      Agent a = w.pool[i];
      if (a.species != s) continue;
      int best = -1;
      float bd = 1e18;
      for (int j = 0; j < K; j++) {
        float dx = a.x - seedX[base + j], dy = a.y - seedY[base + j];
        float d2 = dx * dx + dy * dy;
        if (d2 < bd) {
          bd = d2;
          best = base + j;
        }
      }
      int cur = a.squad;
      if (cur >= base && cur < base + K && cur != best) {   // 히스테리시스 : 현재 분대가 1.3배 + 40px 안이면 유지
        float dx = a.x - seedX[cur], dy = a.y - seedY[cur];
        float dc = sqrt(dx * dx + dy * dy);
        if (dc < sqrt(bd) * 1.3 + 40) best = cur;
      }
      if (a.squad != best) {
        a.squad = best;
        a.formK = 0;                                         // 새 분대에서는 진형에 서서히 합류
      }
      Squad q = sq[best];
      q.sx += a.x;
      q.sy += a.y;
      q.n++;
    }
    for (int j = 0; j < K; j++) {
      Squad q = sq[base + j];
      if (q.n > 0) {
        q.cx = q.sx / q.n;
        q.cy = q.sy / q.n;
      }
    }
  }

  // 명령 목표가 있으면 그쪽, 없으면 평균 속도 방향으로 천천히 돌린다
  void updateDirection(World w, Squad q, Commander cm) {
    int s = q.species;
    float ox = q.cx - w.cx[s], oy = q.cy - w.cy[s];          // 종족 중심에 대한 분대 위치 (분대끼리 겹치지 않도록 목표에도 유지)
    float om = sqrt(ox * ox + oy * oy);
    float cap = cm.order == ORD_ATTACK ? 150 : 350;
    if (om > cap) {
      ox *= cap / om;
      oy *= cap / om;
    }
    q.tgtX = constrain(cm.tx + ox, 60, WORLD_W - 60);
    q.tgtY = constrain(cm.ty + oy, 60, WORLD_H - 60);

    float dx = 0, dy = 0;
    if (cm.order != ORD_NONE && cm.order != ORD_DEFEND) {
      dx = q.tgtX - q.cx;
      dy = q.tgtY - q.cy;
      if (dx * dx + dy * dy < 60 * 60) {                     // 거의 도착했으면 방향 유지
        dx = 0;
        dy = 0;
      }
    }
    if (dx == 0 && dy == 0) {
      dx = q.vx;
      dy = q.vy;
      if (dx * dx + dy * dy < 25) return;
    }
    float want = atan2(dy, dx), now = atan2(q.dirY, q.dirX);
    float diff = atan2(sin(want - now), cos(want - now));
    float maxTurn = SQUAD_TURN * SQUAD_PERIOD * DT;
    if (q.blend == 0) maxTurn = PI;                          // 진형을 새로 짤 때는 바로 맞춘다
    float a = now + constrain(diff, -maxTurn, maxTurn);
    q.dirX = cos(a);
    q.dirY = sin(a);
  }

  // 슬롯 배정 : 슬롯과 개체를 각각 앞뒤(u)로 정렬해 줄 단위로 끊고, 줄 안에서 좌우(v) 순으로 짝짓는다
  void assignSlots(World w, int s) {
    int base = s * SQUAD_STRIDE, K = k[s];
    // 분대별로 개체 모으기 (계수 정렬)
    for (int j = 0; j <= K; j++) sqCount[j] = 0;
    for (int i = 0; i < w.count; i++) {
      Agent a = w.pool[i];
      if (a.species == s && a.squad >= base && a.squad < base + K) sqCount[a.squad - base]++;
    }
    sqStart[0] = 0;
    for (int j = 0; j < K; j++) sqStart[j + 1] = sqStart[j] + sqCount[j];
    for (int j = 0; j < K; j++) sqCount[j] = sqStart[j];
    for (int i = 0; i < w.count; i++) {
      Agent a = w.pool[i];
      if (a.species == s && a.squad >= base && a.squad < base + K) byIdx[sqCount[a.squad - base]++] = i;
    }

    for (int j = 0; j < K; j++) {
      Squad q = sq[base + j];
      int st = sqStart[j], n = sqStart[j + 1] - st;
      q.n = n;
      // 교전 비율
      int e = 0;
      for (int m = 0; m < n; m++) {
        int st8 = w.pool[byIdx[st + m]].state;
        if (st8 == AS_ATTACK || st8 == AS_FLEE || st8 == AS_RETREAT) e++;
      }
      float er = n > 0 ? e / (float) n : 0;
      q.engaged = q.engaged * 0.6 + er * 0.4;
      if (n == 0 || q.form == FM_NONE) continue;

      // 슬롯 (평균 0으로 정규화)
      float mu = 0, mv = 0;
      for (int m = 0; m < n; m++) {
        slotLocal(q.form, m, n, q.gap);
        su[m] = fmU;
        sv[m] = fmV;
        mu += fmU;
        mv += fmV;
      }
      mu /= n;
      mv /= n;
      for (int m = 0; m < n; m++) {
        su[m] -= mu;
        sv[m] -= mv;
        slotOrd[m] = m;
        keyA[m] = -su[m];                                    // 앞(u 큰 쪽)부터
      }
      sortIdx(slotOrd, keyA, n);

      // 개체의 분대 좌표
      for (int m = 0; m < n; m++) {
        Agent a = w.pool[byIdx[st + m]];
        float rx = a.x - q.cx, ry = a.y - q.cy;
        memU[m] = rx * q.dirX + ry * q.dirY;
        memV[m] = -rx * q.dirY + ry * q.dirX;
        memOrd[m] = m;
      }
      for (int m = 0; m < n; m++) keyA[m] = -memU[m];
      sortIdx(memOrd, keyA, n);

      // 줄 단위로 끊어 좌우 순으로 짝짓기
      int r0 = 0;
      while (r0 < n) {
        float u0 = su[slotOrd[r0]];
        int r1 = r0 + 1;
        while (r1 < n && u0 - su[slotOrd[r1]] < q.gap) r1++;
        int len = r1 - r0;
        // 이 줄의 슬롯과 개체를 v 순으로
        for (int t = 0; t < len; t++) keyA[t] = sv[slotOrd[r0 + t]];
        sortRange(slotOrd, r0, len, keyA);
        for (int t = 0; t < len; t++) keyA[t] = memV[memOrd[r0 + t]];
        sortRange(memOrd, r0, len, keyA);
        for (int t = 0; t < len; t++) {
          Agent a = w.pool[byIdx[st + memOrd[r0 + t]]];
          int sl = slotOrd[r0 + t];
          a.slotU = su[sl];
          a.slotV = sv[sl];
        }
        r0 = r1;
      }
    }
  }

  // idx[0..n)를 key[idx[i]] 오름차순으로 (삽입 정렬, 안정)
  void sortIdx(int[] idx, float[] key, int n) {
    for (int i = 1; i < n; i++) {
      int v = idx[i];
      float kv = key[v];
      int j = i - 1;
      while (j >= 0 && key[idx[j]] > kv) {
        idx[j + 1] = idx[j];
        j--;
      }
      idx[j + 1] = v;
    }
  }

  // idx[off..off+len)을 key[t] (t = 구간 안 위치) 오름차순으로. key와 idx를 함께 옮긴다.
  void sortRange(int[] idx, int off, int len, float[] key) {
    for (int i = 1; i < len; i++) {
      int v = idx[off + i];
      float kv = key[i];
      int j = i - 1;
      while (j >= 0 && key[j] > kv) {
        idx[off + j + 1] = idx[off + j];
        key[j + 1] = key[j];
        j--;
      }
      idx[off + j + 1] = v;
      key[j + 1] = kv;
    }
  }
}
