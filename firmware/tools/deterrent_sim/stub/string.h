#pragma once
typedef unsigned long size_t;
extern "C" {
int strcmp(const char *a, const char *b);
size_t strlen(const char *s);
void *memset(void *p, int c, size_t n);
size_t strlcpy(char *dst, const char *src, size_t n);
int snprintf(char *b, unsigned long n, const char *fmt, ...);
}
