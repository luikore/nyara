require_relative "spec_helper"

module Nyara
  describe Request do
    before :each do
      @request = Ext.request_new
      @request_attrs = {
        method_num: HTTP_METHODS['GET'],
        path: '/',
        query: HeaderHash.new.tap{|h| h['id'] = 1 },
        fiber: nil,
        scope: '/',
        format: 'html'
      }
      request_set_attrs
    end

    context "#scheme detect by forwarded.." do
      it "ssl" do
        @request.header['X-Forwarded-Ssl'] = 'on'
        assert_equal 'https', @request.scheme
      end

      it "scheme" do
        @request.header['X-Forwarded-Scheme'] = 'ical'
        assert_equal 'ical', @request.scheme
      end

      it "protocol" do
        @request.header['X-Forwarded-Proto'] = 'https,http'
        assert_equal 'https', @request.scheme
      end
    end

    it "#domain and #port" do
      @request.header['Host'] = "yavaeye.com:3000"
      assert_equal 'yavaeye.com', @request.domain
      assert_equal 3000, @request.port
    end

    it "#host_with_port ignores port on 80" do
      @request.header['Host'] = '127.0.0.1'
      assert_equal '127.0.0.1', @request.host_with_port
    end

    it "#accept_language" do
      @request.header['accept-language'] = "en-US,en;q=0.8"
      assert_equal ['en-US', 'en'], @request.accept_language
    end

    it "#accept_encoding with blank header" do
      @request.header.delete 'Accept-Encoding'
      assert_equal [], @request.accept_encoding
    end

    it "#accept_charset" do
      @request.header['ACCEPT-CHARSET'] = "iso-8859-1;q=0.2, utf-8"
      assert_equal %w[utf-8 iso-8859-1], @request.accept_charset
    end

    it "#param" do
      @request_attrs[:method_num] = HTTP_METHODS['POST']
      @request_attrs[:body] = "foo[bar]=baz"
      request_set_attrs
      assert_equal({'foo' => {'bar' => 'baz'}}, @request.param)
      assert_equal 'baz', @request.param[:foo][:bar]
    end

    def request_set_attrs
      Ext.request_set_attrs @request, @request_attrs
    end
  end
end
