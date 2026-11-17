// V0.8 전장 효과 (시각 전용 - 시뮬레이션에 영향 없음, Processing random()만 쓴다)
//
//   투사체(예광)  공격자 -> 피격자로 날아가는 빛줄기. 종족마다 모양이 다르다 (RED 짧은 화염 사선, BLUE 에너지 탄, GREEN 쌍침)
//   발사 섬광     공격자 위치의 작은 섬광
//   피격 섬광     투사체가 닿은 곳의 섬광 + 공격 방향으로 튀는 불꽃 (Effects의 파티클)
//   충격파        사망 지점에서 퍼지는 고리 (BLUE는 이중 고리)
//   연기/파편     사망 지점의 연기와 불티
//   그을음        사망 지점에 남는 어두운 자국 (90초에 걸쳐 옅어진다 -> 전투가 쌓일수록 전장이 어두워진다)
//
// 모두 고정 크기 풀(배열)이며, 가득 차면 새 효과를 버린다 (그을음은 가장 오래된 것을 덮어쓴다).
// Java2D는 반투명 선이 느려서 고리/예광은 배경과 미리 섞은 불투명 색으로 그린다.

class BattleFx {
  // 투사체
  final int MAXT = 500;
  float[] tax = new float[MAXT], tay = new float[MAXT], tbx = new float[MAXT], tby = new float[MAXT];
  float[] tt = new float[MAXT], tdur = new float[MAXT];
  int[] tsp = new int[MAXT];
  int nt;

  // 섬광 (발사, 피격)
  final int MAXF = 400;
  float[] fx0 = new float[MAXF], fy0 = new float[MAXF], flife = new float[MAXF], fmax = new float[MAXF], fsize = new float[MAXF];
  int[] fcol = new int[MAXF];
  int nf;

  // 충격파
  final int MAXW = 160;
  float[] wx = new float[MAXW], wy = new float[MAXW], wr = new float[MAXW], wlife = new float[MAXW], wmax = new float[MAXW];
  int[] wcol = new int[MAXW];
  int nw;

  // 연기
  final int MAXS = 260;
  float[] sx = new float[MAXS], sy = new float[MAXS], svx = new float[MAXS], svy = new float[MAXS];
  float[] ssize = new float[MAXS], slife = new float[MAXS], smax = new float[MAXS];
  int[] sshade = new int[MAXS];
  int ns;

  // 그을음 (원형 버퍼)
  final int MAXD = 300;
  final float DECAL_LIFE = 90;
  float[] dx = new float[MAXD], dy = new float[MAXD], dr = new float[MAXD], dage = new float[MAXD];
  int[] dcol = new int[MAXD];
  int nd, dhead;

  long dropped;                                   // 풀이 가득 차 버린 효과 수 (검증용)

  void reset() {
    nt = 0;
    nf = 0;
    nw = 0;
    ns = 0;
    nd = 0;
    dhead = 0;
    dropped = 0;
  }

  // ---------- 생성 ----------

  void projectile(float ax, float ay, float bx, float by, int sp) {
    if (nt >= MAXT) {
      dropped++;
      return;
    }
    tax[nt] = ax;
    tay[nt] = ay;
    tbx[nt] = bx;
    tby[nt] = by;
    tt[nt] = 0;
    tdur[nt] = sp == 0 ? 0.07 : (sp == 1 ? 0.15 : 0.10);
    tsp[nt] = sp;
    nt++;
  }

  void flash(float x, float y, float size, float life, int col) {
    if (nf >= MAXF) {
      dropped++;
      return;
    }
    fx0[nf] = x;
    fy0[nf] = y;
    fsize[nf] = size;
    flife[nf] = life;
    fmax[nf] = life;
    fcol[nf] = col;
    nf++;
  }

  void wave(float x, float y, float r, float life, int col) {
    if (nw >= MAXW) {
      dropped++;
      return;
    }
    wx[nw] = x;
    wy[nw] = y;
    wr[nw] = r;
    wlife[nw] = life;
    wmax[nw] = life;
    wcol[nw] = col;
    nw++;
  }

  void smoke(float x, float y, float size, float life, int shade) {
    if (ns >= MAXS) {
      dropped++;
      return;
    }
    float a = random(TWO_PI), s = random(5, 20);
    sx[ns] = x;
    sy[ns] = y;
    svx[ns] = cos(a) * s;
    svy[ns] = sin(a) * s - 12;                     // 천천히 위로 흩어진다
    ssize[ns] = size;
    slife[ns] = life;
    smax[ns] = life;
    sshade[ns] = shade;
    ns++;
  }

  void decal(float x, float y, float r, int col) {
    int i;
    if (nd < MAXD) i = nd++;
    else {
      i = dhead;                                   // 가장 오래된 자국을 덮어쓴다
      dhead = (dhead + 1) % MAXD;
    }
    dx[i] = x;
    dy[i] = y;
    dr[i] = r;
    dage[i] = 0;
    dcol[i] = col;
  }

  // 타격 사건 : 예광 + 발사 섬광 (피격 섬광은 예광이 닿을 때)
  void onHit(float ax, float ay, float bx, float by, int sp, int L) {
    if (L >= 2) {
      projectile(ax, ay, bx, by, sp);
      if (sp == 1 && L >= 3) projectile(ax + 3, ay - 3, bx, by, sp);  // BLUE는 L3에서 두 발
    } else {
      flash(bx, by, 7, 0.12, hitColor(sp));          // 낮음 : 예광 없이 피격 섬광만
    }
    if (L >= 3) flash(ax, ay, 6, 0.08, muzzleColor(sp));
  }

  // 사망 사건 : 충격파 + 연기 + 그을음 (종족별)
  void onDeath(float x, float y, int sp, int L) {
    if (sp == 0) {                                     // RED : 주황 폭발
      wave(x, y, 38, 0.45, color(255, 140, 60));
      flash(x, y, 18, 0.15, color(255, 200, 120));
      if (L >= 2) for (int i = 0; i < (L >= 3 ? 3 : 1); i++) smoke(x, y, random(10, 18), random(1.0, 1.8), 70);
      decal(x, y, random(9, 14), color(40, 14, 10));
    } else if (sp == 1) {                              // BLUE : 이중 충격파
      wave(x, y, 52, 0.55, color(110, 170, 255));
      if (L >= 2) wave(x, y, 28, 0.35, color(200, 230, 255));
      flash(x, y, 16, 0.12, color(190, 220, 255));
      if (L >= 3) smoke(x, y, random(10, 16), random(0.8, 1.4), 60);
      decal(x, y, random(10, 15), color(12, 20, 40));
    } else {                                           // GREEN : 작은 포자 구름
      wave(x, y, 24, 0.35, color(110, 240, 140));
      if (L >= 2) for (int i = 0; i < (L >= 3 ? 3 : 2); i++) smoke(x, y, random(6, 11), random(0.7, 1.2), 50);
      decal(x, y, random(6, 10), color(12, 32, 16));
    }
  }

  int hitColor(int sp) {
    return sp == 0 ? color(255, 190, 110) : (sp == 1 ? color(170, 210, 255) : color(170, 255, 180));
  }

  int muzzleColor(int sp) {
    return sp == 0 ? color(255, 120, 60) : (sp == 1 ? color(120, 180, 255) : color(120, 255, 150));
  }

  // ---------- 갱신 ----------

  void update(float dt, Effects owner) {
    for (int i = nt - 1; i >= 0; i--) {
      tt[i] += dt / tdur[i];
      if (tt[i] >= 1) {                                // 도착 : 피격 섬광 + 공격 방향으로 튀는 불꽃
        int sp = tsp[i];
        flash(tbx[i], tby[i], sp == 1 ? 10 : 7, 0.12, hitColor(sp));
        float a = atan2(tby[i] - tay[i], tbx[i] - tax[i]);
        for (int k = 0; k < 2; k++) {
          float aa = a + random(-0.6, 0.6), s = random(80, 200);
          owner.addParticle(tbx[i], tby[i], cos(aa) * s, sin(aa) * s, random(0.12, 0.3), random(1.8, 3), hitColor(sp));
        }
        nt--;
        tax[i] = tax[nt];
        tay[i] = tay[nt];
        tbx[i] = tbx[nt];
        tby[i] = tby[nt];
        tt[i] = tt[nt];
        tdur[i] = tdur[nt];
        tsp[i] = tsp[nt];
      }
    }
    for (int i = nf - 1; i >= 0; i--) {
      flife[i] -= dt;
      if (flife[i] <= 0) {
        nf--;
        fx0[i] = fx0[nf];
        fy0[i] = fy0[nf];
        flife[i] = flife[nf];
        fmax[i] = fmax[nf];
        fsize[i] = fsize[nf];
        fcol[i] = fcol[nf];
      }
    }
    for (int i = nw - 1; i >= 0; i--) {
      wlife[i] -= dt;
      if (wlife[i] <= 0) {
        nw--;
        wx[i] = wx[nw];
        wy[i] = wy[nw];
        wr[i] = wr[nw];
        wlife[i] = wlife[nw];
        wmax[i] = wmax[nw];
        wcol[i] = wcol[nw];
      }
    }
    for (int i = ns - 1; i >= 0; i--) {
      slife[i] -= dt;
      if (slife[i] <= 0) {
        ns--;
        sx[i] = sx[ns];
        sy[i] = sy[ns];
        svx[i] = svx[ns];
        svy[i] = svy[ns];
        ssize[i] = ssize[ns];
        slife[i] = slife[ns];
        smax[i] = smax[ns];
        sshade[i] = sshade[ns];
        continue;
      }
      sx[i] += svx[i] * dt;
      sy[i] += svy[i] * dt;
      svx[i] *= 0.97;
      svy[i] *= 0.97;
      ssize[i] += 14 * dt;                             // 퍼지면서 커진다
    }
    for (int i = 0; i < nd; i++) dage[i] += dt;
  }

  // ---------- 그리기 ----------

  // 개체 아래 : 그을음
  void drawBelow(Renderer r) {
    noStroke();
    for (int i = 0; i < nd; i++) {
      if (dage[i] >= DECAL_LIFE || !r.visible(dx[i], dy[i])) continue;
      float k = 1 - dage[i] / DECAL_LIFE;
      int c = dcol[i];
      fill(6 + (red(c) - 6) * k, 8 + (green(c) - 8) * k, 14 + (blue(c) - 14) * k);   // 배경과 섞은 불투명 색
      ellipse(dx[i], dy[i], dr[i] * 2, dr[i] * 1.6);
    }
  }

  // 개체 위 : 연기 -> 충격파 -> 예광 -> 섬광
  void drawAbove(Renderer r) {
    noStroke();
    for (int i = 0; i < ns; i++) {
      if (!r.visible(sx[i], sy[i])) continue;
      float k = slife[i] / smax[i];
      fill(sshade[i], sshade[i] + 2, sshade[i] + 6, 110 * k);
      ellipse(sx[i], sy[i], ssize[i], ssize[i]);
    }
    noFill();
    for (int i = 0; i < nw; i++) {
      if (!r.visible(wx[i], wy[i])) continue;
      float t = 1 - wlife[i] / wmax[i];
      float k = 1 - t;
      int c = wcol[i];
      stroke(6 + (red(c) - 6) * k, 8 + (green(c) - 8) * k, 14 + (blue(c) - 14) * k);
      strokeWeight(1 + 3 * k);
      float rr = 6 + wr[i] * (1 - (1 - t) * (1 - t));   // 빨리 퍼지고 천천히 멈춘다
      ellipse(wx[i], wy[i], rr * 2, rr * 2);
    }
    for (int i = 0; i < nt; i++) {
      float hx = lerp(tax[i], tbx[i], tt[i]), hy = lerp(tay[i], tby[i], tt[i]);
      if (!r.visible(hx, hy)) continue;
      float d = max(1, dist(tax[i], tay[i], tbx[i], tby[i]));
      int sp = tsp[i];
      float len = sp == 0 ? 16 : (sp == 1 ? 9 : 7);
      float t0 = max(0, tt[i] - len / d);
      float lx = lerp(tax[i], tbx[i], t0), ly = lerp(tay[i], tby[i], t0);
      if (sp == 0) {                                  // RED : 굵은 화염 사선
        stroke(255, 120, 50);
        strokeWeight(3);
        line(lx, ly, hx, hy);
        stroke(255, 230, 170);
        strokeWeight(1.2);
        line(lerp(lx, hx, 0.5), lerp(ly, hy, 0.5), hx, hy);
      } else if (sp == 1) {                           // BLUE : 꼬리 달린 에너지 탄
        stroke(70, 120, 220);
        strokeWeight(2);
        line(lx, ly, hx, hy);
        noStroke();
        fill(200, 230, 255);
        ellipse(hx, hy, 5, 5);
        noFill();
      } else {                                        // GREEN : 가는 쌍침
        float nx = -(tby[i] - tay[i]) / d * 2, ny = (tbx[i] - tax[i]) / d * 2;
        stroke(150, 255, 170);
        strokeWeight(1.2);
        line(lx + nx, ly + ny, hx + nx, hy + ny);
        line(lx - nx, ly - ny, hx - nx, hy - ny);
      }
    }
    strokeWeight(1);
    noStroke();
    for (int i = 0; i < nf; i++) {
      if (!r.visible(fx0[i], fy0[i])) continue;
      float k = flife[i] / fmax[i];
      int c = fcol[i];
      fill(red(c), green(c), blue(c), 230 * k);
      float s = fsize[i] * (0.6 + 0.4 * k);
      ellipse(fx0[i], fy0[i], s, s);
    }
  }
}
