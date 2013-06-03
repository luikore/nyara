#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  VALUE controller;
  VALUE args;
  VALUE scope;
} RouteResult;

extern VALUE request_register_route(VALUE, VALUE);
extern VALUE request_clear_route(VALUE);
extern void init_route();
extern RouteResult search_route(VALUE pathinfo);

// for debug
extern VALUE request_inspect_route(VALUE);
extern VALUE request_search_route(VALUE, VALUE);

#ifdef __cplusplus
}
#endif
