// V0.7 전술 AI
//
// AI 계층 :  Strategic (Commander.update, 1Hz) -> Tactical (이 파일, 5Hz) -> Squad (Squad.pde, 5Hz) -> Agent (Boids/Combat, 매 스텝)
//   Strategic : 종족 전체 목표 (공격할 종족, 후퇴, 방어, 자율)
//   Tactical  : 분대마다 역할과 목표 지점 (집중 공격, 전선 돌파, 측면 공격, 포위, 불리한 분대 후퇴와 재집결)
//   Squad     : 진형과 슬롯 (V0.6)
//   Agent     : 회피, 공격, 생존 (V0.2~)
// 판단은 200px 영향력 격자(InfluenceMap)로 한다 : 지역별 병력 집계, 전선, 적의 약한 지점.
// 난수를 쓰지 않는다. 할당도 없다.

// 종족 상성 (행 = 나, 열 = 상대). RED는 GREEN을 잡지만 BLUE에게 지고, BLUE는 RED를 이기지만 GREEN을 못 따라잡는다.
final float[][] MATCHUP_TABLE = {{1.0, 0.6, 2.0}, {1.6, 1.0, 0.1}, {0.5, 0.3, 1.0}};

float matchupOf(int me, int other) {
  return MATCHUP_TABLE[me][other];
}

// 전술 계획
final int PLAN_NONE = 0, PLAN_FOCUS = 1, PLAN_FLANK = 2, PLAN_ENCIRCLE = 3, PLAN_RETREAT = 4, PLAN_DEFEND = 5;
// 분대 역할
final int ROLE_NONE = 0, ROLE_MAIN = 1, ROLE_BREACH = 2, ROLE_FLANK = 3, ROLE_ENCIRCLE = 4, ROLE_RETREAT = 5, ROLE_REGROUP = 6, ROLE_DEFEND = 7;

final int TAC_PERIOD = 12;            // 5Hz
final float ENCIRCLE_RATIO = 2.0;     // 이만큼 유리하면 포위
final float SQUAD_RETREAT_EFF = 0.6;  // 분대 주변 유효 전력비가 이보다 낮으면 그 분대만 후퇴
final float FLANK_OFFSET = 350;       // 측면 우회 거리
final float ENCIRCLE_R = 260;         // 포위 고리 반경

String planName(int p) {
  String[] n = {"-", "집중", "측면", "포위", "후퇴", "방어"};
  return n[p];
}

String roleName(int r) {
  String[] n = {"-", "주력", "돌파", "측면", "포위", "후퇴", "재집결", "방어"};
  return n[r];
}

// 병력 수에 따른 계획 : 분대가 3개 이상이고 크게 유리하면 포위, 3개 이상이면 측면+돌파, 아니면 집중
int choosePlan(int squads, float eff) {
  if (squads >= 3 && eff >= ENCIRCLE_RATIO) return PLAN_ENCIRCLE;
  if (squads >= 3) return PLAN_FLANK;
  return PLAN_FOCUS;
}

// ---------- 영향력 격자 : 종족별 200px 칸의 개체 수와 전투력 합 ----------

class InfluenceMap {
  final float C = 200;
  int cols = ceil(WORLD_W / 200.0), rows = ceil(WORLD_H / 200.0);
  int[][] cnt = new int[N_SPECIES][cols * rows];
  float[][] pow = new float[N_SPECIES][cols * rows];
  int[] frontCells = new int[N_SPECIES];        // 전선 : 내 칸 중 이웃 8칸에 적이 있는 칸 수

  int cell(float x, float y) {
    return constrain((int) (y / C), 0, rows - 1) * cols + constrain((int) (x / C), 0, cols - 1);
  }

  void update(World w) {
    for (int s = 0; s < N_SPECIES; s++) {
      java.util.Arrays.fill(cnt[s], 0);
      java.util.Arrays.fill(pow[s], 0);
    }
    for (int i = 0; i < w.count; i++) {
      Agent a = w.pool[i];
      int c = cell(a.x, a.y);
      cnt[a.species][c]++;
      pow[a.species][c] += a.power;
    }
    for (int s = 0; s < N_SPECIES; s++) {
      int f = 0;
      for (int c = 0; c < cols * rows; c++) if (cnt[s][c] > 0 && enemyNear(s, c % cols, c / cols)) f++;
      frontCells[s] = f;
    }
  }

  boolean enemyNear(int s, int cx, int cy) {
    for (int y = max(0, cy - 1); y <= min(rows - 1, cy + 1); y++)
      for (int x = max(0, cx - 1); x <= min(cols - 1, cx + 1); x++)
        for (int e = 0; e < N_SPECIES; e++) if (e != s && cnt[e][y * cols + x] > 0) return true;
    return false;
  }

  // (x, y) 주변 3x3칸의 내 전투력과, 상성으로 보정한 적 전투력 (결과는 ownP, enemyP)
  float ownP, enemyP;
  void localForce(int s, float x, float y) {
    ownP = 0;
    enemyP = 0;
    int cx = constrain((int) (x / C), 0, cols - 1), cy = constrain((int) (y / C), 0, rows - 1);
    for (int yy = max(0, cy - 1); yy <= min(rows - 1, cy + 1); yy++)
      for (int xx = max(0, cx - 1); xx <= min(cols - 1, cx + 1); xx++) {
        int c = yy * cols + xx;
        ownP += pow[s][c];
        for (int e = 0; e < N_SPECIES; e++) if (e != s) enemyP += pow[e][c] / matchupOf(s, e);
      }
  }

  // 적의 약한 지점 : (x, y)에서 radius 안의 종족 e 칸 중 전투력이 가장 작은 칸 중심 (없으면 false)
  float weakX, weakY;
  boolean weakest(int e, float x, float y, float radius) {
    float best = 1e30;
    boolean found = false;
    for (int c = 0; c < cols * rows; c++) {
      if (cnt[e][c] < 3) continue;                   // 낙오자 몇 마리는 '전선'이 아니다
      float px = (c % cols + 0.5) * C, py = (c / cols + 0.5) * C;
      if (dist(px, py, x, y) > radius) continue;
      if (pow[e][c] < best) {
        best = pow[e][c];
        weakX = px;
        weakY = py;
        found = true;
      }
    }
    return found;
  }
}

// ---------- 전술 AI ----------

class TacticalAI {
  int[] plan = new int[N_SPECIES];
  int[] rank = new int[MAX_SQUADS_PER_SPECIES];
  float[] lateral = new float[MAX_SQUADS_PER_SPECIES];
  long[] roleSteps = new long[8];                 // 역할별 누적 (검증용)
  int retreats, regroups;                          // 분대 후퇴/재집결 전환 횟수 (검증용)

  void reset() {
    for (int s = 0; s < N_SPECIES; s++) plan[s] = PLAN_NONE;
    java.util.Arrays.fill(roleSteps, 0);
    retreats = 0;
    regroups = 0;
  }

  // 전술이 이 종족의 분대를 움직이는가 (AI 지휘 + 할 일이 있을 때)
  boolean active(Commander cm) {
    return !cm.isPlayer && cm.order != ORD_NONE;
  }

  void update(World w) {
    InfluenceMap im = w.influence;
    for (int s = 0; s < N_SPECIES; s++) {
      Commander cm = w.cmd[s];
      int base = s * SQUAD_STRIDE, K = w.squads.k[s];
      if (!active(cm) || K == 0) {
        plan[s] = PLAN_NONE;
        for (int j = 0; j < MAX_SQUADS_PER_SPECIES; j++) clearSquad(w.squads.sq[base + j]);
        continue;
      }

      // 분대를 진행 축의 좌우 순서로 정렬 (왼쪽 분대가 왼쪽 측면으로)
      float ax = cm.tx - w.cx[s], ay = cm.ty - w.cy[s];
      float am = max(1, sqrt(ax * ax + ay * ay));
      float ux = ax / am, uy = ay / am, px = -uy, py = ux;
      for (int j = 0; j < K; j++) {
        Squad q = w.squads.sq[base + j];
        lateral[j] = (q.cx - w.cx[s]) * px + (q.cy - w.cy[s]) * py;
        rank[j] = j;
      }
      for (int i = 1; i < K; i++) {                // 삽입 정렬 (K <= 12)
        int v = rank[i];
        int k = i - 1;
        while (k >= 0 && lateral[rank[k]] > lateral[v]) {
          rank[k + 1] = rank[k];
          k--;
        }
        rank[k + 1] = v;
      }

      if (cm.order == ORD_RETREAT) plan[s] = PLAN_RETREAT;
      else if (cm.order == ORD_DEFEND) plan[s] = PLAN_DEFEND;
      else if (cm.order == ORD_ATTACK) plan[s] = choosePlan(K, cm.lastEff);
      else plan[s] = PLAN_FOCUS;                   // 이동

      // 돌파 지점 : 목표 근처에서 적이 가장 약한 칸
      float bx = cm.tx, by = cm.ty;
      if (cm.order == ORD_ATTACK && cm.targetSp >= 0 && im.weakest(cm.targetSp, cm.tx, cm.ty, 450)) {
        bx = im.weakX;
        by = im.weakY;
      }

      for (int r = 0; r < K; r++) {
        Squad q = w.squads.sq[base + rank[r]];
        if (q.n == 0) continue;
        q.roleT += TAC_PERIOD * DT;

        // 분대 단위 생존 판단 : 주변 유효 전력비가 낮으면 이 분대만 물러났다가 재집결 (전 종족 후퇴와 별개)
        im.localForce(s, q.cx, q.cy);
        float eff = im.enemyP > 0 ? im.ownP / im.enemyP : 99;
        if (q.role == ROLE_RETREAT) {
          if (dist(q.cx, q.cy, q.rallyX, q.rallyY) < 160 || (eff > 1.0 && q.roleT > 3)) setRole(q, ROLE_REGROUP, ORD_MOVE, q.rallyX, q.rallyY);
          else q.order = ORD_RETREAT;
          continue;
        }
        if (q.role == ROLE_REGROUP) {
          if (q.roleT < 2.5 || q.engaged > 0.1) continue;           // 대열을 다시 짜는 동안 기다린다
        } else if (plan[s] != PLAN_RETREAT && eff < SQUAD_RETREAT_EFF) {   // 교전 전이라도 천적 근처면 피한다
          rally(w, s, q);
          setRole(q, ROLE_RETREAT, ORD_RETREAT, q.rallyX, q.rallyY);
          retreats++;
          continue;
        }

        if (plan[s] == PLAN_RETREAT) {
          setRole(q, ROLE_RETREAT, ORD_RETREAT, cm.tx + lateral[rank[r]] * 0.3 * px, cm.ty + lateral[rank[r]] * 0.3 * py);
          q.rallyX = q.tx;
          q.rallyY = q.ty;
        } else if (plan[s] == PLAN_DEFEND) {                       // 방어 지점 둘레에 분대를 나눠 세운다
          float a = TWO_PI * r / K;
          float rr = K > 1 ? 140 : 0;
          setRole(q, ROLE_DEFEND, ORD_DEFEND, cm.tx + cos(a) * rr, cm.ty + sin(a) * rr);
        } else if (plan[s] == PLAN_ENCIRCLE) {                     // 목표 둘레의 서로 다른 각도로 돌아간 뒤 조인다
          float base0 = atan2(-uy, -ux);
          float a = base0 + (K > 1 ? (r / (float) (K - 1) - 0.5) : 0) * PI * 1.6;
          float gx = cm.tx + cos(a) * ENCIRCLE_R, gy = cm.ty + sin(a) * ENCIRCLE_R;
          approach(q, ROLE_ENCIRCLE, gx, gy, cm.tx, cm.ty);
        } else if (plan[s] == PLAN_FLANK) {                        // 양 끝 분대는 측면으로 우회, 가운데는 약한 지점 돌파
          if (r == 0 || r == K - 1) {
            float side = r == 0 ? -1 : 1;
            float gx = cm.tx + px * side * FLANK_OFFSET - ux * 80, gy = cm.ty + py * side * FLANK_OFFSET - uy * 80;
            approach(q, ROLE_FLANK, gx, gy, cm.tx, cm.ty);
          } else {
            setRole(q, ROLE_BREACH, ORD_ATTACK, bx, by);
          }
        } else {                                                   // 집중 : 모두 약한 지점으로
          setRole(q, cm.order == ORD_ATTACK ? ROLE_MAIN : ROLE_MAIN, cm.order == ORD_ATTACK ? ORD_ATTACK : ORD_MOVE,
                  cm.order == ORD_ATTACK ? bx : cm.tx, cm.order == ORD_ATTACK ? by : cm.ty);
        }
      }
      for (int j = K; j < MAX_SQUADS_PER_SPECIES; j++) clearSquad(w.squads.sq[base + j]);
    }
    for (int i = 0; i < MAX_SQUADS; i++) {
      Squad q = w.squads.sq[i];
      if (q.active && q.order >= 0) roleSteps[q.role] += TAC_PERIOD;
    }
  }

  // 우회 지점(gx, gy)까지는 이동(종대), 도착하면 목표(tx, ty)로 공격(쐐기). 한 번 공격으로 바뀌면 멀리 밀려나기 전까지 유지.
  void approach(Squad q, int role, float gx, float gy, float tx, float ty) {
    boolean wasAttacking = q.role == role && q.order == ORD_ATTACK;
    float d = dist(q.cx, q.cy, gx, gy);
    float dt = dist(q.cx, q.cy, tx, ty);
    if ((wasAttacking && dt < ENCIRCLE_R * 2.2) || d < 180 || dt < ENCIRCLE_R * 0.9) setRole(q, role, ORD_ATTACK, tx, ty);
    else setRole(q, role, ORD_MOVE, gx, gy);
  }

  void setRole(Squad q, int role, int order, float tx, float ty) {
    if (q.role != role) {
      if (role == ROLE_REGROUP) regroups++;
      q.role = role;
      q.roleT = 0;
    }
    q.order = order;
    q.tx = constrain(tx, 60, WORLD_W - 60);
    q.ty = constrain(ty, 60, WORLD_H - 60);
  }

  void clearSquad(Squad q) {
    q.order = -1;
    q.role = ROLE_NONE;
    q.roleT = 0;
  }

  // 재집결 지점 : 종족 중심 쪽으로, 분대 주변 적 무게중심의 반대편 (적이 없으면 종족 중심)
  void rally(World w, int s, Squad q) {
    float ex = 0, ey = 0, en = 0;
    for (int e = 0; e < N_SPECIES; e++) {
      if (e == s || w.pop[e] == 0) continue;
      float d = dist(w.cx[e], w.cy[e], q.cx, q.cy);
      float wgt = w.powerSum[e] / max(1, d);
      ex += w.cx[e] * wgt;
      ey += w.cy[e] * wgt;
      en += wgt;
    }
    float rx = w.cx[s], ry = w.cy[s];
    if (en > 0) {
      ex /= en;
      ey /= en;
      float dx = q.cx - ex, dy = q.cy - ey, m = max(1, sqrt(dx * dx + dy * dy));
      rx = q.cx + dx / m * 380;
      ry = q.cy + dy / m * 380;
      if (dist(w.cx[s], w.cy[s], ex, ey) > dist(rx, ry, ex, ey)) {  // 종족 본대가 더 안전하면 본대로
        rx = w.cx[s];
        ry = w.cy[s];
      }
    }
    q.rallyX = constrain(rx, 100, WORLD_W - 100);
    q.rallyY = constrain(ry, 100, WORLD_H - 100);
  }
}
