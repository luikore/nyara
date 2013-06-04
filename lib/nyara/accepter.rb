module Nyara
  # child process watch for io events
  class Accepter < EM::Connection
    # c-ext try_accept

    def notify_readable
      fd = try_accept @io
      return unless fd

      # faster than EM::attach_io
      io = IO.for_fd fd
      fd = io.fileno # EM won' accept number
      s = EM.attach_fd fd, false
      c = Request.alloc s, io # get around EM::Connection.new
      EM.instance_variable_get(:@conns)[s] = c

      # seems we can ignore the following 2
      # c.instance_variable_set(:@watch_mode, false)
      # c.instance_variable_set(:@fd, fd)
    end
  end
end
