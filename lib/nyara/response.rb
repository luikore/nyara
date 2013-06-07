module Nyara
  class Response
    def initialize signature
      @status = 200
      @header = HeaderHash.new
      @header._aset 'Connection', 'close'
      @header._aset 'Content-Type', 'text/plain; charset=UTF-8'
      @extra_header = []
      @signature = signature
    end
    attr_reader :status, :header, :extra_header

    def send_data data
      data = data.to_s
      EM.send_data @signature, data, data.bytesize
    end

    def render_header
      data = [HTTP_STATUS_FIRST_LINES[@status], *@extra_header]
      @header.each do |k,v|
        data << "#{k}: #{v}\r\n"
      end
      data << "\r\n"
      data = data.join
      EM.send_data @signature, data, data.bytesize
    end
  end
end
