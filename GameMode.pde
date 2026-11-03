// 게임 모드. 시뮬레이션 규칙은 같고, 승패 조건만 다르다.
//   FREE      자유 시뮬레이션 : 끝이 없다
//   SURVIVAL  생존 : 마지막까지 살아남는 종족이 승리
//   CONQUEST  점령 : 오아시스 7곳 중 많이 차지한 종족이 점수를 얻는다. 500점 먼저 얻거나 10분 뒤 최고 점수가 승리
//   EVOLUTION 진화 : 어느 종족이든 평균 세대가 12에 이르면(또는 15분) 평균 적응도가 가장 높은 종족이 승리
//   COMMAND   지휘 : 플레이어 종족이 다른 종족을 모두 멸종시키거나, 전체의 70%를 30초 지키면 승리. 멸종하면 패배

final int MODE_FREE = 0, MODE_SURVIVAL = 1, MODE_CONQUEST = 2, MODE_EVOLUTION = 3, MODE_COMMAND = 4;
final int N_MODES = 5;
final int WIN_NONE = -1, WIN_DRAW = -2, WIN_PLAYER_LOST = -3;

class GameMode {
  int mode = MODE_FREE;
  boolean over;
  int winner = WIN_NONE;
  float elapsed;                              // 모드 시작 후 시뮬레이션 시간 (초)
  long lastStep;
  float[] points = new float[N_SPECIES];      // 점령 점수
  int[] zoneOwner = new int[7];               // 구역 점유자 (-1 중립)
  float dominance;                            // 지휘 모드 : 전체의 70% 이상을 지킨 시간
  final float ZONE_R = 180;
  final float CONQUEST_POINTS = 500, CONQUEST_TIME = 600;
  final float EVO_GEN = 12, EVO_TIME = 900;
  final float COMMAND_SHARE = 0.7, COMMAND_HOLD = 30;

  int[] zoneCnt = new int[N_SPECIES * 7];

  String name() {
    String[] n = {"자유 시뮬레이션", "생존", "점령", "진화", "지휘"};
    return n[mode];
  }

  void setMode(int m, World w) {
    mode = m;
    reset(w);
  }

  void cycle(World w) {
    setMode((mode + 1) % N_MODES, w);
  }

  void reset(World w) {
    over = false;
    winner = WIN_NONE;
    elapsed = 0;
    dominance = 0;
    lastStep = w.stepCount;
    for (int s = 0; s < N_SPECIES; s++) points[s] = 0;
    for (int z = 0; z < zoneOwner.length; z++) zoneOwner[z] = -1;
  }

  int aliveSpecies(World w) {
    int n = 0;
    for (int s = 0; s < N_SPECIES; s++) if (w.pop[s] > 0) n++;
    return n;
  }

  // 프레임마다(또는 시뮬레이션을 진행한 뒤) 호출. 지난 호출 이후 진행된 시뮬레이션 시간만큼만 센다.
  void update(World w, int player) {
    if (w.stepCount < lastStep) lastStep = w.stepCount;       // 월드가 재시작되었다
    float dt = (w.stepCount - lastStep) * DT;
    lastStep = w.stepCount;
    if (mode == MODE_FREE || over) return;
    elapsed += dt;
    w.countSpecies();

    if (mode == MODE_SURVIVAL) {
      int alive = aliveSpecies(w);
      if (alive <= 1) finish(alive == 1 ? onlyAlive(w) : WIN_DRAW);
    } else if (mode == MODE_CONQUEST) {
      updateZones(w);
      for (int z = 0; z < zoneOwner.length; z++) if (zoneOwner[z] >= 0) points[zoneOwner[z]] += dt;
      int lead = leaderByPoints();
      if (points[lead] >= CONQUEST_POINTS || elapsed >= CONQUEST_TIME) finish(points[lead] > 0 ? lead : WIN_DRAW);
    } else if (mode == MODE_EVOLUTION) {
      w.refreshSpeciesStats();
      float g = 0;
      for (int s = 0; s < N_SPECIES; s++) if (w.pop[s] > 0) g = max(g, w.avgGen[s]);
      if (g >= EVO_GEN || elapsed >= EVO_TIME) finish(bestFitness(w));
    } else if (mode == MODE_COMMAND) {
      if (player >= 0 && w.pop[player] == 0) {
        finish(WIN_PLAYER_LOST);
      } else if (player >= 0) {
        if (aliveSpecies(w) == 1) {
          finish(player);
        } else {
          float share = w.pop[player] / (float) max(1, w.count);
          if (share >= COMMAND_SHARE) dominance += dt;
          else dominance = 0;
          if (dominance >= COMMAND_HOLD) finish(player);
        }
      }
    }
  }

  void finish(int win) {
    over = true;
    winner = win;
  }

  int onlyAlive(World w) {
    for (int s = 0; s < N_SPECIES; s++) if (w.pop[s] > 0) return s;
    return WIN_DRAW;
  }

  int leaderByPoints() {
    int best = 0;
    for (int s = 1; s < N_SPECIES; s++) if (points[s] > points[best]) best = s;
    return best;
  }

  // 평균 적응도(사망한 개체 기준)가 가장 높은 종족
  int bestFitness(World w) {
    int best = WIN_DRAW;
    float bf = -1;
    for (int s = 0; s < N_SPECIES; s++) {
      float f = w.evo.meanFitness(s);
      if (f > bf) {
        bf = f;
        best = s;
      }
    }
    return best;
  }

  // 구역 점유 : 구역 안의 개체가 8마리 이상이고, 2위의 1.3배 이상인 종족이 차지한다
  void updateZones(World w) {
    java.util.Arrays.fill(zoneCnt, 0);
    for (int i = 0; i < w.count; i++) {
      Agent a = w.pool[i];
      for (int z = 0; z < zoneOwner.length; z++) {
        float dx = a.x - w.eco.hotX[z], dy = a.y - w.eco.hotY[z];
        if (dx * dx + dy * dy < ZONE_R * ZONE_R) {
          zoneCnt[z * N_SPECIES + a.species]++;
          break;
        }
      }
    }
    for (int z = 0; z < zoneOwner.length; z++) {
      int best = -1, c1 = 0, c2 = 0;
      for (int s = 0; s < N_SPECIES; s++) {
        int c = zoneCnt[z * N_SPECIES + s];
        if (c > c1) {
          c2 = c1;
          c1 = c;
          best = s;
        } else if (c > c2) {
          c2 = c;
        }
      }
      zoneOwner[z] = (c1 >= 8 && c1 >= 1.3 * c2) ? best : -1;
    }
  }

  // 화면에 보일 한 줄 상태
  String status(World w) {
    if (mode == MODE_FREE) return "승패 없음";
    if (mode == MODE_SURVIVAL) return "생존 종족 " + aliveSpecies(w) + "/" + N_SPECIES;
    if (mode == MODE_CONQUEST) {
      String s = "점령 점수 ";
      for (int i = 0; i < N_SPECIES; i++) s += w.species[i].name.charAt(0) + " " + int(points[i]) + "  ";
      return s + "(목표 " + int(CONQUEST_POINTS) + ")";
    }
    if (mode == MODE_EVOLUTION) {
      float g = 0;
      for (int s = 0; s < N_SPECIES; s++) if (w.pop[s] > 0) g = max(g, w.avgGen[s]);
      return "최고 평균 세대 " + nf(g, 1, 1) + " / " + int(EVO_GEN);
    }
    return "지배 유지 " + nf(dominance, 1, 0) + " / " + int(COMMAND_HOLD) + "초 (70% 이상)";
  }

  String resultText(World w) {
    if (winner >= 0) return w.species[winner].name + " 승리!";
    if (winner == WIN_PLAYER_LOST) return "패배 - 지휘 종족 멸종";
    return "무승부";
  }
}
