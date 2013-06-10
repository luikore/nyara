#include "nyara.h"
#include <sys/fcntl.h>
#include <sys/socket.h>
#include <errno.h>
#include <stdint.h>
#include <unistd.h>

#define ETYPE_ACCEPT 0
#define ETYPE_REQUEST 1
#define ETYPE_CONNECT 2
#define MAX_E 1024
static void loop_body(int fd, int etype);
static int qfd;

#ifdef HAVE_KQUEUE
#include "kqueue.h"
#elif HAVE_EPOLL
#include "epoll.h"
#endif

static void set_nonblock(int fd) {
  int flags;

  if ((flags = fcntl(fd, F_GETFL)) == -1) {
    rb_raise(rb_eRuntimeError, "fcntl(F_GETFL): %s", strerror(errno));
  }
  if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) == -1) {
    rb_raise(rb_eRuntimeError, "fcntl(F_SETFL,O_NONBLOCK): %s", strerror(errno));
  }
}

static VALUE ext_add(VALUE self, VALUE vfd) {
  int fd = FIX2INT(vfd);
  ADD_E(fd, ETYPE_CONNECT);
  return Qnil;
}

// platform independent, invoked by LOOP_E()
static void loop_body(int fd, int etype) {
  switch (etype) {
    case ETYPE_ACCEPT: {
      int cfd = accept(fd, NULL, NULL);
      if (cfd > 0) {
        set_nonblock(cfd);
        ADD_E(cfd, ETYPE_REQUEST);
      }
      break;
    }
    case ETYPE_REQUEST: {
      nyara_handle_request(fd);
      break;
    }
    case ETYPE_CONNECT: {
      // todo
    }
  }
}

static VALUE ext_init_queue(VALUE self) {
  INIT_E();
  return Qnil;
}

static VALUE ext_run_queue(VALUE self, VALUE v_fd) {
  int fd = FIX2INT(v_fd);
  set_nonblock(fd);
  ADD_E(fd, ETYPE_ACCEPT);

  LOOP_E();
  return Qnil;
}

void Init_event(VALUE ext) {
  // rb_define_singleton_method(c, "add", add_q, 2);
  rb_define_singleton_method(ext, "init_queue", ext_init_queue, 0);
  rb_define_singleton_method(ext, "run_queue", ext_run_queue, 1);
}
