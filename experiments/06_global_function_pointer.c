int f(void) {
  return 7;
}

int (*pf)(void) = f;

int call_pf(void) {
  return pf();
}
