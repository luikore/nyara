/* epoll event adapter */

#pragma once

#include <sys/epoll.h>

static struct epoll_event qevents[MAX_E];

static void ADD_E(int fd, VALUE rid) {
  struct epoll_event e;
  // not using edge trigger flag EPOLLET
  // because edge trigger only fire once when fd is readable/writable
  // but the event may not be consumed in our handler
  e.events = EPOLLIN | EPOLLOUT;
  e.data.u64 = (uint64_t)rid;

  if (epoll_ctl(qfd, EPOLL_CTL_ADD, fd, &e))
    rb_sys_fail("epoll_ctl(2) - EPOLL_CTL_ADD");
}

// NOTE either epoll or kqueue removes the event watch from queue when fd closed
static void DEL_E(int fd) {
  struct epoll_event e;
  e.events = EPOLLIN | EPOLLOUT;
  if (epoll_ctl(qfd, EPOLL_CTL_DEL, fd, &e))
    rb_sys_fail("epoll_ctl(2) - EPOLL_CTL_DEL");
}

static void INIT_E() {
  qfd = epoll_create(10); // size not important
  if (qfd == -1) {
    rb_sys_fail("epoll_create(2)");
  }
}

static void LOOP_E() {
  while (1) {
    // heart beat of 0.1 sec, allow ruby signal interrupts to be inserted
    int sz = epoll_wait(qfd, qevents, MAX_E, 100);
    st_clear(handled_rids);

    for (int i = 0; i < sz; i++) {
      VALUE rid = (VALUE)qevents[i].data.u64;
      if (qevents[i].events & (EPOLLHUP | EPOLLERR)) {
        nyara_detach_rid(rid);
        // todo log?
      } else if (qevents[i].events & (EPOLLIN | EPOLLOUT)) {
        loop_body(rid);
      } else if (qevents[i].events & EPOLLRDHUP) {
        // do sth?
      }
    }
    loop_check();
  }
}
