struct pair {
  int x;
  int y;
};

struct pair g = {1, 2};

int load_gy(void) {
  return g.y;
}

void store_gx(int x) {
  g.x = x;
}
