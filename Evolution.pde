// 유전 알고리즘. 선택은 별도의 '진화 단계'가 아니라 생존과 번식 결과로 일어난다.
//   - 유전자 7개가 능력치와 행동 성향을 정한다 (능력치가 높을수록 에너지 유지비가 커서 공짜가 아니다)
//   - 번식할 때 근처의 에너지가 높은 같은 종족 개체를 짝으로 골라 균일 교차(Crossover), 이어서 돌연변이(Mutation)
//   - 오래 살고, 자식을 많이 낳고, 많이 잡고, 많이 먹은 개체가 적응도가 높다 (사망 시 평가해 세대별로 기록)

class Evolution {
  float mutRate = MUT_RATE;
  float mutSigma = MUT_SIGMA;

  // 세대별 통계 (그래프용): 태어난 개체의 유전자 합, 사망 개체의 적응도 합
  int[][] genBirths = new int[N_SPECIES][MAX_GEN_TRACK];
  float[][][] genGeneSum = new float[N_SPECIES][MAX_GEN_TRACK][NGENE];
  float[][] genFitSum = new float[N_SPECIES][MAX_GEN_TRACK];
  int[][] genDeaths = new int[N_SPECIES][MAX_GEN_TRACK];

  // 선택 압력 측정 : 사망한 개체들의 (유전자 값, 적응도) 통계 -> 피어슨 상관
  int[] selN = new int[N_SPECIES];
  double[] selSumF = new double[N_SPECIES];
  double[] selSumF2 = new double[N_SPECIES];
  double[][] selSumG = new double[N_SPECIES][NGENE];
  double[][] selSumG2 = new double[N_SPECIES][NGENE];
  double[][] selSumGF = new double[N_SPECIES][NGENE];

  void reset() {
    for (int s = 0; s < N_SPECIES; s++) {
      selN[s] = 0;
      selSumF[s] = 0;
      selSumF2[s] = 0;
      for (int i = 0; i < NGENE; i++) {
        selSumG[s][i] = 0;
        selSumG2[s][i] = 0;
        selSumGF[s][i] = 0;
      }
      for (int g = 0; g < MAX_GEN_TRACK; g++) {
        genBirths[s][g] = 0;
        genFitSum[s][g] = 0;
        genDeaths[s][g] = 0;
        for (int i = 0; i < NGENE; i++) genGeneSum[s][g][i] = 0;
      }
    }
  }

  float mult(float g) { return 0.6 + 0.8 * g; }

  // 유전자 -> 실제 능력치. 비용: 속도/공격/방어/감지가 높을수록 유지비가 늘어난다.
  void apply(Agent a, Species s) {
    float mSpeed = mult(a.gene[GN_SPEED]);
    float mAtk = mult(a.gene[GN_ATK]);
    float mDef = mult(a.gene[GN_DEF]);
    float mPerc = mult(a.gene[GN_PERC]);
    a.speedMax = s.maxSpeed * mSpeed;
    a.atk = s.attack * mAtk;
    a.def = s.defense * mDef;
    a.perception = min(CELL, s.perception * mPerc);
    a.aggression = s.aggression * mult(a.gene[GN_AGGR]);
    a.evasion = s.evasion * mult(a.gene[GN_EVADE]);
    a.flockMul = mult(a.gene[GN_FLOCK]);
    a.costMul = 1 + 0.40 * (mSpeed - 1) + 0.40 * (mAtk - 1) + 0.30 * (mDef - 1) + 0.25 * (mPerc - 1);
  }

  // 초기 개체 : 종족 기본값(0.5) 주변의 작은 변이
  void initGenes(World w, Agent a) {
    for (int i = 0; i < NGENE; i++) a.gene[i] = constrain(0.5 + (float) w.rng.nextGaussian() * INIT_GENE_SIGMA, 0, 1);
    apply(a, w.species[a.species]);
  }

  float mutate(java.util.Random rng, float g) {
    if (rng.nextFloat() < mutRate) g += (float) rng.nextGaussian() * mutSigma;
    return constrain(g, 0, 1);
  }

  // 자식의 유전자 : 짝이 있으면 균일 교차(유전자마다 부모 중 한쪽을 무작위로), 없으면 복제. 그 뒤 돌연변이.
  void breed(World w, Agent child, Agent p, Agent m) {
    for (int i = 0; i < NGENE; i++) {
      float g = p.gene[i];
      if (m != null && w.rng.nextBoolean()) g = m.gene[i];
      child.gene[i] = mutate(w.rng, g);
    }
    child.gen = (m != null ? max(p.gen, m.gen) : p.gen) + 1;
    apply(child, w.species[child.species]);
    recordBirth(child);
  }

  void recordBirth(Agent a) {
    int g = min(a.gen, MAX_GEN_TRACK - 1);
    genBirths[a.species][g]++;
    for (int i = 0; i < NGENE; i++) genGeneSum[a.species][g][i] += a.gene[i];
  }

  // 적응도 = 생존 시간 + 번식 x 30 + 처치 x 12 + 섭취 x 1.5
  float fitness(Agent a) {
    return a.age + 30.0 * a.offspring + 12.0 * a.kills + 1.5 * a.eaten;
  }

  void onDeath(Agent a) {
    int g = min(a.gen, MAX_GEN_TRACK - 1);
    float f = fitness(a);
    genFitSum[a.species][g] += f;
    genDeaths[a.species][g]++;

    int s = a.species;
    selN[s]++;
    selSumF[s] += f;
    selSumF2[s] += (double) f * f;
    for (int i = 0; i < NGENE; i++) {
      double v = a.gene[i];
      selSumG[s][i] += v;
      selSumG2[s][i] += v * v;
      selSumGF[s][i] += v * f;
    }
  }

  // 종족 s의 평균 적응도 (사망한 개체 기준, 진화 모드의 승패 판정에 쓴다)
  float meanFitness(int s) {
    return selN[s] > 0 ? (float) (selSumF[s] / selN[s]) : 0;
  }

  // 종족 s에서 유전자 i의 값과 적응도의 상관 (-1 ~ +1). 양수면 그 형질이 유리한 환경이다.
  float selection(int s, int i) {
    int n = selN[s];
    if (n < 30) return 0;
    double mg = selSumG[s][i] / n, mf = selSumF[s] / n;
    double cov = selSumGF[s][i] / n - mg * mf;
    double vg = selSumG2[s][i] / n - mg * mg;
    double vf = selSumF2[s] / n - mf * mf;
    if (vg < 1e-12 || vf < 1e-12) return 0;
    return (float) (cov / Math.sqrt(vg * vf));
  }

  // 세대 g에 태어난 개체들의 평균 유전자 (없으면 -1)
  float genMean(int s, int g, int gene) {
    return genBirths[s][g] > 0 ? genGeneSum[s][g][gene] / genBirths[s][g] : -1;
  }

  float genFitness(int s, int g) {
    return genDeaths[s][g] > 0 ? genFitSum[s][g] / genDeaths[s][g] : -1;
  }
}
