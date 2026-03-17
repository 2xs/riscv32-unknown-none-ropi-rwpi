int target = 7;
int *pg = &target;

int load_target_through_pg(void) {
  return *pg;
}

void store_target_through_pg(int x) {
  *pg = x;
}
