int g[16];

int load_gi(int i) {
  return g[i];
}

void store_gi(int i, int x) {
  g[i] = x;
}
