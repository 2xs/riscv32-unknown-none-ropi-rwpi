__thread int tls_counter = 3;

int *tls_ptr_sink;

int main(void) {
  tls_ptr_sink = &tls_counter;
  return 0;
}
