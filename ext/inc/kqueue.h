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
  EV_SET(&e, fd, EVFILT_READ | EVFILT_WRITE, EV_ADD, 0, 0, (void*)rid);
  if (kevent(qfd, &e, 1, NULL, 0, NULL))
    rb_sys_fail("kevent(2) - EV_ADD");
}

static void DEL_E_WITH_FILTER(int fd, int filter) {
  struct kevent e;
  EV_SET(&e, fd, filter, EV_DELETE, 0, 0, NULL);
  if (kevent(qfd, &e, 1, NULL, 0, NULL))
    rb_sys_fail("kevent(2) - EV_DELETE");
}

static void DEL_E(int fd) {
  DEL_E_WITH_FILTER(fd, EVFILT_READ | EVFILT_WRITE);
}

static void INIT_E() {
  qfd = kqueue();
  if (qfd == -1) {
    rb_sys_fail("kqueue(2)");
  }
}

static void LOOP_E() {
  // printf("%d,%d,%d,\n%d,%d,%d,\n%d,%d,%d,\n",
  // EV_ADD, EV_ENABLE, EV_DISABLE,
  // EV_DELETE, EV_RECEIPT, EV_ONESHOT,
  // EV_CLEAR, EV_EOF, EV_ERROR);

  static struct timespec ts = {0, 1000 * 1000 * 100};
  while (1) {
    // heart beat of 0.1 sec, allow ruby signal interrupts to be inserted
    int sz = kevent(qfd, NULL, 0, qevents, MAX_E, &ts);
    st_clear(handled_rids);

    for (int i = 0; i < sz; i++) {
      if (qevents[i].flags & EV_EOF) {
        int fd = (int)qevents[i].ident;
        // EV_EOF is set if the read side of the socket is shutdown
        // the event can keep flipping back to consume cpu if we don't remove it
        DEL_E_WITH_FILTER(fd, qevents[i].filter);
      }
      if (qevents[i].filter & (EVFILT_READ | EVFILT_WRITE)) {
        loop_body((VALUE)qevents[i].udata);
        break;
      }
    }
    loop_check();
  }
}
