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
      set_request_attrs
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

    def set_request_attrs
      Ext.set_request_attrs @request, @request_attrs
    end
  end
end
