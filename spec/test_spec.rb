require_relative "spec_helper"

module Nyara
  describe Nyara::Test do
    class MyController < Nyara::Controller
      get '/' do
        content_type 'txt'
        send_string 'hello from test'
      end
    end

    class MyTest
      include Nyara::Test
    end

    before :all do
      configure do
        reset
        set :env, 'test'
        map '/', MyController
      end
      Nyara.setup
      @test = MyTest.new
    end

    it "response" do
      @test.get "/"
      assert @test.response.success?
      assert_equal 'hello from test', @test.response.body
      assert_equal 'text/plain; charset=UTF-8', @test.response.header['Content-Type']
    end
  end
end
