// 지휘관. 종족마다 하나이며, 플레이어가 고른 종족은 입력으로, 나머지는 자체 AI로 명령을 정한다.
//
// 명령은 개체를 직접 움직이지 않고 '조향력의 한 항'으로만 들어간다. 그래서
//   - 개체는 군집(Boids), 전투 판단, 채집을 그대로 유지하면서 명령 위치를 목표로 삼는다.
//   - 복종도 = 군집 성향 x (0.5 + 0.5 x 에너지 비율) : 배고프거나 군집 성향이 낮은 개체는 덜 따른다 (무조건 복종 아님).
//   - 전투 중(공격/도주/후퇴/지원)인 개체는 이동 명령보다 전투 판단을 우선한다.
//
//   MOVE    좌클릭 : 위치로 이동 (도착하면 속도를 줄인다)
//   DEFEND  우클릭 : 위치를 중심으로 방어. 구역 안의 적에게는 더 공격적이고, 이탈 한계(반경 x 1.5) 밖으로는 추격하지 않는다
//   ATTACK  Q      : 공격 명령. 목표(마지막 이동 지점 또는 가장 큰 적 무리)로 전진하며 훨씬 공격적이 된다
//   RETREAT E      : 후퇴 명령. 집결지로 물러나며 교전을 피한다

class Commander {
  int species;
  boolean isPlayer;
  int order = ORD_NONE;
  float tx, ty;                     // 명령 목표
  float radius = 220;               // 방어 반경
  float rallyX, rallyY;             // 집결지 (후퇴 목적지)
  int aiTimer;

  // 무리 찾기용 거친 격자 (할당 없이 재사용)
  final int CC = 200;
  int ccols = ceil(WORLD_W / 200.0), crows = ceil(WORLD_H / 200.0);
  int[] ccnt = new int[ccols * crows];
  float[] csx = new float[ccols * crows];
  float[] csy = new float[ccols * crows];

  float fx, fy;                     // force()가 만든 조향력
  float tgtX, tgtY;                 // findCluster() 결과

  Commander(int species) {
    this.species = species;
  }

  void reset(float homeX, float homeY) {
    order = ORD_NONE;
    rallyX = homeX;
    rallyY = homeY;
    tx = homeX;
    ty = homeY;
    aiTimer = 0;
  }

  // ---------- 플레이어 명령 ----------

  void moveTo(float x, float y) {
    order = ORD_MOVE;
    tx = x;
    ty = y;
  }

  void defendAt(float x, float y) {
    order = ORD_DEFEND;
    tx = x;
    ty = y;
    rallyX = x;
    rallyY = y;
  }

  void attack(World w) {
    w.refreshSpeciesStats();                               // 개체 수와 무게중심을 최신으로
    if (order != ORD_MOVE && order != ORD_ATTACK) {        // 이동 목표가 없으면 가장 큰 적 무리로
      if (findEnemyTarget(w)) {
        tx = tgtX;
        ty = tgtY;
      }
    }
    order = ORD_ATTACK;
  }

  void retreat() {
    order = ORD_RETREAT;
    tx = rallyX;
    ty = rallyY;
  }

  // ---------- 무리 찾기 ----------

  // 종족 sp의 개체가 가장 많이 모인 200px 칸의 중심을 tgtX, tgtY에 넣는다. 개체가 없으면 false.
  boolean findCluster(World w, int sp) {
    java.util.Arrays.fill(ccnt, 0);
    java.util.Arrays.fill(csx, 0);
    java.util.Arrays.fill(csy, 0);
    for (int i = 0; i < w.count; i++) {
      Agent a = w.pool[i];
      if (a.species != sp) continue;
      int c = constrain((int) (a.y / CC), 0, crows - 1) * ccols + constrain((int) (a.x / CC), 0, ccols - 1);
      ccnt[c]++;
      csx[c] += a.x;
      csy[c] += a.y;
    }
    int best = -1, bn = 0;
    for (int c = 0; c < ccnt.length; c++) {
      if (ccnt[c] > bn) {
        bn = ccnt[c];
        best = c;
      }
    }
    if (best < 0) return false;
    tgtX = csx[best] / bn;
    tgtY = csy[best] / bn;
    return true;
  }

  // 이 종족에게 가장 가까운 적 종족의 가장 큰 무리
  boolean findEnemyTarget(World w) {
    int ne = nearestEnemy(w);
    return ne >= 0 && findCluster(w, ne);
  }

  int nearestEnemy(World w) {
    int ne = -1;
    float best = 1e18;
    for (int s = 0; s < N_SPECIES; s++) {
      if (s == species || w.pop[s] == 0) continue;
      float dx = w.cx[s] - w.cx[species], dy = w.cy[s] - w.cy[species];
      float d2 = dx * dx + dy * dy;
      if (d2 < best) {
        best = d2;
        ne = s;
      }
    }
    return ne;
  }

  // ---------- 자체 AI (3초마다) ----------
  //   이길 수 있으면 공격, 크게 밀리면 적에게서 가장 먼 오아시스로 후퇴, 그 밖에는 명령 없이 자율 행동

  void update(World w) {
    if (isPlayer || w.pop[species] == 0) return;
    if (aiTimer-- > 0) return;
    aiTimer = 180;
    if (w.eco.enabled && w.meanEnergy[species] < 0.5) {   // 배가 고프면 명령을 멈추고 먹이부터 구한다
      order = ORD_NONE;
      return;
    }

    // 전투력 합 비율에 종족 상성을 곱해 판단한다 (전투력 합만으로는 BLUE의 방어와 지원, GREEN의 도주를 반영하지 못한다)
    //   행 = 내 종족, 열 = 상대 종족. RED는 GREEN을 잡지만 BLUE에게는 지고, BLUE는 RED를 이기지만 GREEN을 못 따라잡는다.
    float[][] matchup = {{1.0, 0.6, 2.0}, {1.6, 1.0, 0.1}, {0.5, 0.3, 1.0}};
    float[] attackThr = {0.9, 2.2, 99};               // RED는 공세적, BLUE는 압도적일 때만(수호자), GREEN은 싸우지 않는다

    int ne = nearestEnemy(w);
    int target = -1;                                  // 가장 유리한 적 종족
    float bestEff = 0;
    for (int e = 0; e < N_SPECIES; e++) {
      if (e == species || w.pop[e] == 0) continue;
      float eff = w.powerSum[species] / max(1, w.powerSum[e]) * matchup[species][e];
      if (eff > bestEff) {
        bestEff = eff;
        target = e;
      }
    }
    float nearEff = ne >= 0 ? w.powerSum[species] / max(1, w.powerSum[ne]) * matchup[species][ne] : 99;

    if (target >= 0 && bestEff >= attackThr[species] && findCluster(w, target)) {
      order = ORD_ATTACK;
      tx = tgtX;
      ty = tgtY;
    } else if (ne >= 0 && nearEff < 0.5) {
      order = ORD_RETREAT;
      float far = -1;                                  // 적 무리에서 가장 먼 오아시스로 물러난다
      for (int h = 0; h < w.eco.hotX.length; h++) {
        float d = dist(w.eco.hotX[h], w.eco.hotY[h], w.cx[ne], w.cy[ne]);
        if (d > far) {
          far = d;
          tx = w.eco.hotX[h];
          ty = w.eco.hotY[h];
        }
      }
      rallyX = tx;
      rallyY = ty;
    } else {
      order = ORD_NONE;                                // 할 일이 없으면 자율 행동 (채집과 군집). 계속 이동시키면 먹이를 고갈시킨다.
    }
  }

  // ---------- 개체에 미치는 힘 ----------

  boolean free(Agent me) {
    return me.state == AS_FLOCK || me.state == AS_REGROUP || me.state == AS_SUPPORT;
  }

  void force(World w, Agent me, Species s) {
    fx = 0;
    fy = 0;
    if (order == ORD_NONE) return;
    BoidsSystem b = w.boids;
    float obey = me.flockMul * (0.5 + 0.5 * me.energy / me.maxEnergy);
    float dx = tx - me.x, dy = ty - me.y;
    float d = sqrt(dx * dx + dy * dy);

    if (order == ORD_MOVE || order == ORD_ATTACK) {
      if (!free(me)) return;
      float old = me.speedMul;
      if (order == ORD_MOVE) me.speedMul = old * constrain(d / 160.0, 0.2, 1.0);     // 도착하면 속도를 줄인다
      b.steer(dx, dy, me, s.maxForce);
      me.speedMul = old;
      fx = b.outX * 1.2 * obey;
      fy = b.outY * 1.2 * obey;
    } else if (order == ORD_DEFEND) {
      if (d > radius * 0.8) {                          // 방어 구역 밖이면 돌아온다
        b.steer(dx, dy, me, s.maxForce);
        float k = d > radius * 1.5 ? 2.0 : 1.2;
        fx = b.outX * k * obey;
        fy = b.outY * k * obey;
      }
    } else if (order == ORD_RETREAT) {
      if (d > 120) {
        b.steer(dx, dy, me, s.maxForce);
        fx = b.outX * 1.6 * obey;
        fy = b.outY * 1.6 * obey;
      }
    }
  }
}
