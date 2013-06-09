#include "nyara.h"
#include <sys/fcntl.h>
#include <sys/socket.h>
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <unistd.h>

#ifdef HAVE_KQUEUE
#include "kqueue.h"
#elif HAVE_EPOLL
#include "epoll.h"
#endif

static int sig_fds[2];
static VALUE sig_map;
static ID id_call;

static void set_nonblock(int fd) {
  int flags;

  if ((flags = fcntl(fd, F_GETFL)) == -1) {
    rb_raise(rb_eRuntimeError, "fcntl(F_GETFL): %s", strerror(errno));
  }
  if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) == -1) {
    rb_raise(rb_eRuntimeError, "fcntl(F_SETFL,O_NONBLOCK): %s", strerror(errno));
  }
}

static VALUE ext_send_data(VALUE self, VALUE v_fd, VALUE data) {
  int fd = FIX2INT(v_fd);
  char* buf = RSTRING_PTR(data);
  long len = RSTRING_LEN(data);

  while(len) {
    long written = write(fd, buf, len);
    if (written == 0)
      return Qnil;
    if (written == -1) {
      if (errno == EWOULDBLOCK) {
        // todo enqueue data
      }
      return Qnil;
    }
    buf += written;
    len -= written;
  }
  return Qnil;
}

static VALUE ext_add(VALUE self, VALUE vfd) {
  int fd = FIX2INT(vfd);
  ADD_E(fd, FILTER_READ, Qfalse);
  return Qnil;
}

void nyara_detach_fd(int fd) {
  DEL_E(fd, FILTER_READ);
  close(fd);
}

static VALUE ext_close(VALUE self, VALUE vfd) {
  int fd = FIX2INT(vfd);
  nyara_detach_fd(fd);
  nyara_detach_request(fd);
  return Qnil;
}

static void nyara_sig_action(int sig) {
  uint8_t sigs[1];
  sigs[0] = (uint8_t)sig;
  write(sig_fds[1], sigs, 1);
}

// NOTE running the proc in the trap can break ruby's cfp
// ruby's signal can not be triggered inside kqueue loop
static VALUE ext_trap(VALUE self, VALUE v_sig, VALUE proc) {
  rb_hash_aset(sig_map, v_sig, proc);
  int sig = FIX2INT(v_sig);
  signal(sig, nyara_sig_action);
  return Qnil;
}

// platform independent, invoked by LOOP_E()
static void loop_body(int fd, VALUE udata) {
  if (udata == Qtrue) {
    // accept request
    int cfd = accept(fd, NULL, NULL);
    if (cfd > 0) {
      set_nonblock(cfd);
      ADD_E(cfd, FILTER_READ, Qfalse);
    }

  } else if (udata == Qfalse) {
    // handle request
    nyara_handle_request(fd);
    // rb_funcall(handler, rb_intern("call"), 1, INT2FIX(fd));

  } else if (udata == Qnil) {
    // handle signal, 200 at most...
    static uint8_t buf[200];
    long num = read(fd, buf, 200);
    if (num > 0) {
      for (long i = 0; i < num; i++) {
        VALUE p = rb_hash_aref(sig_map, INT2FIX(buf[i]));
        if (p != Qnil) {
          rb_funcall(p, id_call, 0);
        }
      }
    }

  } else {
    // handle connection callback

  }
}

static VALUE ext_init_queue(VALUE self) {
  INIT_E();
  return Qnil;
}

static VALUE ext_run_queue(VALUE self, VALUE v_fd) {
  int fd = FIX2INT(v_fd);
  set_nonblock(fd);
  ADD_E(fd, FILTER_READ, Qtrue);

  if (pipe(sig_fds)) {
    rb_raise(rb_eRuntimeError, "%s: %s", __func__, strerror(errno));
  }
  set_nonblock(sig_fds[0]);
  set_nonblock(sig_fds[1]);
  ADD_E(sig_fds[0], FILTER_READ, Qnil);

  LOOP_E();
  return Qnil;
}

void Init_event(VALUE ext) {
  sig_map = rb_hash_new();
  rb_gc_register_mark_object(sig_map);
  id_call = rb_intern("call");

  rb_define_singleton_method(ext, "send_data", ext_send_data, 2);
  rb_define_singleton_method(ext, "close", ext_close, 1);
  // rb_define_singleton_method(c, "add", add_q, 2);
  rb_define_singleton_method(ext, "init_queue", ext_init_queue, 0);
  rb_define_singleton_method(ext, "run_queue", ext_run_queue, 1);
  rb_define_singleton_method(ext, "trap", ext_trap, 2);
}
