#pragma once

#include <sys/types.h>
#include <sys/event.h>
#include <sys/time.h>

static void loop_body(int fd, VALUE udata);

#define MAX_E 1024
static int qfd;
static struct kevent kevents[MAX_E];

static void ADD_E(int fd, VALUE udata) {
  struct kevent e;
  EV_SET(&e, fd, EVFILT_READ, EV_ADD, 0, 0, (void*)udata);
  // todo timeout
# ifdef NDEBUG
  kevent(qfd, &e, 1, NULL, 0, NULL);
# else
  if (kevent(qfd, &e, 1, NULL, 0, NULL))
    printf("%s: %s\n", __func__, strerror(errno));
# endif
}

static void DEL_E(int fd) {
  struct kevent e;
  EV_SET(&e, fd, EVFILT_READ, EV_DELETE, 0, 0, NULL);
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
    int sz = kevent(qfd, NULL, 0, kevents, MAX_E, &ts);

    for (int i = 0; i < sz; i++) {
      switch (kevents[i].filter) {
        case EVFILT_READ: {
          int fd = (int)kevents[i].ident;
          // EV_EOF is set if the read side of the socket is shutdown
          // the event can keep flipping back to consume cpu if we don't remove it
          if ((kevents[i].flags & EV_EOF)) {
            DEL_E(fd);
          } else {
            loop_body(fd, (VALUE)kevents[i].udata);
          }
          break;
        }
      }
    }
    // execute other thread / interrupts
    rb_thread_schedule();
  }
}
