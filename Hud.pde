// 화면 정보. 상단에 전황, 오른쪽에 실시간 통계 그래프 4개.
//   개체 수(종족별)   세대별 평균 능력치(지휘 종족)   먹이 생성/소비   종족별 전투 승률

class Hud {
  boolean visible = true;
  boolean graphs = true;
  final float BAR_H = 64;
  final float PANEL_W = 340;
  String[] geneNames = {"속도", "공격", "방어", "감지", "공격성", "군집성", "회피성"};
  int[] geneCols = {0xFF5AD2FF, 0xFFFF6B6B, 0xFF6B8CFF, 0xFF9BE564, 0xFFFFB347, 0xFFC792EA, 0xFFFFE066};

  // 화면 위의 이 좌표가 HUD(상단 바, 그래프 패널) 위인가 (명령 클릭이 HUD를 뚫지 않도록)
  boolean hits(float mx, float my) {
    if (!visible) return false;
    if (my < BAR_H) return true;
    return graphs && mx > width - PANEL_W - 10 && my > BAR_H;
  }

  String orderName(int o) {
    String[] n = {"자율", "이동", "방어", "공격", "후퇴"};
    return n[o];
  }

  // text() 한 번이 약 0.5ms라 HUD를 매 프레임 그리면 느리다. 오프스크린 버퍼에 초당 5번만 그리고,
  // 매 프레임은 그 이미지를 복사만 한다. (숫자가 5Hz로 갱신돼도 읽는 데 지장이 없다)
  PGraphics topG, panelG, helpG;
  int lastRefresh = -100;
  final int REFRESH_FRAMES = 12;
  final int TOP_H = 96, HELP_H = 40;

  void draw(World w, Metrics m, int player, float timeScale, boolean paused, GameMode gm, Effects fx) {
    drawResult(w, gm);
    if (!visible) return;

    int panelX = (int) (width - PANEL_W - 4);
    if (topG == null) {
      topG = createGraphics(width, TOP_H);
      panelG = createGraphics(width - panelX, height - (int) BAR_H);
      helpG = createGraphics(width, HELP_H);
      lastRefresh = -100;
    }
    if (frameCount - lastRefresh >= REFRESH_FRAMES) {
      lastRefresh = frameCount;

      PGraphics saved = g;                       // 전역 그리기 함수가 버퍼에 그려지도록 g를 잠시 바꾼다
      beginLayer(topG, 0, 0);
      drawBar(w, m, player, timeScale, paused);
      drawModeLine(w, gm, fx);
      endLayer(topG, saved);

      if (graphs) {
        beginLayer(panelG, panelX, BAR_H);
        drawGraphs(w, player);
        endLayer(panelG, saved);
      }

      beginLayer(helpG, 0, height - HELP_H);
      drawHelp();
      endLayer(helpG, saved);
    }
    image(topG, 0, 0);
    if (graphs) image(panelG, panelX, BAR_H);
    image(helpG, 0, height - HELP_H);
  }

  void beginLayer(PGraphics pg, float ox, float oy) {
    g = pg;
    pg.beginDraw();
    pg.clear();
    pg.textFont(uiFont);
    pg.translate(-ox, -oy);                      // 화면 좌표로 그린 내용이 버퍼 안의 올바른 위치에 오도록
  }

  void endLayer(PGraphics pg, PGraphics saved) {
    pg.endDraw();
    g = saved;
  }

  // 상단 바 아래의 모드/효과 상태
  void drawModeLine(World w, GameMode gm, Effects fx) {
    String t = "모드[M] " + gm.name() + "  " + gm.status(w) + "     효과[F] " + fx.levelName(w);
    textAlign(LEFT, TOP);
    textSize(13);
    fill(0, 140);
    noStroke();
    rect(8, BAR_H + 4, textWidth(t) + 16, 22, 5);
    fill(255, 225, 140);
    text(t, 16, BAR_H + 8);
  }

  // 승패가 정해지면 화면 중앙에 결과
  void drawResult(World w, GameMode gm) {
    if (!gm.over) return;
    noStroke();
    fill(0, 150);
    rect(0, 0, width, height);
    textAlign(CENTER, CENTER);
    color c = gm.winner >= 0 ? w.species[gm.winner].col : color(255);
    fill(0, 160);
    textSize(64);
    text(gm.resultText(w), width / 2 + 3, height / 2 - 40 + 3);
    fill(c);
    text(gm.resultText(w), width / 2, height / 2 - 40);
    fill(255);
    textSize(20);
    text(gm.name() + " 모드  -  경과 " + nf(gm.elapsed, 1, 0) + "초", width / 2, height / 2 + 20);
    fill(200);
    textSize(16);
    text("R : 재시작     M : 모드 변경", width / 2, height / 2 + 56);
  }

  // ---------- 상단 전황 ----------

  void drawBar(World w, Metrics m, int player, float timeScale, boolean paused) {
    noStroke();
    fill(0, 190);
    rect(0, 0, width, BAR_H);

    for (int s = 0; s < N_SPECIES; s++) {
      Species sp = w.species[s];
      float x = 12 + s * 285;
      if (s == player) {
        fill(255, 28);
        rect(x - 6, 4, 276, BAR_H - 8, 6);
      }
      fill(sp.col);
      rect(x, 11, 12, 12);
      textAlign(LEFT, TOP);
      fill(255);
      textSize(15);
      text(sp.name + (s == player ? "  [지휘 중]" : "  [AI]") + "   개체 " + w.pop[s], x + 20, 7);
      fill(200);
      textSize(12);
      text("생존율 " + round(w.stats.survival(w, s) * 100) + "%  에너지 " + round(w.meanEnergy[s] * 100) + "%  세대 " + nf(w.avgGen[s], 1, 1) + " (최대 " + w.maxGen[s] + ")", x, 28);
      text("처치 " + w.kills[s] + " / 사망 " + w.deaths[s] + "   명령 " + orderName(w.cmd[s].order), x, 44);
    }

    float gx = 12 + 3 * 285 + 6;
    fill(255);
    textSize(13);
    textAlign(LEFT, TOP);
    text("전체 사망 " + w.totalDeaths + "   총 번식 " + w.eco.totalBirths, gx, 8);
    text("전투 중 " + w.combatAgents + "   개체 " + w.count, gx, 26);
    fill(180);
    textSize(11);
    text("FPS " + round(frameRate) + "  스텝 " + nf(w.stepMs, 1, 2) + "ms  x" + nf(timeScale, 1, 1) + (paused ? "  [정지]" : "")
      + "  시간 " + nf(w.stepCount * DT, 1, 0) + "s", gx, 46);
  }

  // ---------- 그래프 ----------

  void panel(float x, float y, float w, float h, String title) {
    noStroke();
    fill(0, 175);
    rect(x, y, w, h, 6);
    fill(255);
    textSize(13);
    textAlign(LEFT, TOP);
    text(title, x + 8, y + 5);
  }

  void series(float[] v, int n, float x, float y, float w, float h, float vmax, int col, int total) {
    if (n < 2) return;
    noFill();
    stroke(col);
    strokeWeight(1.8);
    beginShape();
    for (int i = 0; i < n; i++) {
      float px = x + w * (total - n + i) / (float) (total - 1);
      float py = y + h - h * constrain(v[i] / vmax, 0, 1);
      vertex(px, py);
    }
    endShape();
    strokeWeight(1);
  }

  void drawGraphs(World w, int player) {
    float px = width - PANEL_W - 4, ph = (height - BAR_H - 16 - 3 * 8) / 4.0;
    float y0 = BAR_H + 8;
    Stats st = w.stats;

    // 1) 개체 수
    float y = y0;
    panel(px, y, PANEL_W, ph, "개체 수 (최근 4분)");
    float gx = px + 10, gy = y + 26, gw = PANEL_W - 20, gh = ph - 38;
    float vmax = 50;
    for (int s = 0; s < N_SPECIES; s++) for (int i = 0; i < st.len; i++) vmax = max(vmax, st.pop[s][i]);
    stroke(255, 40);
    line(gx, gy + gh, gx + gw, gy + gh);
    for (int s = 0; s < N_SPECIES; s++) series(st.pop[s], st.len, gx, gy, gw, gh, vmax, w.species[s].col, st.N);
    fill(160);
    textSize(10);
    textAlign(RIGHT, TOP);
    text("최대 " + int(vmax), px + PANEL_W - 8, y + 6);

    // 2) 세대별 평균 능력치 (지휘 종족, 태어난 개체 기준)
    y += ph + 8;
    int ps = max(0, player);
    panel(px, y, PANEL_W, ph, "세대별 평균 능력치 - " + w.species[ps].name);
    gy = y + 26;
    gh = ph - 52;
    int maxG = max(1, min(w.maxGen[ps], MAX_GEN_TRACK - 1));
    stroke(255, 40);
    line(gx, gy + gh, gx + gw, gy + gh);
    line(gx, gy + gh * 0.5, gx + gw, gy + gh * 0.5);
    for (int g = 0; g < NGENE; g++) {
      noFill();
      stroke(geneCols[g]);
      strokeWeight(1.6);
      beginShape();
      for (int k = 0; k <= maxG; k++) {
        float v = w.evo.genMean(ps, k, g);
        if (v < 0) continue;
        vertex(gx + gw * k / (float) maxG, gy + gh - gh * constrain(v, 0, 1));
      }
      endShape();
    }
    strokeWeight(1);
    textSize(10);
    textAlign(LEFT, TOP);
    for (int g = 0; g < NGENE; g++) {
      fill(geneCols[g]);
      text(geneNames[g], gx + g * 46, y + ph - 22);
    }
    fill(160);
    textAlign(RIGHT, TOP);
    text("세대 0~" + maxG, px + PANEL_W - 8, y + 6);

    // 3) 먹이 생성/소비
    y += ph + 8;
    panel(px, y, PANEL_W, ph, "먹이 (개/초)  생성 vs 소비");
    gy = y + 26;
    gh = ph - 38;
    float fmax = 10;
    for (int i = 0; i < st.len; i++) fmax = max(fmax, max(st.foodGen[i], st.foodCon[i]));
    stroke(255, 40);
    line(gx, gy + gh, gx + gw, gy + gh);
    series(st.foodGen, st.len, gx, gy, gw, gh, fmax, 0xFF8CFF8C, st.N);
    series(st.foodCon, st.len, gx, gy, gw, gh, fmax, 0xFFFFA64D, st.N);
    textSize(10);
    textAlign(RIGHT, TOP);
    fill(140, 255, 140);
    text("생성", px + PANEL_W - 60, y + 6);
    fill(255, 166, 77);
    text("소비", px + PANEL_W - 28, y + 6);

    // 4) 종족별 전투 승률
    y += ph + 8;
    panel(px, y, PANEL_W, ph, "종족별 전투 승률 (처치 / (처치+사망))");
    for (int s = 0; s < N_SPECIES; s++) {
      float by = y + 32 + s * ((ph - 44) / N_SPECIES);
      float wr = st.winRate(w, s);
      fill(255, 30);
      noStroke();
      rect(px + 70, by, PANEL_W - 90, 16, 3);
      fill(w.species[s].col);
      rect(px + 70, by, (PANEL_W - 90) * wr, 16, 3);
      fill(255);
      textSize(12);
      textAlign(LEFT, TOP);
      text(w.species[s].name, px + 10, by + 1);
      textAlign(RIGHT, TOP);
      text(round(wr * 100) + "%", px + PANEL_W - 14, by + 1);
    }
  }

  void drawHelp() {
    fill(255, 150);
    textSize(12);
    textAlign(LEFT, BOTTOM);
    text("명령 : 좌클릭 이동   우클릭 방어   Q 공격   E 후퇴   1/2/3 지휘 종족 선택", 12, height - 28);
    text("화면 : WASD 이동   휠 확대   TAB 그래프   G 격자   T 잔상   F 효과   H 숨김   |   SPACE 정지   , . 배속   M 모드   R 재시작   N 새 시드   UP/DOWN 개체 +-50",
      12, height - 10);
  }
}
