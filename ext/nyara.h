#pragma once
#include <ruby.h>
#include <stdbool.h>
#include <http_parser.h>
#include "inc/status_codes.inc"

#ifdef DEBUG
#undef NDEBUG
#endif


/* event.c */
void Init_event(VALUE ext);


/* request.c */
void Init_request(VALUE nyara, VALUE ext);
void nyara_handle_request(int fd);


/* url_encoded.c */
void Init_url_encoded(VALUE ext);
long nyara_parse_path(VALUE path, const char*s, long len);
void nyara_parse_param(VALUE output, const char* s, long len);


/* accept.c */
void Init_accept(VALUE ext);
VALUE ext_parse_accept_value(VALUE _, VALUE str);


/* mime.c */
void Init_mime(VALUE ext);
VALUE ext_mime_match(VALUE _, VALUE request_accept, VALUE accept_mimes);


/* hashes.c */
void Init_hashes(VALUE nyara);

// "ab-cd" => "Ab-Cd"
// note str must be string created by nyara code
void nyara_headerlize(VALUE str);
int nyara_rb_hash_has_key(VALUE hash, VALUE key);

extern VALUE nyara_param_hash_class;
extern VALUE nyara_header_hash_class;
extern VALUE nyara_config_hash_class;


/* route.c */
typedef struct {
  VALUE controller;
  VALUE args;
  VALUE scope;
  VALUE format; // string, path extension or matched ext in config
} RouteResult;

extern void Init_route(VALUE nyara, VALUE ext);
extern RouteResult nyara_lookup_route(enum http_method method_num, VALUE vpath, VALUE accept_arr);
