/* kqueue event adapter */

#pragma once

#include <sys/types.h>
#include <sys/time.h>
#ifdef HAVE_SYS_EVENT_H
# include <sys/event.h>
#else
# include <sys/queue.h>
#endif

static struct kevent qevents[MAX_E];

static void ADD_E(int fd, VALUE rid) {
  struct kevent e;
  // without EV_CLEAR, it is level-triggered
  // http://www.cs.helsinki.fi/linux/linux-kernel/2001-38/0547.html
  EV_SET(&e, fd, EVFILT_READ | EVFILT_WRITE, EV_ADD | EV_CLEAR, 0, 0, (void*)rid);
  if (kevent(q.fd, &e, 1, NULL, 0, NULL))
    rb_sys_fail("kevent(2) - EV_ADD");
}

static void DEL_E_WITH_FILTER(int fd, int filter) {
  struct kevent e;
  EV_SET(&e, fd, filter, EV_DELETE, 0, 0, NULL);
  if (kevent(q.fd, &e, 1, NULL, 0, NULL))
    rb_sys_fail("kevent(2) - EV_DELETE");
}

static void DEL_E(int fd) {
  DEL_E_WITH_FILTER(fd, EVFILT_READ | EVFILT_WRITE);
}

static void INIT_E() {
  q.fd = kqueue();
  if (q.fd == -1) {
    rb_sys_fail("kqueue(2)");
  }
}

static int SELECT_E(st_table* rids) {
  static struct timespec ts = {0, 1000 * 1000 * 100};

  // heart beat of 0.1 sec, allow ruby signal interrupts to be inserted
  int sz = kevent(q.fd, NULL, 0, qevents, MAX_E, &ts);
  int accept_sz = 0;

  for (int i = 0; i < sz; i++) {
    if (qevents[i].filter & (EVFILT_READ | EVFILT_WRITE)) {
      VALUE rid = (VALUE)qevents[i].udata;
      if (rid == sym_accept) {
        accept_sz++;
      } else {
        st_insert(rids, rid, 0);
      }
    }
  }
  return accept_sz;
}
