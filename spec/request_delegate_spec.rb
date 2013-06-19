require_relative "spec_helper"

module Nyara
  describe [Controller, Request] do
    class DelegateController < Controller
    end

    before :all do
      Ext.set_skip_on_url true
    end

    after :all do
      Ext.set_skip_on_url false
    end

    before :each do
      @client, @server = Socket.pair :UNIX, :STREAM
      Ext.set_nonblock @server.fileno
      @request = Ext.handle_request @server.fileno
      Ext.set_request_attrs @request, {
        method_num: HTTP_METHODS['GET'],
        path: '/search',
        param: ParamHash.new.tap{|h| h['q'] = 'nyara' },
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

    it "set response header and send" do
      pending
      @c.set_header
      @c.add_header_line
      @c.send_header
      @client
    end

    it "set / delete / clear cookie" do
      pending
    end

    it "#session" do
      pending
    end
  end
end
