# patch TCPSocket to make operations synchrony
class TCPSocket
  alias _orig_initialize initialize

  def initialize *xs
    _orig_initialize *xs
    Nyara::Ext.set_nonblock fileno
    Nyara::Ext.fd_watch fileno
  end

  def send data, flags, dest_addr=nil, &blk
    if dest_addr
      super
    else
      Nyara::Ext.fd_send fileno, data, flags, &blk
    end
  end

  def recv max_len, flags=0
    Nyara::Ext.fd_recv fileno, max_len, flags
  end
end
