// Freestanding Wasm needs no libc/WASI imports. Volatile prevents
// loop-to-libcall lowering.
#include <stddef.h>
extern "C" void *memset(void *destination, int value, size_t size) {
  auto *d = static_cast<volatile unsigned char *>(destination);
  for (size_t i = 0; i < size; i++)
    d[i] = static_cast<unsigned char>(value);
  return destination;
}
extern "C" void *memcpy(void *destination, const void *source, size_t size) {
  auto *d = static_cast<volatile unsigned char *>(destination);
  auto *s = static_cast<const volatile unsigned char *>(source);
  for (size_t i = 0; i < size; i++)
    d[i] = s[i];
  return destination;
}
