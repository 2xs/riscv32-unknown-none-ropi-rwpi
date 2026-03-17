#include <stdint.h>

enum {
  SEMI_SYS_WRITE0 = 0x04,
  SEMI_SYS_EXIT = 0x18,
  SEMI_SYS_EXIT_EXTENDED = 0x20,
  ADP_STOPPED_APPLICATION_EXIT = 0x20026,
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

int alpha = 7;
int beta = 9;
int *rw_ptr = &alpha;
int *rw_pair[2] = {&alpha, &beta};

const int *const ro_ptr = &alpha;
const int *const ro_pair[2] = {&alpha, &beta};

static int plus(void) { return alpha + beta; }

int (*rw_fn)(void) = plus;
int (*const ro_fn)(void) = plus;

static int self_check(void) {
  return rw_ptr == &alpha && rw_pair[0] == &alpha && rw_pair[1] == &beta &&
         ro_ptr == &alpha && ro_pair[0] == &alpha && ro_pair[1] == &beta &&
         rw_fn == plus && ro_fn == plus && *rw_ptr == 7 && *ro_pair[1] == 9 &&
         rw_fn() == 16 && ro_fn() == 16;
}

int main(void) {
  if (self_check()) {
    semihost_write0("House blob RWPI runtime OK\n");
    semihost_exit(0);
  }

  semihost_write0("House blob RWPI runtime FAILED\n");
  semihost_exit(1);
}
