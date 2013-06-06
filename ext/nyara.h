#pragma once
#include <ruby.h>
#include <http_parser.h>
#include "status_codes.inc"

/* -- request & response class -- */
void Init_request(VALUE nyara);


/* -- url encoded parse -- */
void Init_url_encoded(VALUE ext);
size_t nyara_parse_path(VALUE path, const char*s, size_t len);


/* -- hashes -- */
void Init_hashes(VALUE nyara);

// ab-cd => Ab-Cd
// note str must be string created by nyara code
void nyara_headerlize(VALUE str);
int nyara_rb_hash_has_key(VALUE hash, VALUE key);

extern VALUE nyara_param_hash_class;
extern VALUE nyara_header_hash_class;
extern VALUE nyara_config_hash_class;


/* -- route -- */
typedef struct {
  VALUE controller;
  VALUE args;
  VALUE scope;
} RouteResult;

extern void Init_route(VALUE nyara, VALUE ext);
extern RouteResult nyara_lookup_route(enum http_method method_num, VALUE vpath);
