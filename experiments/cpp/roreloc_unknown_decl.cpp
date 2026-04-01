extern const int target;
extern const int *const p;

const int *const *get_p_addr() {
  return &p;
}
