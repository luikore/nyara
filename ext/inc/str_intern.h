/* string internals, from ruby source code string.c */

#pragma once

#define RUBY_MAX_CHAR_LEN 16
#define STR_TMPLOCK FL_USER7
#define STR_NOEMBED FL_USER1
#define STR_SHARED  FL_USER2 /* = ELTS_SHARED */
#define STR_ASSOC   FL_USER3
#define STR_SHARED_P(s) FL_ALL((s), STR_NOEMBED|ELTS_SHARED)
#define STR_ASSOC_P(s)  FL_ALL((s), STR_NOEMBED|STR_ASSOC)
#define STR_NOCAPA  (STR_NOEMBED|ELTS_SHARED|STR_ASSOC)
#define STR_NOCAPA_P(s) (FL_TEST((s),STR_NOEMBED) && FL_ANY((s),ELTS_SHARED|STR_ASSOC))
#define STR_UNSET_NOCAPA(s) do {\
    if (FL_TEST((s),STR_NOEMBED)) FL_UNSET((s),(ELTS_SHARED|STR_ASSOC));\
} while (0)

#define STR_SET_NOEMBED(str) do {\
    FL_SET((str), STR_NOEMBED);\
    STR_SET_EMBED_LEN((str), 0);\
} while (0)
#define STR_SET_EMBED(str) FL_UNSET((str), STR_NOEMBED)
#define STR_EMBED_P(str) (!FL_TEST((str), STR_NOEMBED))
#define STR_SET_EMBED_LEN(str, n) do { \
    long tmp_n = (n);\
    RBASIC(str)->flags &= ~RSTRING_EMBED_LEN_MASK;\
    RBASIC(str)->flags |= (tmp_n) << RSTRING_EMBED_LEN_SHIFT;\
} while (0)

#define STR_SET_LEN(str, n) do { \
    if (STR_EMBED_P(str)) {\
        STR_SET_EMBED_LEN((str), (n));\
    }\
    else {\
        RSTRING(str)->as.heap.len = (n);\
    }\
} while (0)

#define STR_DEC_LEN(str) do {\
    if (STR_EMBED_P(str)) {\
        long n = RSTRING_LEN(str);\
        n--;\
        STR_SET_EMBED_LEN((str), n);\
    }\
    else {\
        RSTRING(str)->as.heap.len--;\
    }\
} while (0)

#define RESIZE_CAPA(str,capacity) do {\
    if (STR_EMBED_P(str)) {\
        if ((capacity) > RSTRING_EMBED_LEN_MAX) {\
            char *tmp = ALLOC_N(char, (capacity)+1);\
            memcpy(tmp, RSTRING_PTR(str), RSTRING_LEN(str));\
            RSTRING(str)->as.heap.ptr = tmp;\
            RSTRING(str)->as.heap.len = RSTRING_LEN(str);\
            STR_SET_NOEMBED(str);\
            RSTRING(str)->as.heap.aux.capa = (capacity);\
        }\
    }\
    else {\
        REALLOC_N(RSTRING(str)->as.heap.ptr, char, (capacity)+1);\
        if (!STR_NOCAPA_P(str))\
            RSTRING(str)->as.heap.aux.capa = (capacity);\
    }\
} while (0)
