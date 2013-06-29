#pragma once

#include "nyara.h"
#include <multipart_parser.h>
#include <errno.h>
#include <unistd.h>

enum ParseState {
  PS_INIT, PS_HEADERS_COMPLETE, PS_MESSAGE_COMPLETE, PS_ERROR
};

typedef struct {
  http_parser hparser;
  multipart_parser* mparser;

  enum http_method method;
  int fd;
  enum ParseState parse_state;
  int status;   // response status

  VALUE self;

  // request
  VALUE header;
  VALUE accept; // mime array sorted with q
  VALUE format; // string ext without dot
  VALUE fiber;
  VALUE scope;  // mapped prefix
  VALUE path_with_query;
  VALUE path;
  VALUE query;
  VALUE last_field;
  VALUE last_value;

  // response
  VALUE response_content_type;
  VALUE response_header;
  VALUE response_header_extra_lines;

  VALUE watched_fds;
  VALUE instance;

  bool sleeping;
} Request;
