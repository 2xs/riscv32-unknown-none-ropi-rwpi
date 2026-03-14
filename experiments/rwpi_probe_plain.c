__attribute__((section(".rwpi"))) unsigned char __rwpi_anchor = 0;
int g = 42;
int z;

int *get_g(void) {
  return &g;
}

int load_g(void) {
  return g + z;
}
