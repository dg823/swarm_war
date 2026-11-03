// 균일 격자(Uniform Grid) 공간 분할. 매 스텝 카운팅 정렬로 다시 만든다. 할당 없음.
//   셀 c에 속한 개체 인덱스 = order[cellStart[c] .. cellStart[c + 1] - 1]

class SpatialGrid {
  float cell, invCell;
  int cols, rows, nCells;
  int[] cellStart;                  // nCells + 1
  int[] fillPos;                    // 정렬용 임시 위치
  int[] cellOf;                     // 개체 인덱스 -> 셀
  int[] order;                      // 셀 순서로 정렬된 개체 인덱스

  SpatialGrid(float worldW, float worldH, float cell, int capacity) {
    this.cell = cell;
    invCell = 1.0 / cell;
    cols = ceil(worldW / cell);
    rows = ceil(worldH / cell);
    nCells = cols * rows;
    cellStart = new int[nCells + 1];
    fillPos = new int[nCells];
    cellOf = new int[capacity];
    order = new int[capacity];
  }

  int cellX(float x) {
    int c = (int) (x * invCell);
    return c < 0 ? 0 : (c >= cols ? cols - 1 : c);
  }

  int cellY(float y) {
    int c = (int) (y * invCell);
    return c < 0 ? 0 : (c >= rows ? rows - 1 : c);
  }

  void build(Agent[] a, int n) {
    java.util.Arrays.fill(cellStart, 0);
    for (int i = 0; i < n; i++) {
      int c = cellY(a[i].y) * cols + cellX(a[i].x);
      cellOf[i] = c;
      cellStart[c + 1]++;
    }
    for (int c = 0; c < nCells; c++) cellStart[c + 1] += cellStart[c];
    System.arraycopy(cellStart, 0, fillPos, 0, nCells);
    for (int i = 0; i < n; i++) order[fillPos[cellOf[i]]++] = i;
  }

  // 반경 r(<= cell) 안의 개체 인덱스를 out에 채우고 개수를 돌려준다. 검증과 비핫패스용.
  int queryRadius(Agent[] a, float x, float y, float r, int exclude, int[] out) {
    int cx = cellX(x), cy = cellY(y);
    float r2 = r * r;
    int cnt = 0;
    for (int gy = max(0, cy - 1); gy <= min(rows - 1, cy + 1); gy++) {
      for (int gx = max(0, cx - 1); gx <= min(cols - 1, cx + 1); gx++) {
        int c = gy * cols + gx;
        for (int k = cellStart[c]; k < cellStart[c + 1]; k++) {
          int j = order[k];
          if (j == exclude) continue;
          float dx = a[j].x - x, dy = a[j].y - y;
          if (dx * dx + dy * dy < r2) out[cnt++] = j;
        }
      }
    }
    return cnt;
  }
}
