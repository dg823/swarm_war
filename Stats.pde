// 그래프용 통계. 시뮬레이션 시간으로 1초마다 한 번 기록한다 (최근 4분).

class Stats {
  final int N = 240;
  float[][] pop = new float[N_SPECIES][N];     // 종족별 개체 수
  float[] foodGen = new float[N];              // 초당 먹이 생성량 (자연 생성 + 시체)
  float[] foodCon = new float[N];              // 초당 먹이 소비량
  int len;
  long lastGen, lastCon;

  void reset() {
    len = 0;
    lastGen = 0;
    lastCon = 0;
  }

  void sample(World w) {
    if (len == N) {                            // 가득 차면 한 칸씩 밀어낸다
      for (int s = 0; s < N_SPECIES; s++) System.arraycopy(pop[s], 1, pop[s], 0, N - 1);
      System.arraycopy(foodGen, 1, foodGen, 0, N - 1);
      System.arraycopy(foodCon, 1, foodCon, 0, N - 1);
      len = N - 1;
    }
    w.countSpecies();
    for (int s = 0; s < N_SPECIES; s++) pop[s][len] = w.pop[s];
    long g = w.eco.generated + w.eco.corpses;
    long c = w.eco.consumed;
    foodGen[len] = g - lastGen;
    foodCon[len] = c - lastCon;
    lastGen = g;
    lastCon = c;
    len++;
  }

  // 전투 승률 = 처치 / (처치 + 사망)
  float winRate(World w, int s) {
    int k = w.kills[s], d = w.deaths[s];
    return k + d > 0 ? k / (float) (k + d) : 0;
  }

  // 생존율 = 현재 개체 수 / (시작 개체 수 + 출생)
  float survival(World w, int s) {
    return w.pop[s] / (float) (INITIAL_PER_SPECIES + w.eco.births[s]);
  }
}
