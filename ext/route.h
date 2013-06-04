#pragma once

#include <http_parser.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  VALUE controller;
  VALUE args;
  VALUE scope;
} RouteResult;

extern void Init_route(VALUE ext);
extern RouteResult lookup_route(enum http_method method_num, VALUE vpath);

#ifdef __cplusplus
}
#endif
