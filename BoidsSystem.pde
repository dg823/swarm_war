// Boids + 전투 이웃 수집. 이웃 순회는 개체마다 한 번만 하고, 결과를 Boids 힘과 NeighborScan에 동시에 쌓는다.
// 2단계 갱신(가속도 계산 -> 적분)으로 처리 순서 편향을 없앤다.

class BoidsSystem {
  float outX, outY;                 // steer() 결과 (할당 없이 돌려주기 위한 임시 값)
  NeighborScan sc = new NeighborScan();

  // 목표 방향(dx, dy)으로 가기 위한 조향력. 원하는 속력은 이 개체의 현재 최대 속력, 크기는 maxForce로 제한.
  void steer(float dx, float dy, Agent me, float maxForce) {
    float m = sqrt(dx * dx + dy * dy);
    if (m < 1e-6) {
      outX = 0;
      outY = 0;
      return;
    }
    float spd = me.speedMax * me.speedMul;
    float sx = dx / m * spd - me.vx;
    float sy = dy / m * spd - me.vy;
    float l = sqrt(sx * sx + sy * sy);
    if (l > maxForce) {
      sx *= maxForce / l;
      sy *= maxForce / l;
    }
    outX = sx;
    outY = sy;
  }

  // 1단계 : 모든 개체의 가속도 ax, ay 계산 (위치와 속도는 바꾸지 않는다)
  void compute(World w) {
    Agent[] a = w.pool;
    int n = w.count;
    SpatialGrid g = w.grid;

    w.refreshSpeciesStats();
    for (int i = 0; i < n; i++) {
      Agent o = a[i];
      Species s = w.species[o.species];
      o.power = (o.atk / s.attackCd) * o.hp * (1 + o.def / 100.0);
    }
    w.combatAgents = 0;
    w.forceSat = 0;

    for (int i = 0; i < n; i++) {
      Agent me = a[i];
      Species s = w.species[me.species];
      float R2 = me.perception * me.perception;
      float supR = min(CELL, me.perception * 1.3);       // 아군 피격을 알아차리는 반경
      float supR2 = supR * supR;
      float sepR = s.sepRadius();
      float sepR2 = sepR * sepR;
      float osepR = s.otherSepRadius();
      float osepR2 = osepR * osepR;

      float sepSX = 0, sepSY = 0, sepOX = 0, sepOY = 0;
      float aliX = 0, aliY = 0, cohX = 0, cohY = 0;
      int nSame = 0, nSepSame = 0, nSepOther = 0;
      sc.reset();

      // 번식 상대 탐색 : 번식 가능한 개체만, 가까운(<= 45px) 같은 종족 중 에너지가 가장 높은 개체를 고른다
      float matThr = s.reproThr * me.maxEnergy;
      boolean eligible = me.energy >= matThr && me.age >= s.minAge && me.repCd <= 0;
      float mateR = min(me.perception, 45);
      float mateR2 = mateR * mateR;
      Agent bestMate = null;
      float bestMateE = 0;

      int cx = g.cellX(me.x), cy = g.cellY(me.y);
      for (int gy = max(0, cy - 1); gy <= min(g.rows - 1, cy + 1); gy++) {
        for (int gx = max(0, cx - 1); gx <= min(g.cols - 1, cx + 1); gx++) {
          int c = gy * g.cols + gx;
          int end = g.cellStart[c + 1];
          for (int k = g.cellStart[c]; k < end; k++) {
            int j = g.order[k];
            if (j == i) continue;
            Agent o = a[j];
            float dx = me.x - o.x, dy = me.y - o.y;
            float d2 = dx * dx + dy * dy;
            if (d2 >= supR2 || d2 < 1e-6) continue;

            if (o.species == me.species) {
              if (o.hurtTimer > 0 && d2 < sc.hurtAllyD2) {
                sc.hurtAlly = j;
                sc.hurtAllyD2 = d2;
              }
              if (d2 >= R2) continue;
              sc.allies++;
              sc.allyPower += o.power;
              if (eligible && d2 < mateR2 && o.energy >= matThr * 0.8 && o.age >= s.minAge * 0.5 && o.energy > bestMateE) {
                bestMate = o;
                bestMateE = o.energy;
              }
              if (d2 < sepR2) {
                sepSX += dx / d2;
                sepSY += dy / d2;
                nSepSame++;
              }
              if (nSame < NEIGHBOR_CAP) {
                aliX += o.vx;
                aliY += o.vy;
                cohX -= dx;
                cohY -= dy;
                nSame++;
              }
            } else {
              if (d2 < osepR2) {
                sepOX += dx / d2;
                sepOY += dy / d2;
                nSepOther++;
              }
              if (d2 >= R2) continue;
              sc.enemies++;
              sc.enemyPower += o.power;
              sc.enemyCx += o.x;
              sc.enemyCy += o.y;
              if (d2 < sc.nearEnemyD2) {
                sc.nearEnemy = j;
                sc.nearEnemyD2 = d2;
              }
            }
          }
        }
      }

      me.mate = bestMate;
      me.mateId = bestMate != null ? bestMate.id : -1;

      float fx = 0, fy = 0;

      // 분리 : 가까울수록 강하게 (거리 반비례), 최대 3배
      if (nSepSame > 0) {
        float mag = sqrt(sepSX * sepSX + sepSY * sepSY);
        if (mag > 0) {
          float f = min(mag * sepR, 3.0) * s.maxForce * s.wSep / mag;
          fx += sepSX * f;
          fy += sepSY * f;
        }
      }
      if (nSepOther > 0) {
        float mag = sqrt(sepOX * sepOX + sepOY * sepOY);
        if (mag > 0) {
          float f = min(mag * osepR, 3.0) * s.maxForce * s.wSepOther / mag;
          fx += sepOX * f;
          fy += sepOY * f;
        }
      }

      // 진형 강도 (V0.6) : 분대 진형 x 전환 블렌드 x (1 - 0.85 x 교전 비율) x 개체의 복귀 정도
      Squad q = w.squads.of(me);
      float formStr = w.squads.strength(me, q);

      // 정렬, 응집 : 같은 종족 이웃만. 진형 중에는 응집을 줄인다 (슬롯이 대신 모양을 잡는다)
      if (nSame > 0) {
        steer(aliX / nSame, aliY / nSame, me, s.maxForce);
        fx += outX * s.wAli * me.flockMul;                // 군집 성향 유전자
        fy += outY * s.wAli * me.flockMul;
        steer(cohX / nSame, cohY / nSame, me, s.maxForce);
        float coh = s.wCoh * me.flockMul * (1 - FORM_COH_CUT * formStr);
        fx += outX * coh;
        fy += outY * coh;
      }

      // 전투 AI : 상태 결정, 상태별 조향력, 공격 (같은 순회 결과를 재사용)
      w.combat.react(w, me, i, sc);
      fx += w.combat.fx;
      fy += w.combat.fy;

      // 진형 복귀 정도 : 교전(공격/도주/후퇴)하면 0, 끝나고 1.5초 뒤부터 초당 0.5씩 회복
      if (me.state == AS_ATTACK || me.state == AS_FLEE || me.state == AS_RETREAT) {
        me.engT = ENGAGE_HOLD;
        me.formK = 0;
      } else if (me.engT > 0) {
        me.engT -= DT;
      } else if (me.formK < 1) {
        me.formK = min(1, me.formK + REFORM_RATE * DT);
      }

      // 진형 슬롯 : 분대 속도 + 슬롯 오차 보정을 원하는 속도로 (도착하면 자연히 느려진다)
      if (formStr > 0.01) {
        float wx = q.cx + q.dirX * me.slotU - q.dirY * me.slotV;
        float wy = q.cy + q.dirY * me.slotU + q.dirX * me.slotV;
        float dvx = q.vx + (wx - me.x) * FORM_GAIN, dvy = q.vy + (wy - me.y) * FORM_GAIN;
        float dm = sqrt(dvx * dvx + dvy * dvy), vmax = me.speedMax * me.speedMul;
        if (dm > vmax) {
          dvx *= vmax / dm;
          dvy *= vmax / dm;
        }
        float sx = dvx - me.vx, sy = dvy - me.vy;
        float sl = sqrt(sx * sx + sy * sy);
        if (sl > s.maxForce) {
          sx *= s.maxForce / sl;
          sy *= s.maxForce / sl;
        }
        float k = FORM_W * formStr * me.flockMul;
        fx += sx * k;
        fy += sy * k;
      }

      // 채집 : 먹이 후보 선정, 배고프면 먹이 쪽으로 (전투 상태가 정해진 뒤에)
      w.eco.forage(w, me, s);
      fx += w.eco.fx;
      fy += w.eco.fy;

      // 지휘 명령 : 조향력의 한 항으로만 더해진다 (군집/전투/채집 규칙은 그대로)
      Commander cm = w.cmd[me.species];
      cm.force(w, me, s);
      fx += cm.fx;
      fy += cm.fy;

      // 경계 회피 : 가장자리 150px 안에서 안쪽으로 점점 강하게
      float m = 150;
      float bf = s.maxForce * s.wBound;
      if (me.x < m) fx += (m - me.x) / m * bf;
      else if (me.x > WORLD_W - m) fx -= (me.x - (WORLD_W - m)) / m * bf;
      if (me.y < m) fy += (m - me.y) / m * bf;
      else if (me.y > WORLD_H - m) fy -= (me.y - (WORLD_H - m)) / m * bf;

      // 장애물 회피 (V0.6) : 가까울수록 강한 반발 + 다가가는 중이면 접선 방향으로 비켜 돌기
      for (int o = 0; o < w.nObs; o++) {
        float ox = me.x - w.obX[o], oy = me.y - w.obY[o];
        float margin = 45 + s.size * 2;
        float reach = w.obR[o] + margin;
        float od2 = ox * ox + oy * oy;
        if (od2 >= reach * reach) continue;
        float od = max(1e-3, sqrt(od2));
        float nx = ox / od, ny = oy / od;
        float t = constrain(1 - (od - w.obR[o]) / margin, 0, 1.5);
        fx += nx * t * s.maxForce * 2.0;
        fy += ny * t * s.maxForce * 2.0;
        float toward = -(me.vx * nx + me.vy * ny);              // 장애물 쪽으로 다가가는 속도
        if (toward > 0) {
          float side = me.vx * -ny + me.vy * nx >= 0 ? 1 : -1;  // 이미 기울어진 쪽으로 돈다
          fx += -ny * side * t * s.maxForce * 1.5;
          fy += nx * side * t * s.maxForce * 1.5;
        }
      }

      // 미세한 무작위 힘 (시드 RNG라 재현 가능)
      fx += (w.rng.nextFloat() - 0.5) * s.jitter;
      fy += (w.rng.nextFloat() - 0.5) * s.jitter;

      float fm = sqrt(fx * fx + fy * fy);
      float fmax = s.maxForce * 2.5;
      if (fm > fmax) {
        fx *= fmax / fm;
        fy *= fmax / fm;
        w.forceSat++;
      }
      me.ax = fx;
      me.ay = fy;
    }
  }

  // 2단계 : 속도와 위치 갱신. 속도는 [0.4 * speedMax, speedMax * speedMul]로 제한, 월드 밖으로 못 나간다.
  void integrate(World w) {
    Agent[] a = w.pool;
    int n = w.count;
    for (int i = 0; i < n; i++) {
      Agent me = a[i];

      me.vx += me.ax * DT;
      me.vy += me.ay * DT;

      float sp = sqrt(me.vx * me.vx + me.vy * me.vy);
      float lo = 0.4 * me.speedMax, hi = me.speedMax * me.speedMul;
      if (sp < 1e-6) {
        me.vx = lo;
        me.vy = 0;
      } else if (sp > hi) {
        me.vx *= hi / sp;
        me.vy *= hi / sp;
      } else if (sp < lo) {
        me.vx *= lo / sp;
        me.vy *= lo / sp;
      }

      me.x += me.vx * DT;
      me.y += me.vy * DT;

      // 그리는 방향은 속도 방향을 부드럽게 따라간다 (갑자기 뒤집히지 않도록)
      float diff = atan2(me.vy, me.vx) - me.heading;
      diff = atan2(sin(diff), cos(diff));
      me.heading += diff * 0.25;

      // 장애물 안으로 들어갔으면 가장자리로 밀어내고 안쪽 속도 성분을 없앤다
      for (int o = 0; o < w.nObs; o++) {
        float ox = me.x - w.obX[o], oy = me.y - w.obY[o];
        float r = w.obR[o] + 1;
        float od2 = ox * ox + oy * oy;
        if (od2 >= r * r) continue;
        float od = sqrt(od2);
        float nx = od > 1e-4 ? ox / od : 1, ny = od > 1e-4 ? oy / od : 0;
        me.x = w.obX[o] + nx * r;
        me.y = w.obY[o] + ny * r;
        float vn = me.vx * nx + me.vy * ny;
        if (vn < 0) {
          me.vx -= vn * nx;
          me.vy -= vn * ny;
        }
      }

      if (me.x < 0) { me.x = 0; me.vx = abs(me.vx); }
      else if (me.x >= WORLD_W) { me.x = WORLD_W - 0.01; me.vx = -abs(me.vx); }
      if (me.y < 0) { me.y = 0; me.vy = abs(me.vy); }
      else if (me.y >= WORLD_H) { me.y = WORLD_H - 0.01; me.vy = -abs(me.vy); }
    }
  }
}
