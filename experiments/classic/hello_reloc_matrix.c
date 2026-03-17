#include <stdint.h>

enum {
  SEMI_SYS_WRITE0 = 0x04,
  SEMI_SYS_EXIT = 0x18,
  SEMI_SYS_EXIT_EXTENDED = 0x20,
  ADP_STOPPED_APPLICATION_EXIT = 0x20026,
};

struct data_pair {
  int *first;
  int *second;
};

struct fn_pair {
  int (*first)(void);
  int (*second)(void);
};

static long semihost_call(long op, void *arg) {
  register long a0 asm("a0") = op;
  register void *a1 asm("a1") = arg;

  asm volatile(
      ".option push\n"
      ".option norvc\n"
      "slli zero, zero, 0x1f\n"
      "ebreak\n"
      "srai zero, zero, 7\n"
      ".option pop\n"
      : "+r"(a0)
      : "r"(a1)
      : "memory");

  return a0;
}

static void semihost_write0(const char *s) {
  semihost_call(SEMI_SYS_WRITE0, (void *)s);
}

__attribute__((noreturn)) static void semihost_exit(int code) {
  struct {
    int reason;
    int subcode;
  } block = {ADP_STOPPED_APPLICATION_EXIT, code};

  semihost_call(SEMI_SYS_EXIT_EXTENDED, &block);
  semihost_call(SEMI_SYS_EXIT, (void *)(uintptr_t)code);

  for (;;)
    ;
}

#define CHECK(expr, msg)                                                      \
  do {                                                                        \
    if (!(expr)) {                                                            \
      semihost_write0(msg "\n");                                              \
      semihost_exit(1);                                                       \
    }                                                                         \
  } while (0)

int target_a = 11;
int target_b = 23;
int target_c = 37;
int zero_cell;
unsigned char zeros[4];

int *rw_ptr = &target_a;
int *rw_ptr_array[2] = {&target_a, &target_b};
struct data_pair rw_pair = {&target_b, &target_c};
int **rw_ptr_to_ptr = &rw_ptr;

int fn0(void) {
  return 101;
}

int fn1(void) {
  return 202;
}

int (*rw_fn)(void) = fn0;
int (*rw_fn_array[2])(void) = {fn0, fn1};
struct fn_pair rw_fn_pair = {fn0, fn1};
int (**rw_fn_to_ptr)(void) = &rw_fn;

int *const ro_ptr = &target_a;
int *const ro_ptr_array[2] = {&target_a, &target_b};
const struct data_pair ro_pair = {&target_b, &target_c};
int *const *const ro_ptr_to_ptr = &rw_ptr;

int (*const ro_fn)(void) = fn0;
int (*const ro_fn_array[2])(void) = {fn0, fn1};
const struct fn_pair ro_fn_pair = {fn0, fn1};
int (*const *const ro_fn_to_ptr)(void) = &rw_fn;

static void check_zero_init(void) {
  CHECK(zero_cell == 0, "zero_cell init failed");
  CHECK(zeros[0] == 0, "zeros[0] init failed");
  CHECK(zeros[1] == 0, "zeros[1] init failed");
  CHECK(zeros[2] == 0, "zeros[2] init failed");
  CHECK(zeros[3] == 0, "zeros[3] init failed");
}

static void check_rw_data_relocs(void) {
  CHECK(rw_ptr == &target_a, "rw_ptr value failed");
  CHECK(*rw_ptr == 11, "rw_ptr deref failed");
  CHECK(rw_ptr_array[0] == &target_a, "rw_ptr_array[0] value failed");
  CHECK(rw_ptr_array[1] == &target_b, "rw_ptr_array[1] value failed");
  CHECK(*rw_ptr_array[0] == 11, "rw_ptr_array[0] deref failed");
  CHECK(*rw_ptr_array[1] == 23, "rw_ptr_array[1] deref failed");
  CHECK(rw_pair.first == &target_b, "rw_pair.first value failed");
  CHECK(rw_pair.second == &target_c, "rw_pair.second value failed");
  CHECK(*rw_pair.first == 23, "rw_pair.first deref failed");
  CHECK(*rw_pair.second == 37, "rw_pair.second deref failed");
  CHECK(rw_ptr_to_ptr == &rw_ptr, "rw_ptr_to_ptr value failed");
  CHECK(*rw_ptr_to_ptr == &target_a, "rw_ptr_to_ptr deref failed");
}

static void check_ro_data_relocs(void) {
  CHECK(ro_ptr == &target_a, "ro_ptr value failed");
  CHECK(*ro_ptr == 11, "ro_ptr deref failed");
  CHECK(ro_ptr_array[0] == &target_a, "ro_ptr_array[0] value failed");
  CHECK(ro_ptr_array[1] == &target_b, "ro_ptr_array[1] value failed");
  CHECK(*ro_ptr_array[0] == 11, "ro_ptr_array[0] deref failed");
  CHECK(*ro_ptr_array[1] == 23, "ro_ptr_array[1] deref failed");
  CHECK(ro_pair.first == &target_b, "ro_pair.first value failed");
  CHECK(ro_pair.second == &target_c, "ro_pair.second value failed");
  CHECK(*ro_pair.first == 23, "ro_pair.first deref failed");
  CHECK(*ro_pair.second == 37, "ro_pair.second deref failed");
  CHECK(ro_ptr_to_ptr == &rw_ptr, "ro_ptr_to_ptr value failed");
  CHECK(*ro_ptr_to_ptr == &target_a, "ro_ptr_to_ptr deref failed");
}

static void check_rw_fn_relocs(void) {
  CHECK(rw_fn == fn0, "rw_fn value failed");
  CHECK(rw_fn() == 101, "rw_fn call failed");
  CHECK(rw_fn_array[0] == fn0, "rw_fn_array[0] value failed");
  CHECK(rw_fn_array[1] == fn1, "rw_fn_array[1] value failed");
  CHECK(rw_fn_array[0]() == 101, "rw_fn_array[0] call failed");
  CHECK(rw_fn_array[1]() == 202, "rw_fn_array[1] call failed");
  CHECK(rw_fn_pair.first == fn0, "rw_fn_pair.first value failed");
  CHECK(rw_fn_pair.second == fn1, "rw_fn_pair.second value failed");
  CHECK(rw_fn_pair.first() == 101, "rw_fn_pair.first call failed");
  CHECK(rw_fn_pair.second() == 202, "rw_fn_pair.second call failed");
  CHECK(rw_fn_to_ptr == &rw_fn, "rw_fn_to_ptr value failed");
  CHECK((*rw_fn_to_ptr)() == 101, "rw_fn_to_ptr call failed");
}

static void check_ro_fn_relocs(void) {
  CHECK(ro_fn == fn0, "ro_fn value failed");
  CHECK(ro_fn() == 101, "ro_fn call failed");
  CHECK(ro_fn_array[0] == fn0, "ro_fn_array[0] value failed");
  CHECK(ro_fn_array[1] == fn1, "ro_fn_array[1] value failed");
  CHECK(ro_fn_array[0]() == 101, "ro_fn_array[0] call failed");
  CHECK(ro_fn_array[1]() == 202, "ro_fn_array[1] call failed");
  CHECK(ro_fn_pair.first == fn0, "ro_fn_pair.first value failed");
  CHECK(ro_fn_pair.second == fn1, "ro_fn_pair.second value failed");
  CHECK(ro_fn_pair.first() == 101, "ro_fn_pair.first call failed");
  CHECK(ro_fn_pair.second() == 202, "ro_fn_pair.second call failed");
  CHECK(ro_fn_to_ptr == &rw_fn, "ro_fn_to_ptr value failed");
  CHECK((*ro_fn_to_ptr)() == 101, "ro_fn_to_ptr call failed");
}

int main(void) {
  check_zero_init();
  check_rw_data_relocs();
  check_ro_data_relocs();
  check_rw_fn_relocs();
  check_ro_fn_relocs();
  semihost_write0("RWPI relocation matrix OK\n");
  semihost_exit(0);
}
