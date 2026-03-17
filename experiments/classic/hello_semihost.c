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

int g = 41;
int z;
unsigned char zeros[4];
char greeting[] = "Hello from RWPI semihosting\n";

int main(void) {
  if (g == 41 && z == 0 && zeros[0] == 0 && zeros[1] == 0 && zeros[2] == 0 &&
      zeros[3] == 0) {
    semihost_write0(greeting);
    semihost_exit(0);
  }

  semihost_write0("RWPI startup self-check failed\n");
  semihost_exit(1);
}
