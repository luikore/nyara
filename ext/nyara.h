#pragma once
#include <ruby.h>
#include <http_parser.h>
#include "inc/status_codes.inc"

#ifdef DEBUG
#undef NDEBUG
#endif


/* -- event -- */
void Init_event(VALUE ext);


/* -- request & response class -- */
void Init_request(VALUE nyara, VALUE ext);
void nyara_handle_request(int fd);


/* -- url encoded parse -- */
void Init_url_encoded(VALUE ext);
size_t nyara_parse_path(VALUE path, const char*s, size_t len);
void nyara_parse_param(VALUE output, const char* s, size_t len);


/* -- mime parse and match -- */
void Init_mime(VALUE ext);
VALUE ext_mime_match(VALUE self, VALUE request_accept, VALUE accept_mimes);


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
  VALUE ext; // maybe string or map
} RouteResult;

extern void Init_route(VALUE nyara, VALUE ext);
extern RouteResult nyara_lookup_route(enum http_method method_num, VALUE vpath);
