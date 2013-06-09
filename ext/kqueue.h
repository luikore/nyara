#pragma once

#include <sys/types.h>
#include <sys/event.h>
#include <sys/time.h>

static void loop_body(int fd, VALUE udata);

#define MAX_E 4096
#define FILTER_READ EVFILT_READ
#define FILTER_SIG EVFILT_SIGNAL
static int qfd;
static struct kevent kevents[MAX_E];

static void ADD_E(int fd, int filter, VALUE udata) {
  struct kevent e;
  EV_SET(&e, fd, filter, EV_ADD, 0, 0, (void*)udata);
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
  while (1) {
    // struct timespec ts = {1, 0};
    int sz = kevent(qfd, NULL, 0, kevents, MAX_E, NULL);

    for (int i = 0; i < sz; i++) {
      switch (kevents[i].filter) {
        case EVFILT_READ: {
          int fd = (int)kevents[i].ident;
          loop_body(fd, (VALUE)kevents[i].udata);
          break;
        }
      }
    }
  }
}
