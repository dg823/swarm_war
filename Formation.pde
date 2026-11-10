// V0.6 진형 (Formation)
//
// 진형은 개체를 고정 좌표에 박지 않는다. 분대(Squad) 중심과 방향을 기준으로 한 '슬롯'을 정하고,
// 그 슬롯으로 가려는 힘을 Boids 조향력의 한 항으로 더할 뿐이다. 분리/정렬/전투/채집은 그대로 살아 있다.
// 교전하면 슬롯 힘이 약해져 진형이 무너지고, 교전이 끝나면 서서히 재정비된다.
// 진형 NONE이 기본이고(명령이 없으면 AUTO도 NONE), 그때 동작은 V0.5와 같다.

final int FM_AUTO = -1, FM_NONE = 0, FM_LINE = 1, FM_WEDGE = 2, FM_CIRCLE = 3, FM_COLUMN = 4, FM_SCATTER = 5;
final int N_FORMS = 6;

final float FORM_W = 1.6;               // 슬롯 힘 가중치
final float FORM_GAIN = 1.5;            // 슬롯 오차 1px당 원하는 보정 속도 (1/s)
final int SQUAD_PERIOD = 12;            // 분대 갱신 주기 (스텝) = 5Hz
final int SQUAD_SIZE = 70;              // 분대 하나의 목표 인원
final int MAX_SQUADS_PER_SPECIES = 12;
final int SQUAD_STRIDE = 16;            // 종족 s의 분대는 sq[s * 16 ..]
final int MAX_SQUADS = 48;
final float FORM_BLEND_TIME = 2.0;      // 진형 전환 블렌드 (초)
final float ENGAGE_HOLD = 1.5;          // 교전이 끝나고 재정비를 시작하기까지 (초)
final float REFORM_RATE = 0.5;          // 재정비 속도 (1/s)
final float FORM_COH_CUT = 0.7;         // 진형 중 응집 가중치 감소 비율
final float SQUAD_TURN = 1.5;           // 분대 방향 회전 속도 상한 (rad/s)

// 장애물 (원형)
final int MAX_OBS = 12;

String formName(int f) {
  if (f == FM_AUTO) return "자동";
  String[] n = {"없음", "횡대", "쐐기", "원형", "종대", "산개"};
  return n[f];
}

// AUTO일 때 명령에 맞는 진형 : 없음=NONE, 이동=종대, 공격=쐐기, 방어=원형, 후퇴=산개
int autoFormation(int order) {
  if (order == ORD_MOVE) return FM_COLUMN;
  if (order == ORD_ATTACK) return FM_WEDGE;
  if (order == ORD_DEFEND) return FM_CIRCLE;
  if (order == ORD_RETREAT) return FM_SCATTER;
  return FM_NONE;
}

// 진형 순환 (Z) : 자동 -> 없음 -> 횡대 -> 쐐기 -> 원형 -> 종대 -> 산개 -> 자동
int nextFormSetting(int f) {
  return f >= FM_SCATTER ? FM_AUTO : f + 1;
}

// ---------- 슬롯 기하 (순수 함수) ----------
// 분대 좌표계 : u = 진행 방향(앞이 +), v = 오른쪽 수직 방향. 결과는 전역 fmU, fmV에 넣는다 (할당 없음).
// k번째 슬롯 (0 <= k < n), gap = 슬롯 간격. 정규화(평균 0)는 분대가 한다.
// 슬롯 순서는 앞줄부터 (원형은 바깥 고리부터).

float fmU, fmV;

void slotLocal(int form, int k, int n, float gap) {
  fmU = 0;
  fmV = 0;
  if (n <= 0) return;
  if (form == FM_LINE) {                                     // 넓고 얕은 줄 (깊이 ~ sqrt(n/4))
    int ranks = max(1, round(sqrt(n / 4.0)));
    int per = ceil(n / (float) ranks);
    int r = k / per, c = k % per;
    int inRank = min(per, n - r * per);
    fmU = -r * gap;
    fmV = (c - (inRank - 1) * 0.5) * gap;
  } else if (form == FM_COLUMN) {                            // 좁고 긴 종대
    int files = max(1, round(sqrt(n / 4.0)));
    int r = k / files, c = k % files;
    int inRow = min(files, n - r * files);
    fmU = -r * gap;
    fmV = (c - (inRow - 1) * 0.5) * gap;
  } else if (form == FM_WEDGE) {                             // 쐐기 : r번째 줄에 2r+1 슬롯, 꼭짓점이 앞
    int r = (int) sqrt(k);
    while ((r + 1) * (r + 1) <= k) r++;
    while (r * r > k) r--;
    int c = k - r * r;
    int inRow = min(2 * r + 1, n - r * r);
    fmU = -r * gap;
    fmV = (c - (inRow - 1) * 0.5) * gap;
  } else if (form == FM_CIRCLE) {                            // 동심원, 바깥 고리부터 채운다 (가운데가 빌 수 있다)
    int R = 0, total = 1;
    while (total < n) {
      R++;
      total += ringCap(R);
    }
    int idx = k;
    for (int j = R; j >= 0; j--) {
      int cap = ringCap(j);
      if (idx < cap) {
        int filledBefore = 0;
        for (int q = R; q > j; q--) filledBefore += ringCap(q);
        int m = min(cap, n - filledBefore);
        float a = TWO_PI * idx / max(1, m) + (j % 2) * PI / max(1, m);
        fmU = cos(a) * j * gap;
        fmV = sin(a) * j * gap;
        return;
      }
      idx -= cap;
    }
  } else if (form == FM_SCATTER) {                           // 넓은 간격 + 결정적 흩뿌림 (난수 미사용)
    float g2 = gap * 2.2;
    int side = max(1, ceil(sqrt(n)));
    int r = k / side, c = k % side;
    int inRow = min(side, n - r * side);
    fmU = -r * g2 + (((k * 37) % 11) - 5) / 5.0 * 0.2 * g2;
    fmV = (c - (inRow - 1) * 0.5) * g2 + (((k * 59) % 13) - 6) / 6.0 * 0.2 * g2;
  }
}

int ringCap(int j) {
  return j == 0 ? 1 : (int) (TWO_PI * j);
}
