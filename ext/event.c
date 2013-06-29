/* unify API for epoll and kqueue */

#include "nyara.h"
#include "request.h"
#include <sys/fcntl.h>
#include <sys/socket.h>
#include <errno.h>
#include <stdint.h>
#include <unistd.h>

#ifndef rb_obj_hide
extern VALUE rb_obj_hide(VALUE obj);
extern VALUE rb_obj_reveal(VALUE obj, VALUE klass);
#endif

#define ETYPE_CAN_ACCEPT 0
#define ETYPE_HANDLE_REQUEST 1
#define ETYPE_CONNECT 2
#define MAX_E 1024
static void loop_body(int fd, int etype);
static int qfd;

#define MAX_RECEIVE_DATA 65536 * 2
static char received_data[MAX_RECEIVE_DATA];
extern http_parser_settings nyara_request_parse_settings;

#ifdef HAVE_KQUEUE
#include "inc/kqueue.h"
#elif HAVE_EPOLL
#include "inc/epoll.h"
#endif

static VALUE fd_request_map;
static VALUE watch_request_map;
static ID id_not_found;
static VALUE sym_term_close;
static VALUE sym_writing;
static VALUE sym_reading;
static VALUE sym_sleep;
static Request* curr_request;

static void _set_nonblock(int fd) {
  int flags;

  if ((flags = fcntl(fd, F_GETFL)) == -1) {
    rb_sys_fail("fcntl(F_GETFL)");
  }
  if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) == -1) {
    rb_sys_fail("fcntl(F_SETFL,O_NONBLOCK)");
  }
}

static VALUE _fiber_func(VALUE _, VALUE args) {
  VALUE instance = rb_ary_pop(args);
  VALUE meth = rb_ary_pop(args);
  rb_apply(instance, SYM2ID(meth), args);
  return Qnil;
}

static void _handle_request(VALUE request) {
  Request* p;
  Data_Get_Struct(request, Request, p);
  if (p->sleeping) {
    return;
  }
  curr_request = p;

  if (p->parse_state == PS_TERM_CLOSE) {
    if (p->fd) {
      nyara_detach_fd(p->fd);
      p->fd = 0;
    }
  }

  // read and parse data
  // NOTE we don't let http_parser invoke ruby code, because:
  // 1. so the stack is shallower
  // 2. Fiber.yield can pause http_parser, then the unparsed received_data is lost
  long len = read(p->fd, received_data, MAX_RECEIVE_DATA);
  if (len < 0) {
    if (errno != EAGAIN && errno != EWOULDBLOCK) {
      // this can happen when 2 events are fetched, and first event closes the fd, then second event fails
      if (p->fd) {
        nyara_detach_fd(p->fd);
        p->fd = 0;
      }
      return;
    }
  } else if (len) {
    // note: for http_parser, len = 0 means eof reached
    //       but when in a fd-becomes-writable event it can also be 0
    http_parser_execute(&(p->hparser), &nyara_request_parse_settings, received_data, len);
  }

  if (!p->parse_state) {
    return;
  }

  // ensure action
  if (p->fiber == Qnil) {
    volatile RouteResult result = nyara_lookup_route(p->method, p->path, p->accept);
    if (RTEST(result.controller)) {
      rb_ary_push(result.args, rb_class_new_instance(1, &(p->self), result.controller));
      // result.args is on stack, no need to worry gc
      p->fiber = rb_fiber_new(_fiber_func, result.args);
      p->instance = RARRAY_PTR(result.args)[RARRAY_LEN(result.args) - 1];
      p->scope = result.scope;
      p->format = result.format;
      p->response_header = rb_class_new_instance(0, NULL, nyara_header_hash_class);
      p->response_header_extra_lines = rb_ary_new();
    } else {
      rb_funcall(p->self, id_not_found, 0);
      nyara_detach_fd(p->fd);
      p->fd = 0;
      return;
    }
  }

  // resume action
  VALUE state = rb_fiber_resume(p->fiber, 0, NULL);
  if (state == Qnil) { // _fiber_func always returns Qnil
    // terminated (todo log raised error ?)
    nyara_request_term_close(request);
    p->parse_state = PS_TERM_CLOSE;
  } else if (state == sym_term_close) {
    nyara_request_term_close(request);
    p->parse_state = PS_TERM_CLOSE;
  } else if (state == sym_writing) {
    // do nothing
  } else if (state == sym_reading) {
    // do nothing
  } else if (state == sym_sleep) {
    // do nothing
  }
}

// platform independent, invoked by LOOP_E()
static void loop_body(int fd, int etype) {
  switch (etype) {
    case ETYPE_CAN_ACCEPT: {
      int cfd = accept(fd, NULL, NULL);
      if (cfd > 0) {
        _set_nonblock(cfd);
        ADD_E(cfd, ETYPE_HANDLE_REQUEST);
      }
      break;
    }
    case ETYPE_HANDLE_REQUEST: {
      VALUE key = INT2FIX(fd);
      volatile VALUE request = rb_hash_aref(fd_request_map, key);
      if (request == Qnil) {
        request = nyara_request_new(fd);
        rb_hash_aset(fd_request_map, key, request);
      }
      _handle_request(request);
      break;
    }
    case ETYPE_CONNECT: {
      VALUE request = rb_hash_aref(watch_request_map, INT2FIX(fd));
      if (request != Qnil) {
        _handle_request(request);
      }
    }
  }
}

void nyara_detach_fd(int fd) {
  VALUE request = rb_hash_delete(fd_request_map, INT2FIX(fd));
  if (request != Qnil) {
    Request* p;
    Data_Get_Struct(request, Request, p);
    VALUE* watched = RARRAY_PTR(p->watched_fds);
    long watched_len = RARRAY_LEN(p->watched_fds);
    for (long i = 0; i < watched_len; i++) {
      rb_hash_delete(watch_request_map, watched[i]);
    }
  }
  close(fd);
}

static VALUE ext_init_queue(VALUE _) {
  INIT_E();
  return Qnil;
}

static VALUE ext_run_queue(VALUE _, VALUE v_fd) {
  int fd = FIX2INT(v_fd);
  _set_nonblock(fd);
  ADD_E(fd, ETYPE_CAN_ACCEPT);

  LOOP_E();
  return Qnil;
}

static VALUE ext_request_sleep(VALUE _, VALUE request) {
  Request* p;
  Data_Get_Struct(request, Request, p);

  VALUE* v_fds = RARRAY_PTR(p->watched_fds);
  long v_fds_len = RARRAY_LEN(p->watched_fds);
  for (long i = 0; i < v_fds_len; i++) {
    DEL_E(FIX2INT(v_fds[i]));
  }
  DEL_E(p->fd);
  p->sleeping = true;
  return Qnil;
}

static VALUE ext_request_wakeup(VALUE _, VALUE request) {
  // NOTE should not use curr_request
  Request* p;
  Data_Get_Struct(request, Request, p);

  VALUE* v_fds = RARRAY_PTR(p->watched_fds);
  long v_fds_len = RARRAY_LEN(p->watched_fds);
  for (long i = 0; i < v_fds_len; i++) {
    ADD_E(FIX2INT(v_fds[i]), ETYPE_CONNECT);
  }
  ADD_E(p->fd, ETYPE_HANDLE_REQUEST);
  return Qnil;
}

static VALUE ext_set_nonblock(VALUE _, VALUE v_fd) {
  int fd = FIX2INT(v_fd);
  _set_nonblock(fd);
  return Qnil;
}

static VALUE ext_fd_watch(VALUE _, VALUE v_fd) {
  int fd = NUM2INT(v_fd);
  rb_hash_aset(watch_request_map, v_fd, curr_request->self);
  rb_ary_push(curr_request->watched_fds, v_fd);
  ADD_E(fd, ETYPE_CONNECT);
  return Qnil;
}

// override TCPSocket.send
// returns sent length
static VALUE ext_fd_send(VALUE _, VALUE v_fd, VALUE v_data, VALUE v_flags) {
  int flags = NUM2INT(v_flags);
  int fd = NUM2INT(v_fd);
  char* buf = RSTRING_PTR(v_data);
  long len = RSTRING_LEN(v_data);

  // similar to _send_data in request.c
  while(len) {
    long written = send(fd, buf, len, flags);
    if (written <= 0) {
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        rb_fiber_yield(1, &sym_writing);
        continue;
      } else {
        rb_sys_fail("send(2)");
        break;
      }
    } else {
      buf += written;
      len -= written;
      if (len) {
        rb_fiber_yield(1, &sym_writing);
      }
    }
  }

  return LONG2NUM(RSTRING_LEN(v_data) - len);
}

// override TCPSocket.recv
// simulate blocking recv len or eof
static VALUE ext_fd_recv(VALUE _, VALUE v_fd, VALUE v_len, VALUE v_flags) {
  int flags = NUM2INT(v_flags);
  int fd = NUM2INT(v_fd);
  long buf_len = NUM2INT(v_len); // int shall be large enough...

  volatile VALUE str = rb_tainted_str_new(0, buf_len);
  volatile VALUE klass = RBASIC(str)->klass;
  rb_obj_hide(str);

  char* s = RSTRING_PTR(str);
  while(buf_len) {
    long recved = recv(fd, s, buf_len, flags);
    if (recved < 0) {
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        rb_fiber_yield(1, &sym_reading);
        continue;
      } else {
        rb_sys_fail("recv(2)");
        break;
      }
    } else if (recved == 0) { // reached EOF
      break;
    }
    s += recved;
    buf_len -= recved;
  }

  if (RBASIC(str)->klass || RSTRING_LEN(str) != NUM2INT(v_len)) {
    rb_raise(rb_eRuntimeError, "buffer string modified");
  }
  rb_obj_reveal(str, klass);
  if (buf_len) {
    rb_str_set_len(str, RSTRING_LEN(str) - buf_len);
  }
  rb_obj_taint(str);

  return str;
}

// (for test) run request handler, read from associated fd and write to it
static VALUE ext_handle_request(VALUE _, VALUE request) {
  Request* p;
  Data_Get_Struct(request, Request, p);

  while (p->fiber == Qnil || rb_fiber_alive_p(p->fiber)) {
    _handle_request(request);
    if (p->parse_state == PS_TERM_CLOSE) {
      break;
    }
  }
  return p->instance;
}

void Init_event(VALUE ext) {
  fd_request_map = rb_hash_new();
  rb_gc_register_mark_object(fd_request_map);
  watch_request_map = rb_hash_new();
  rb_gc_register_mark_object(watch_request_map);
  id_not_found = rb_intern("not_found");
  sym_term_close = ID2SYM(rb_intern("term_close"));
  sym_writing = ID2SYM(rb_intern("writing"));
  sym_reading = ID2SYM(rb_intern("reading"));
  sym_sleep = ID2SYM(rb_intern("sleep"));

  rb_define_singleton_method(ext, "init_queue", ext_init_queue, 0);
  rb_define_singleton_method(ext, "run_queue", ext_run_queue, 1);

  rb_define_singleton_method(ext, "request_sleep", ext_request_sleep, 1);
  rb_define_singleton_method(ext, "request_wakeup", ext_request_wakeup, 1);

  // fd operations
  rb_define_singleton_method(ext, "set_nonblock", ext_set_nonblock, 1);
  rb_define_singleton_method(ext, "fd_watch", ext_fd_watch, 1);
  rb_define_singleton_method(ext, "fd_send", ext_fd_send, 3);
  rb_define_singleton_method(ext, "fd_recv", ext_fd_recv, 3);

  // for test
  rb_define_singleton_method(ext, "handle_request", ext_handle_request, 1);
}
