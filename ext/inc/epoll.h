#pragma once

#include <sys/epoll.h>

static struct epoll_event qevents[MAX_E];

static void ADD_E(int fd, uint64_t etype) {
  struct epoll_event e;
  e.events = EPOLLIN;
  e.data.u64 = (etype << 32) | (uint64_t)fd;

  // todo timeout
# ifdef NDEBUG
  epoll_ctl(qfd, EPOLL_CTL_ADD, fd, &e);
# else
  if (epoll_ctl(qfd, EPOLL_CTL_ADD, fd, &e))
    printf("%s: %s\n", __func__, strerror(errno));
# endif
}

static void DEL_E(int fd) {
  struct epoll_event e;
  e.events = EPOLLIN;
  e.data.ptr = NULL;

# ifdef NDEBUG
  epoll_ctl(qfd, EPOLL_CTL_DEL, fd, &e);
# else
  if (epoll_ctl(qfd, EPOLL_CTL_DEL, fd, &e))
    printf("%s: %s\n", __func__, strerror(errno));
# endif
}

static void INIT_E() {
  qfd = epoll_create(10); // size not important
  if (qfd == -1) {
    printf("%s\n", strerror(errno));
    exit(-1);
  }
}

static void LOOP_E() {
  while (1) {
    // heart beat of 0.1 sec, allow ruby signal interrupts to be inserted
    int sz = epoll_wait(qfd, qevents, MAX_E, 100);

    for (int i = 0; i < sz; i++) {
      switch (qevents[i].events) {
        case EPOLLIN: {
          int fd = (int)(qevents[i].data.u64 & 0xFFFFFFFF);
          int etype = (int)(qevents[i].data.u64 >> 32);
          loop_body(fd, etype);
          break;
        }
      }
    }
    // execute other thread / interrupts
    rb_thread_schedule();
  }
}
