module Nyara
  # serve public dir
  class PublicController < Controller
    get '/%z' do |path|
      path = Config.public_path path
      if path and File.file?(path)
        send_file path
      else
        status 404
        Ext.request_send_data request, "HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
      end
    end
  end
end
