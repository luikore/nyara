#pragma once
#include <ruby.h>

void Init_hashes(VALUE nyara);

// ab-cd => Ab-Cd
// note str must be string created by nyara code
void nyara_headerlize(VALUE str);
int nyara_rb_hash_has_key(VALUE hash, VALUE key);

extern VALUE nyara_param_hash_class;
extern VALUE nyara_header_hash_class;
extern VALUE nyara_config_hash_class;
