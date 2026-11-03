// 월드 <-> 화면 변환, 이동(WASD)과 확대/축소(마우스 휠).

class Camera {
  float zoom = 1, minZoom = 0.5, maxZoom = 4;
  float cx, cy;                     // 화면 중앙에 오는 월드 좌표
  float viewW, viewH;

  // 월드 전체가 창에 들어오도록 맞춘다 (이 배율이 최소 배율)
  void fit(float vw, float vh) {
    viewW = vw;
    viewH = vh;
    minZoom = min(vw / WORLD_W, vh / WORLD_H);
    zoom = minZoom;
    cx = WORLD_W / 2;
    cy = WORLD_H / 2;
  }

  float toWorldX(float sx) { return (sx - viewW / 2) / zoom + cx; }
  float toWorldY(float sy) { return (sy - viewH / 2) / zoom + cy; }
  float toScreenX(float wx) { return (wx - cx) * zoom + viewW / 2; }
  float toScreenY(float wy) { return (wy - cy) * zoom + viewH / 2; }

  // (sx, sy) 화면 위치가 가리키는 월드 점이 제자리에 있도록 확대/축소
  void zoomAt(float sx, float sy, float factor) {
    float wx = toWorldX(sx), wy = toWorldY(sy);
    zoom = constrain(zoom * factor, minZoom, maxZoom);
    cx = wx - (sx - viewW / 2) / zoom;
    cy = wy - (sy - viewH / 2) / zoom;
    clampCenter();
  }

  // 화면 픽셀 단위로 이동
  void pan(float dxScreen, float dyScreen) {
    cx += dxScreen / zoom;
    cy += dyScreen / zoom;
    clampCenter();
  }

  // 보이는 영역이 월드 밖으로 나가지 않게
  void clampCenter() {
    float hw = viewW / (2 * zoom), hh = viewH / (2 * zoom);
    cx = hw * 2 >= WORLD_W ? WORLD_W / 2 : constrain(cx, hw, WORLD_W - hw);
    cy = hh * 2 >= WORLD_H ? WORLD_H / 2 : constrain(cy, hh, WORLD_H - hh);
  }

  // 지금 보이는 월드 영역 (여유 margin 포함)
  float left(float margin) { return cx - viewW / (2 * zoom) - margin; }
  float right(float margin) { return cx + viewW / (2 * zoom) + margin; }
  float top(float margin) { return cy - viewH / (2 * zoom) - margin; }
  float bottom(float margin) { return cy + viewH / (2 * zoom) + margin; }

  // 이후 월드 좌표로 그리면 화면에 맞게 변환된다 (pushMatrix/popMatrix로 감쌀 것)
  void apply() {
    translate(viewW / 2, viewH / 2);
    scale(zoom);
    translate(-cx, -cy);
  }
}
