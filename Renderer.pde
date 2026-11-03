// 그리기 : 종족별로 삼각형을 한 번의 beginShape(TRIANGLES)에 모아 그린다. 화면 밖의 개체는 건너뛴다.

class Renderer {
  boolean trails = false;           // 화면 잔상 (이전 프레임을 서서히 지운다)
  boolean showGrid = false;         // 공간 격자 디버그
  float vl, vt, vr, vb;             // 지금 화면에 보이는 월드 영역

  void draw(World w, Camera cam, int player, Effects fx, GameMode gm) {
    if (trails) {
      noStroke();
      fill(6, 8, 14, 38);
      rect(0, 0, width, height);
    } else {
      background(6, 8, 14);
    }

    vl = cam.left(30);
    vr = cam.right(30);
    vt = cam.top(30);
    vb = cam.bottom(30);

    pushMatrix();
    cam.apply();
    drawBackdrop();
    if (gm.mode == MODE_CONQUEST) drawZones(w, gm);
    fx.drawBelow(w);
    drawFood(w);
    if (fx.effective(w) >= 3) drawStreaks(w);
    drawAgents(w);
    fx.drawAbove(w);
    drawOrders(w, player);
    if (showGrid) drawGridDebug(w);
    popMatrix();
  }

  boolean visible(float x, float y) {
    return x > vl && x < vr && y > vt && y < vb;
  }

  void drawBackdrop() {
    stroke(18, 20, 25);                       // 반투명 선은 Java2D에서 느려서, 배경과 미리 섞은 불투명 색을 쓴다
    strokeWeight(1);
    beginShape(LINES);
    for (float x = 0; x <= WORLD_W; x += 200) {
      vertex(x, 0);
      vertex(x, WORLD_H);
    }
    for (float y = 0; y <= WORLD_H; y += 200) {
      vertex(0, y);
      vertex(WORLD_W, y);
    }
    endShape();
    noFill();
    stroke(55, 56, 61);
    strokeWeight(3);
    rect(0, 0, WORLD_W, WORLD_H);
  }

  // 점령 모드의 구역 : 점유한 종족의 색으로 표시
  void drawZones(World w, GameMode gm) {
    for (int z = 0; z < gm.zoneOwner.length; z++) {
      int o = gm.zoneOwner[z];
      color c = o >= 0 ? w.species[o].col : color(150);
      fill(red(c), green(c), blue(c), o >= 0 ? 26 : 10);
      stroke(red(c), green(c), blue(c), o >= 0 ? 150 : 60);
      strokeWeight(2);
      ellipse(w.eco.hotX[z], w.eco.hotY[z], gm.ZONE_R * 2, gm.ZONE_R * 2);
    }
    strokeWeight(1);
  }

  // 지휘 명령 표시 : 지휘 중인 종족은 선명하게, AI 종족은 흐리게
  void drawOrders(World w, int player) {
    float pulse = 0.5 + 0.5 * sin(frameCount * 0.12);
    for (int s = 0; s < N_SPECIES; s++) {
      Commander c = w.cmd[s];
      if (c.order == ORD_NONE) continue;
      color col = w.species[s].col;
      boolean mine = s == player;
      stroke(red(col), green(col), blue(col), mine ? 230 : 70);
      strokeWeight(mine ? 4 : 2);
      noFill();
      if (c.order == ORD_MOVE) {
        ellipse(c.tx, c.ty, 50 + 24 * pulse, 50 + 24 * pulse);
        line(c.tx - 14, c.ty, c.tx + 14, c.ty);
        line(c.tx, c.ty - 14, c.tx, c.ty + 14);
      } else if (c.order == ORD_DEFEND) {
        ellipse(c.tx, c.ty, c.radius * 2, c.radius * 2);
        ellipse(c.tx, c.ty, c.radius * 3, c.radius * 3);          // 바깥 원 : 이 밖으로는 추격하지 않는다
        ellipse(c.tx, c.ty, 30, 30);
      } else if (c.order == ORD_ATTACK) {
        ellipse(c.tx, c.ty, 70 + 20 * pulse, 70 + 20 * pulse);
        line(c.tx - 50, c.ty, c.tx - 20, c.ty);
        line(c.tx + 20, c.ty, c.tx + 50, c.ty);
        line(c.tx, c.ty - 50, c.tx, c.ty - 20);
        line(c.tx, c.ty + 20, c.tx, c.ty + 50);
      } else if (c.order == ORD_RETREAT) {
        ellipse(c.tx, c.ty, 90, 90);
        float a = atan2(w.cy[s] - c.ty, w.cx[s] - c.tx);
        pushMatrix();
        translate(c.tx, c.ty);
        rotate(a + PI);
        line(-14, 0, 14, 0);
        line(14, 0, 4, -8);
        line(14, 0, 4, 8);
        popMatrix();
      }
    }
    strokeWeight(1);
  }

  // 먹이는 점으로 한 번에 그린다 (시체 먹이는 더 작고 붉은 색)
  void drawFood(World w) {
    FoodField f = w.eco.food;
    strokeCap(ROUND);
    stroke(150, 255, 130, 80);
    strokeWeight(11);
    beginShape(POINTS);
    for (int i = 0; i < f.count; i++) if (f.v[i] >= FOOD_ENERGY && visible(f.x[i], f.y[i])) vertex(f.x[i], f.y[i]);
    endShape();
    stroke(200, 255, 170);
    strokeWeight(5);
    beginShape(POINTS);
    for (int i = 0; i < f.count; i++) if (f.v[i] >= FOOD_ENERGY && visible(f.x[i], f.y[i])) vertex(f.x[i], f.y[i]);
    endShape();
    stroke(255, 170, 120);
    strokeWeight(4);
    beginShape(POINTS);
    for (int i = 0; i < f.count; i++) if (f.v[i] < FOOD_ENERGY && visible(f.x[i], f.y[i])) vertex(f.x[i], f.y[i]);
    endShape();
    strokeWeight(1);
  }

  // 이동 궤적 : 속도 반대 방향으로 짧은 꼬리를 남긴다
  void drawStreaks(World w) {
    Agent[] a = w.pool;
    int n = w.count;
    strokeWeight(1.5);
    for (int s = 0; s < N_SPECIES; s++) {
      color c = w.species[s].col;
      stroke(red(c) * 0.27 + 4, green(c) * 0.27 + 6, blue(c) * 0.27 + 10);     // 배경과 미리 섞은 불투명 색
      beginShape(LINES);
      for (int i = 0; i < n; i++) {
        Agent o = a[i];
        if (o.species != s || !visible(o.x, o.y)) continue;
        vertex(o.x, o.y);
        vertex(o.x - o.vx * 0.17, o.y - o.vy * 0.17);
      }
      endShape();
    }
    strokeWeight(1);
  }

  void drawAgents(World w) {
    noStroke();
    Agent[] a = w.pool;
    int n = w.count;
    for (int s = 0; s < N_SPECIES; s++) {
      Species sp = w.species[s];
      float sz = sp.size;
      fill(sp.col);
      beginShape(TRIANGLES);
      for (int i = 0; i < n; i++) {
        Agent o = a[i];
        if (o.species != s || !visible(o.x, o.y)) continue;
        float dx = cos(o.heading), dy = sin(o.heading);
        float px = -dy, py = dx;
        vertex(o.x + dx * sz, o.y + dy * sz);
        vertex(o.x - dx * sz * 0.6 + px * sz * 0.5, o.y - dy * sz * 0.6 + py * sz * 0.5);
        vertex(o.x - dx * sz * 0.6 - px * sz * 0.5, o.y - dy * sz * 0.6 - py * sz * 0.5);
      }
      endShape();
    }

    // 막 피해를 입은 개체는 잠깐 하얗게 번쩍인다
    fill(255, 255, 255, 220);
    beginShape(TRIANGLES);
    for (int i = 0; i < n; i++) {
      Agent o = a[i];
      if (o.hurtTimer <= 0.85 || !visible(o.x, o.y)) continue;
      float sz = w.species[o.species].size * 1.15;
      float dx = cos(o.heading), dy = sin(o.heading);
      float px = -dy, py = dx;
      vertex(o.x + dx * sz, o.y + dy * sz);
      vertex(o.x - dx * sz * 0.6 + px * sz * 0.5, o.y - dy * sz * 0.6 + py * sz * 0.5);
      vertex(o.x - dx * sz * 0.6 - px * sz * 0.5, o.y - dy * sz * 0.6 - py * sz * 0.5);
    }
    endShape();
  }

  void drawGridDebug(World w) {
    SpatialGrid g = w.grid;
    stroke(255, 255, 0, 40);
    strokeWeight(1);
    beginShape(LINES);
    for (int c = 0; c <= g.cols; c++) {
      vertex(c * g.cell, 0);
      vertex(c * g.cell, g.rows * g.cell);
    }
    for (int r = 0; r <= g.rows; r++) {
      vertex(0, r * g.cell);
      vertex(g.cols * g.cell, r * g.cell);
    }
    endShape();
  }
}
