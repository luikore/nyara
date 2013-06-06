#pragma once
#include <ruby.h>

void Init_url_encoded(VALUE ext);
size_t nyara_parse_path(VALUE path, const char*s, size_t len);
