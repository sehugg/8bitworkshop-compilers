# 2 "test.c"
void *memset(void *s, int c, unsigned int n);

unsigned char buf[16];

int fib(int n) { return n < 2 ? n : fib(n-1) + fib(n-2); }

long mul(long a, long b) { return a * b; }

void main(void) {
  unsigned char i;
  memset(buf, 0, sizeof(buf));
  for (i = 0; i < 16; i++) buf[i] = fib(i) + (unsigned char)mul(i, 3);
}
