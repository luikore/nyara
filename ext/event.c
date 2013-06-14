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
#include "inc/kqueue.h"
#elif HAVE_EPOLL
#include "inc/epoll.h"
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

static VALUE ext_add(VALUE _, VALUE vfd) {
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
      // NOTE
      // fd and connection are 1:1, there can more more than 1 fds on a same file / address
      // so it's streight forward to using fd as query index
    }
  }
}

static VALUE ext_init_queue(VALUE _) {
  INIT_E();
  return Qnil;
}

static VALUE ext_run_queue(VALUE _, VALUE v_fd) {
  int fd = FIX2INT(v_fd);
  set_nonblock(fd);
  ADD_E(fd, ETYPE_ACCEPT);

  LOOP_E();
  return Qnil;
}

static VALUE ext_set_nonblock(VALUE _, VALUE v_fd) {
  int fd = FIX2INT(v_fd);
  set_nonblock(fd);
  return Qnil;
}

void Init_event(VALUE ext) {
  // rb_define_singleton_method(c, "add", add_q, 2);
  rb_define_singleton_method(ext, "init_queue", ext_init_queue, 0);
  rb_define_singleton_method(ext, "run_queue", ext_run_queue, 1);

  // for test
  rb_define_singleton_method(ext, "set_nonblock", ext_set_nonblock, 1);
}
