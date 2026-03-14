__attribute__((section(".rwpi"))) unsigned char __rwpi_anchor = 0;
__attribute__((section(".rwpi"))) int g = 42;

int *get_g(void) {
  return &g;
}

int load_g(void) {
  return g;
}
