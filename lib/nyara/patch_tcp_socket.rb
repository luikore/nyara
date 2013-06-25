# patch TCPSocket to make operations synchrony
class TCPSocket
  alias _orig_initialize initialize

  def initialize *xs
    _orig_initialize *xs
    Ext.set_nonblock fileno
    Ext.fd_watch fileno
  end

  def send data, flags, dest_addr=nil, &blk
    if dest_addr
      super
    else
      Ext.fd_send fileno, data, flags, &blk
    end
  end

  def recv max_len, flags=0
    Ext.fd_recv fileno, max_len, flags
  end
end
