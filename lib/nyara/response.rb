module Nyara
  class Response
    BASE_HEADER = HeaderHash.new
    BASE_HEADER['Content-Type'] = 'text/html; charset=UTF-8'
    BASE_HEADER['X-XSS-Protection'] = '1; mode=block'
    BASE_HEADER['X-Content-Type-Options'] = 'nosniff'
    BASE_HEADER['X-Frame-Options'] = 'SAMEORIGIN'
    # BASE_HEADER['Connection'] = 'close'

    def initialize request
      @status = 200
      @header = BASE_HEADER.dup
      # todo
      # date, etag, cache-control
      @extra_header = []
      @request = request
    end
    attr_reader :status, :header, :extra_header

    def send_data data
      @request.send_data data.to_s
    end

    def render_header
      data = [HTTP_STATUS_FIRST_LINES[@status], *@extra_header]
      @header.each do |k,v|
        data << "#{k}: #{v}\r\n"
      end
      data << "\r\n"
      @request.send_data data.join
    end
  end
end
