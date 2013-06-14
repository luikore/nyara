module Nyara
  class Response
    BASE_HEADER = HeaderHash.new
    BASE_HEADER['Content-Type'] = 'text/html; charset=UTF-8'
    BASE_HEADER['X-XSS-Protection'] = '1; mode=block'
    BASE_HEADER['X-Content-Type-Options'] = 'nosniff'
    BASE_HEADER['X-Frame-Options'] = 'SAMEORIGIN'
    # BASE_HEADER['Connection'] = 'close'

    # c-ext _send_data, close

    def initialize request
      @request = request
      @extra_header = []
    end

    attr_reader :status
    def status= s
      raise ArgumentError, "unsupported status: #{s}" unless HTTP_STATUS_FIRST_LINES[s]
      @status = s
    end

    def header
      @header ||= begin
        h = BASE_HEADER.dup
        if accept = @request._accept
          h._aset 'Content-Type', "#{MIME_TYPES[accept]}; charset=UTF-8"
        end
        h
      end
    end

    # in case a header has repeated key
    def add_header h
      h = h.sub /(?<![\r\n])\z/, "\r\n"
      @extra_header << h
    end

    def send_data data
      _send_data data.to_s
    end

    def render_header
      data = [HTTP_STATUS_FIRST_LINES[(@status || 200)]]
      header.each do |k,v|
        data << "#{k}: #{v}\r\n"
      end
      data.concat @extra_header
      data << "\r\n"
      _send_data data.join
    end
  end
end
