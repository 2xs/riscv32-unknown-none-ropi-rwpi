int g = 42;

int *get_g(void) {
  return &g;
}

int load_g(void) {
  return g;
}

void store_g(int x) {
  g = x;
}
