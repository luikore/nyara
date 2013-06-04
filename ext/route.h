#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  VALUE controller;
  VALUE args;
  VALUE scope;
} RouteResult;

extern void Init_route(VALUE ext);
extern RouteResult lookup_route(const char* pathinfo, long len);

#ifdef __cplusplus
}
#endif
