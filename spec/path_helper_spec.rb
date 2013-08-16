require_relative "spec_helper"

class FooController < Nyara::Controller
  meta '#index'
  get '/%.5d' do |id|
  end

  meta '#put'
  put '/' do
  end

  class BarController < Nyara::Controller
    meta '#index'
    get '/' do
    end
  end

  class BazController < Nyara::Controller
    set_controller_name 'baz'

    meta '#index'
    get '/%d' do |id|
    end
  end
end

module Nyara
  describe [Controller, Route] do
    before :all do
      Config.configure do
        reset
        set 'host', 'yavaeye.com'
        map '/', 'FooController'
        map '/bar-prefix', 'FooController::BarController'
        map '/baz-prefix', 'FooController::BazController'
      end
      Nyara.setup
    end

    context '#path_to' do
      it "local query" do
        c = FooController.new :stub_request
        assert_equal '/00012', c.path_to('#index', 12)
        assert_raise ArgumentError do
          c.path_to '#index'
        end
        assert_raise ArgumentError do
          c.path_to('#index', 'a')
        end
      end

      it "global query" do
        c = FooController::BarController.new :stub_request
        assert_equal '/bar-prefix/', c.path_to('foo_controller::bar#index')
        assert_equal '/baz-prefix/1', c.path_to('baz#index', 1)
      end

      it "generates for nested query" do
        c = FooController.new :stub_request
        path = c.path_to('#index', 1, post: {array: [1, 2]})
        items = URI.parse(path).query.split('&').map{|q| CGI.unescape q }
        assert_equal ["post[array][]=1", "post[array][]=2"], items
      end

      it "perserves _method query" do
        c = FooController.new :stub_request
        path = c.path_to('#put')
        assert_equal '/?_method=PUT', path

        path = c.path_to('#put', :_method => 'POST')
        assert_equal '/?_method=POST', path

        path = c.path_to('#put', '_method' => nil)
        assert_equal '/?_method=', path
      end

      it "appends format and query" do
        c = FooController.new :stub_request
        generated = c.path_to '#index', 1, format: 'js', 'utm_source' => 'a spam'
        assert_equal "/00001.js?utm_source=a+spam", generated
      end
      
      it "raise info with wrong route" do
        c = FooController.new :stub_request
        assert_raise ArgumentError do
          c.path_to('#aksdgjajksdg')
        end
      end
    end

    context '#url_to' do
      it "works" do
        request = Object.new
        class << request
          attr_accessor :host_with_port
        end
        request.host_with_port = 'yavaeye.com'
        c = FooController::BazController.new request
        assert_equal '//yavaeye.com/baz-prefix/1', c.url_to('#index', 1)
        assert_equal 'https://localhost:4567/00001', c.url_to('foo#index', 1, scheme: 'https', host: 'localhost:4567')
      end
    end
  end
end
