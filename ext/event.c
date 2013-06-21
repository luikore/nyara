/* unify API for epoll and kqueue */

#include "nyara.h"
#include "request.h"
#include <sys/fcntl.h>
#include <sys/socket.h>
#include <errno.h>
#include <stdint.h>
#include <unistd.h>

#define ETYPE_CAN_ACCEPT 0
#define ETYPE_HANDLE_REQUEST 1
#define ETYPE_CONNECT 2
#define MAX_E 1024
static void loop_body(int fd, int etype);
static int qfd;

#define MAX_RECEIVE_DATA 65536
static char received_data[MAX_RECEIVE_DATA];
extern http_parser_settings nyara_request_parse_settings;

#ifdef HAVE_KQUEUE
#include "inc/kqueue.h"
#elif HAVE_EPOLL
#include "inc/epoll.h"
#endif

static VALUE fd_request_map;
static ID id_not_found;
static VALUE sym_term_close;
static VALUE sym_writing;

static void _set_nonblock(int fd) {
  int flags;

  if ((flags = fcntl(fd, F_GETFL)) == -1) {
    rb_raise(rb_eRuntimeError, "fcntl(F_GETFL): %s", strerror(errno));
  }
  if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) == -1) {
    rb_raise(rb_eRuntimeError, "fcntl(F_SETFL,O_NONBLOCK): %s", strerror(errno));
  }
}

static VALUE _fiber_func(VALUE _, VALUE args) {
  VALUE instance = rb_ary_pop(args);
  VALUE meth = rb_ary_pop(args);
  rb_apply(instance, SYM2ID(meth), args);
  return Qnil;
}

static void _handle_request(int fd) {
  // get request
  VALUE key = INT2FIX(fd);
  volatile VALUE request = rb_hash_aref(fd_request_map, key);
  if (request == Qnil) {
    request = nyara_request_new(fd);
    rb_hash_aset(fd_request_map, key, request);
  }
  Request* p;
  Data_Get_Struct(request, Request, p);

  // read and parse data
  // NOTE we don't let http_parser invoke ruby code, because:
  // 1. so the stack is shallower
  // 2. Fiber.yield can pause http_parser, then the unparsed received_data is lost
  long len = read(fd, received_data, MAX_RECEIVE_DATA);
  if (len < 0) {
    if (errno != EAGAIN) {
      rb_warn("%s", strerror(errno));
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
    nyara_request_term_close(request, false);
  } else if (state == sym_term_close) {
    nyara_request_term_close(request, true);
  } else if (state == sym_writing) {
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
      _handle_request(fd);
      break;
    }
    case ETYPE_CONNECT: {
      // todo
      // NOTE
      // fd and connection are 1:1, there can more more than 1 fds on a same file / address
      // so it's streight forward to using fd as query index
    }
  }
}

void nyara_detach_fd(int fd) {
  rb_hash_delete(fd_request_map, INT2FIX(fd));
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

static VALUE ext_set_nonblock(VALUE _, VALUE v_fd) {
  int fd = FIX2INT(v_fd);
  _set_nonblock(fd);
  return Qnil;
}

static VALUE ext_watch(VALUE _, VALUE vfd) {
  // todo dupe fd or just stub into TCP
  int fd = FIX2INT(vfd);
  ADD_E(fd, ETYPE_CONNECT);
  return Qnil;
}

void Init_event(VALUE ext) {
  fd_request_map = rb_hash_new();
  rb_gc_register_mark_object(fd_request_map);
  id_not_found = rb_intern("not_found");
  sym_term_close = ID2SYM(rb_intern("term_close"));
  sym_writing = ID2SYM(rb_intern("writing"));

  rb_define_singleton_method(ext, "init_queue", ext_init_queue, 0);
  rb_define_singleton_method(ext, "run_queue", ext_run_queue, 1);
  rb_define_singleton_method(ext, "watch", ext_watch, 1);

  // for test
  rb_define_singleton_method(ext, "set_nonblock", ext_set_nonblock, 1);
}
