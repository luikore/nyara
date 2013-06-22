require_relative "spec_helper"

module Nyara
  describe [Controller, Request] do
    class DelegateController < Controller
    end

    before :each do
      @request = Ext.request_new
      Ext.request_set_attrs @request, {
        method_num: HTTP_METHODS['GET'],
        path: '/search',
        query: ParamHash.new.tap{|h| h['q'] = 'nyara' },
        fiber: Fiber.new{},
        scope: '/scope',
        header: HeaderHash.new.tap{|h| h['Accept'] = 'en-US' }
        # ext: nil
        # response_header:
        # response_header_extra_lines:
      }
      @c = DelegateController.new @request
    end

    it "#content_type" do
      @c.content_type :js
      assert_equal 'application/javascript', @request.response_content_type
    end

    it "#status" do
      assert_raise ArgumentError do
        @c.status 1000
      end
      @c.status 404
      assert_equal 404, @request.status
    end

    it "request header" do
      assert_equal 'en-US', @c.header['accept']
    end

    context "Simulate IO" do
      before :each do
        @client, @server = Socket.pair :UNIX, :STREAM
        Ext.set_nonblock @server.fileno
        Ext.request_set_fd @request, @server.fileno
      end

      def receive_header
        @c.send_header
        @server.close_write
        @client.read
      end

      it "set response header and send" do
        @c.set_header 'X-Test', true
        @c.add_header_line "X-Test: also-true\r\n"
        res = receive_header.lines
        assert_includes res, "X-Test: true\r\n"
        assert_includes res, "X-Test: also-true\r\n"
      end

      it "set cookie" do
        @c.set_cookie 'set', 'set'
        cookie = receive_header.lines.grep(/Set-Cookie:/).last
        assert_includes cookie, "set=set; HttpOnly"
      end

      it "delete cookie" do
        @c.delete_cookie 'del'
        cookie = receive_header.lines.grep(/Set-Cookie:/).last
        assert_includes cookie, "Expires"
      end

      it "clear cookie" do
        @c.clear_cookie
        pending 'incomplete implementation'
      end

      it "#session" do
        pending
      end
    end
  end
end
