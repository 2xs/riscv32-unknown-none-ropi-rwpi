const int c = 7;

const int *get_c(void) {
  return &c;
}

int load_c(void) {
  return c;
}
