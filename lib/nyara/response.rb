module Nyara
  class Response
    def initialize signature
      @status = '200'
      @header = {
        'Connection' => 'close',
        'Content-Type' => 'text/plain; charset=UTF-8'
      }
      @signature = signature
    end
    attr_reader :status, :header

    def send_data data
      data = data.to_s
      EM.send_data @signature, data, data.bytesize
    end

    def render_header
      data = "HTTP/1.1 #{@status} OK\r\n"
      EM.send_data @signature, data, data.bytesize

      data = @header.map do |k, v|
        "#{k}: #{v}\r\n" # todo escape newlines in k,v
      end
      data << "\r\n"
      data = data.join
      EM.send_data @signature, data, data.bytesize
    end
  end
end
