/* kqueue event adapter */

#pragma once

#include <sys/types.h>
#include <sys/time.h>
#ifdef HAVE_SYS_EVENT_H
# include <sys/event.h>
#else
# include <sys/queue.h>
#endif

#define MAX_E 1024
static int qfd;
static struct kevent qevents[MAX_E];

static void ADD_E(int fd, uint64_t etype) {
  struct kevent e;
  EV_SET(&e, fd, EVFILT_READ | EVFILT_WRITE, EV_ADD, 0, 0, (void*)etype);
  // todo timeout
# ifdef NDEBUG
  kevent(qfd, &e, 1, NULL, 0, NULL);
# else
  if (kevent(qfd, &e, 1, NULL, 0, NULL))
    printf("%s: %s\n", __func__, strerror(errno));
# endif
}

static void DEL_E(int fd, int filter) {
  struct kevent e;
  EV_SET(&e, fd, filter, EV_DELETE, 0, 0, NULL);
# ifdef NDEBUG
  kevent(qfd, &e, 1, NULL, 0, NULL);
# else
  if (kevent(qfd, &e, 1, NULL, 0, NULL))
    printf("%s: %s\n", __func__, strerror(errno));
# endif
}

static void INIT_E() {
  qfd = kqueue();
  if (qfd == -1) {
    printf("%s\n", strerror(errno));
    exit(-1);
  }
}

static void LOOP_E() {
  // printf("%d,%d,%d,\n%d,%d,%d,\n%d,%d,%d,\n",
  // EV_ADD, EV_ENABLE, EV_DISABLE,
  // EV_DELETE, EV_RECEIPT, EV_ONESHOT,
  // EV_CLEAR, EV_EOF, EV_ERROR);

  struct timespec ts = {0, 1000 * 1000 * 100};
  while (1) {
    // heart beat of 0.1 sec, allow ruby signal interrupts to be inserted
    int sz = kevent(qfd, NULL, 0, qevents, MAX_E, &ts);

    for (int i = 0; i < sz; i++) {
      int fd = (int)qevents[i].ident;
      if (qevents[i].flags & EV_EOF) {
        // EV_EOF is set if the read side of the socket is shutdown
        // the event can keep flipping back to consume cpu if we don't remove it
        DEL_E(fd, qevents[i].filter);
      }
      if (qevents[i].filter & (EVFILT_READ | EVFILT_WRITE)) {
        loop_body(fd, (int)qevents[i].udata);
        break;
      }
    }
    // execute other thread / interrupts
    rb_thread_schedule();
  }
}
