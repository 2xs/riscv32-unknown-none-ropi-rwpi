#include <stdint.h>

enum {
  SEMI_SYS_EXIT = 0x18,
  SEMI_SYS_EXIT_EXTENDED = 0x20,
  ADP_STOPPED_APPLICATION_EXIT = 0x20026,
};

extern char __text_start[];

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

static int plus(void) { return 1; }

static uintptr_t runtime_probe(void) {
  uintptr_t pc;
  asm volatile(
      ".option push\n"
      ".option norvc\n"
      "auipc %0, 0\n"
      ".option pop\n"
      : "=r"(pc));
  return pc;
}

uintptr_t linked_text_start = (uintptr_t)__text_start;
uintptr_t linked_runtime_probe = (uintptr_t)runtime_probe;
uintptr_t linked_plus = (uintptr_t)plus;
int (*rw_fn)(void) = plus;
int (*const ro_fn)(void) = plus;

int main(void) {
  uintptr_t runtime_probe_addr = runtime_probe();
  uintptr_t runtime_text_start =
      runtime_probe_addr - (linked_runtime_probe - linked_text_start);
  uintptr_t runtime_plus = runtime_text_start + (linked_plus - linked_text_start);

  if ((uintptr_t)rw_fn == linked_plus && (uintptr_t)ro_fn == linked_plus &&
      runtime_plus != linked_plus) {
    semihost_exit(0);
  }

  semihost_exit(1);
}
