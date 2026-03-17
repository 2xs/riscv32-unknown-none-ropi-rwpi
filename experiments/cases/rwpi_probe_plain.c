int g = 42;
int z;

int *get_g(void) {
  return &g;
}

int load_g(void) {
  return g + z;
}
