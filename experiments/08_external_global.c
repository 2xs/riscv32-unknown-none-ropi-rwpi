extern int ext;

int *get_ext(void) {
  return &ext;
}

int load_ext(void) {
  return ext;
}
