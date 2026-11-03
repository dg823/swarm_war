// 전투 AI. Boids와 같은 이웃 순회 결과(NeighborScan)를 받아 개체의 행동 상태를 정하고 추가 조향력을 만든다.
//
// 상태 결정 (가장 가까운 적을 무조건 공격하지 않는다):
//   적이 없다            : 공격받는 아군이 근처에 있으면 SUPPORT, 아군이 하나도 없으면 REGROUP, 아니면 FLOCK
//   적이 있다            : 체력 비율이 후퇴 기준 미만이면 RETREAT
//                          (나 + 주변 아군의 전투력 합) / (주변 적의 전투력 합) x 공격 성향 >= 기준이면 ATTACK, 아니면 FLEE
//                          기준은 현재 상태에 따라 0.8~1.2로 달라진다 (상태가 깜빡이지 않도록 히스테리시스)
// 피해는 두 단계로 처리한다 : 계산 중에는 pendingDmg에 쌓기만 하고, resolve()에서 한꺼번에 적용한다.

class NeighborScan {
  int allies, enemies;
  float allyPower, enemyPower;
  float enemyCx, enemyCy;           // 적 위치의 합 (평균은 사용할 때 나눈다)
  int nearEnemy;
  float nearEnemyD2;
  int hurtAlly;
  float hurtAllyD2;

  void reset() {
    allies = 0;
    enemies = 0;
    allyPower = 0;
    enemyPower = 0;
    enemyCx = 0;
    enemyCy = 0;
    nearEnemy = -1;
    nearEnemyD2 = 1e18;
    hurtAlly = -1;
    hurtAllyD2 = 1e18;
  }
}

class CombatSystem {
  float fx, fy;                     // react()가 만든 추가 조향력

  void react(World w, Agent me, int idx, NeighborScan sc) {
    Species s = w.species[me.species];
    Agent[] a = w.pool;
    BoidsSystem b = w.boids;
    fx = 0;
    fy = 0;
    me.speedMul = 1;
    int prev = me.state;
    float hpFrac = me.hp / me.maxHp;

    if (sc.enemies > 0) w.combatAgents++;

    // ---- 지휘 명령이 판단에 주는 영향 (명령은 성향을 바꿀 뿐, 전투 규칙 자체는 그대로) ----
    Commander cm = w.cmd[me.species];
    float aggr = me.aggression;
    float retreatHp = s.retreatHp;
    int enemies = sc.enemies;
    if (cm.order == ORD_ATTACK) {
      aggr *= 2.0;
      retreatHp *= 0.5;
    } else if (cm.order == ORD_RETREAT) {
      aggr *= 0.25;
    } else if (cm.order == ORD_DEFEND) {
      float dz = dist(me.x, me.y, cm.tx, cm.ty);
      if (dz < cm.radius * 1.2) aggr *= 1.5;               // 방어 구역 안에서는 적극적으로
      else if (dz > cm.radius * 1.5) enemies = 0;          // 이탈 한계 밖에서는 추격하지 않고 돌아간다
      else aggr *= 0.7;
    }

    // ---- 상태 결정 ----
    if (enemies == 0) {
      if (sc.hurtAlly >= 0) me.state = AS_SUPPORT;
      else if (sc.allies == 0 && w.pop[me.species] > 1) me.state = AS_REGROUP;
      else me.state = AS_FLOCK;
    } else {
      float ratio = (me.power + sc.allyPower) / max(0.001, sc.enemyPower);
      float thr = 1.0;
      if (prev == AS_ATTACK) thr = 0.8;
      else if (prev == AS_FLEE || prev == AS_RETREAT) thr = 1.2;
      if (hpFrac < retreatHp) me.state = AS_RETREAT;
      else if (ratio * aggr >= thr) me.state = AS_ATTACK;
      else me.state = AS_FLEE;
    }

    // ---- 상태별 조향력 ----
    if (me.state == AS_ATTACK) {
      Agent t = a[sc.nearEnemy];
      b.steer(t.x - me.x, t.y - me.y, me, s.maxForce);
      fx = b.outX * s.wSeek;
      fy = b.outY * s.wSeek;
      me.speedMul = s.chaseMul;
    } else if (me.state == AS_FLEE || me.state == AS_RETREAT) {
      float ex = sc.enemyCx / sc.enemies, ey = sc.enemyCy / sc.enemies;
      float wf = s.wFlee * me.evasion * (me.state == AS_RETREAT ? 1.5 : 1.0);
      b.steer(me.x - ex, me.y - ey, me, s.maxForce);
      fx = b.outX * wf;
      fy = b.outY * wf;
      me.speedMul = s.fleeMul;
    } else if (me.state == AS_SUPPORT) {
      Agent t = a[sc.hurtAlly];
      b.steer(t.x - me.x, t.y - me.y, me, s.maxForce);
      fx = b.outX * s.wSupport;
      fy = b.outY * s.wSupport;
    } else if (me.state == AS_REGROUP) {
      b.steer(w.cx[me.species] - me.x, w.cy[me.species] - me.y, me, s.maxForce);
      fx = b.outX * s.wRegroup;
      fy = b.outY * s.wRegroup;
    }

    // ---- 공격 : 사거리 안의 가장 가까운 적 (도주 중에도 몰리면 반격한다) ----
    if (sc.nearEnemy >= 0 && me.cooldown <= 0 && sc.nearEnemyD2 <= s.attackRange * s.attackRange) {
      Agent t = a[sc.nearEnemy];
      t.pendingDmg += max(1, me.atk * 100.0 / (100.0 + t.def));
      t.attackerSp = me.species;
      t.attacker = me;
      t.attackerId = me.id;
      me.cooldown = s.attackCd;
      w.events.add(EV_HIT, t.x, t.y, me.species);
    }
  }

  // 피해 적용, 타이머 갱신, 전투 밖 회복, 사망 처리 (뒤에서부터 제거)
  void resolve(World w) {
    Agent[] a = w.pool;
    for (int i = 0; i < w.count; i++) {
      Agent o = a[i];
      Species s = w.species[o.species];
      if (o.cooldown > 0) o.cooldown -= DT;
      if (o.pendingDmg > 0) {                      // 피해 적용이 타이머 만료보다 먼저 (가해자 기록 보존)
        o.hp -= o.pendingDmg;
        w.damageDealt += o.pendingDmg;
        o.pendingDmg = 0;
        o.hurtTimer = 1.0;
      } else {
        if (o.hurtTimer > 0) {
          o.hurtTimer -= DT;
          if (o.hurtTimer <= 0) {
            o.attackerSp = -1;
            o.attacker = null;
          }
        }
        if (o.hurtTimer <= 0 && o.hp < o.maxHp && o.energy > 0
          && (o.state == AS_FLOCK || o.state == AS_REGROUP || o.state == AS_SUPPORT)) {
          o.hp = min(o.maxHp, o.hp + s.regen * DT);
        }
      }
    }
    for (int i = w.count - 1; i >= 0; i--) {
      if (a[i].hp <= 0) {
        w.onDeath(a[i]);
        w.removeAt(i);
      }
    }
  }
}
