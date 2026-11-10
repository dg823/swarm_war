// SWARM WAR : 군집 전쟁 시뮬레이션
//   Boids + 균일 격자 공간 분할 + 전투 AI + 생태계 + 유전 알고리즘 + 플레이어 지휘 + 시각 효과 + 게임 모드
//
// V0.1 군집(Boids, 균일 격자, 고정 타임스텝, 시드 재현)   V0.2 전투(상태 AI, 두 단계 피해 처리)
// V0.3 생태계(일정한 먹이 생성, 에너지, 번식)               V0.4 진화(유전자 7개, 교차, 돌연변이, 적응도)
// V0.5 지휘(이동/방어/공격/후퇴 명령, 카메라, 통계 그래프)  FINAL 시각 효과, 게임 모드, 안정성
//
// 조작 : 좌클릭 이동 명령, 우클릭 방어 명령, Q 공격 명령, E 후퇴 명령, 마우스 휠 확대/축소, WASD 화면 이동,
//        SPACE 일시정지, 1/2/3 지휘할 종족 선택, 0 관찰 모드(전 종족 AI), M 게임 모드, F 효과 수준, TAB 그래프, G 공간 격자, T 잔상,
//        H HUD, R 재시작, N 새 시드, , . 배속, UP/DOWN 지휘 종족 개체 +-50 (디버그)
//
// 시작은 관찰 모드다(세 종족 모두 AI). 지휘는 관찰자가 개입하는 보조 기능이며, 명령은 지휘 중인 종족이 있을 때만 받는다.

PFont uiFont;
World world;
Renderer rdr;
Camera cam;
Hud hud;
Metrics metrics;
Effects fx;
GameMode gm;

int player = -1;                    // 플레이어가 지휘하는 종족 (-1 = 관찰 모드, 모두 AI)
float timeScale = 1;
boolean isPaused;
int lastMs;
boolean kw, ka, ks, kd;             // 화면 이동 키

void setup() {
  size(1200, 800);
  frameRate(60);
  surface.setTitle("SWARM WAR");
  uiFont = createFont("Malgun Gothic", 16);
  textFont(uiFont);

  world = new World(DEFAULT_SEED);
  world.setPlayer(player);
  rdr = new Renderer();
  cam = new Camera();
  cam.fit(width, height);
  hud = new Hud();
  metrics = new Metrics();
  fx = new Effects();
  gm = new GameMode();
  gm.reset(world);
  lastMs = millis();

  if (SELFTEST) runSelfTest();
}

void draw() {
  if (SELFTEST) {
    selfTestFrame();
    return;
  }

  int now = millis();
  float frameDt = (now - lastMs) / 1000.0;
  lastMs = now;

  float pan = 700 * min(frameDt, 0.1);
  if (kw) cam.pan(0, -pan);
  if (ks) cam.pan(0, pan);
  if (ka) cam.pan(-pan, 0);
  if (kd) cam.pan(pan, 0);

  if (!isPaused) world.update(frameDt, timeScale);
  gm.update(world, player);
  fx.update(world, min(frameDt, 0.1));
  if (frameCount % 15 == 1) {
    metrics.compute(world);
    world.countSpecies();
  }

  rdr.draw(world, cam, player, fx, gm);
  hud.draw(world, metrics, player, timeScale, isPaused, gm, fx);
}

void restart(long seed) {
  world.reset(seed);
  world.setPlayer(player);
  gm.reset(world);
}

void keyPressed() {
  if (keyCode == 'W') kw = true;
  if (keyCode == 'A') ka = true;
  if (keyCode == 'S') ks = true;
  if (keyCode == 'D') kd = true;

  if (keyCode >= '1' && keyCode <= '3') {
    player = keyCode - '1';
    world.setPlayer(player);
  }
  if (keyCode == '0') {                                  // 관찰 모드로 돌아가기 (모두 AI)
    player = -1;
    world.setPlayer(player);
  }
  if (player >= 0) {                                     // 명령은 지휘 중인 종족이 있을 때만
    if (keyCode == 'Q') world.cmd[player].attack(world);
    if (keyCode == 'E') world.cmd[player].retreat();
    if (keyCode == UP) world.setPopulation(player, world.pop[player] + 50);
    if (keyCode == DOWN) world.setPopulation(player, world.pop[player] - 50);
  }
  if (key == ' ') isPaused = !isPaused;
  if (keyCode == 'R') restart(world.seed);
  if (keyCode == 'N') restart(millis() * 7919L + 13);
  if (keyCode == 'M') gm.cycle(world);
  if (keyCode == 'F') fx.cycleLevel();
  if (keyCode == 'G') rdr.showGrid = !rdr.showGrid;
  if (keyCode == 'T') rdr.trails = !rdr.trails;
  if (keyCode == 'H') hud.visible = !hud.visible;
  if (keyCode == TAB) hud.graphs = !hud.graphs;
  if (key == '.') timeScale = min(4, timeScale * 2);
  if (key == ',') timeScale = max(0.25, timeScale / 2);
  metrics.compute(world);
}

void keyReleased() {
  if (keyCode == 'W') kw = false;
  if (keyCode == 'A') ka = false;
  if (keyCode == 'S') ks = false;
  if (keyCode == 'D') kd = false;
}

// 좌클릭 = 이동 명령, 우클릭 = 방어 명령 (HUD 위는 제외)
void mousePressed() {
  if (player < 0 || hud.hits(mouseX, mouseY)) return;    // 관찰 모드에서는 클릭 명령 없음
  float wx = cam.toWorldX(mouseX), wy = cam.toWorldY(mouseY);
  if (mouseButton == LEFT) world.cmd[player].moveTo(wx, wy);
  else if (mouseButton == RIGHT) world.cmd[player].defendAt(wx, wy);
}

void mouseWheel(processing.event.MouseEvent event) {
  cam.zoomAt(mouseX, mouseY, pow(1.1, -event.getCount()));
}
