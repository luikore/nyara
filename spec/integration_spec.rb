require_relative "spec_helper"

class TestController < Nyara::Controller
  attr_reader :before_invoked

  before ":delete" do
    @before_invoked = true
  end

  meta '#index'
  get '/' do
    content_type 'txt'
    send_string '初めまして from test'
  end

  meta '#create'
  post '/create' do
    redirect_to '#index'
  end

  put '/send_file/%z' do |name|
    send_file Nyara.config.views_path name
  end

  delete '/render' do
    render 'edit.slim'
  end
end

class MyTest
  include Nyara::Test
end

module Nyara
  describe Nyara::Test, 'integration' do
    before :all do
      configure do
        reset
        map '/', TestController
        set :root, __dir__
        set :logger, false
      end
      Nyara.setup
      @test = MyTest.new
    end

    it "response" do
      @test.get "/", {'Xample' => 'résumé'}
      assert @test.response.success?
      assert_equal 'résumé', @test.request.header['Xample']
      assert_equal '初めまして from test', @test.response.body
      assert_equal 'text/plain; charset=UTF-8', @test.response.header['Content-Type']
    end

    it "redirect" do
      @test.post @test.path_to('test#create')
      assert @test.response.success?
      assert_equal 'http://localhost:3000/', @test.redirect_location
      @test.follow_redirect
      assert_equal '/', @test.request.path
    end

    it "session continuation" do
      @test.session['a'] = '3'
      @test.get "/"
      assert_equal '3', @test.session['a']
      @test.session['b'] = '4'
      @test.get "/"
      assert_equal '4', @test.session['b']
      assert_equal '3', @test.session['a']
    end

    it "send file" do
      @test.put "/send_file/layout.erb"
      data = File.read Nyara.config.views_path('layout.erb')
      assert_equal data, @test.response.body
    end

    it "render" do
      @test.delete "/render"
      assert_include @test.response.body, "slim:edit"
    end

    context "public static content" do
      it "found file" do
        @test.get "/index.html"
        assert_equal 200, @test.response.status
        assert_equal "index.html", @test.response.body
      end

      it "found empty file" do
        @test.get "/empty file.html"
        assert_equal 200, @test.response.status
        assert_empty @test.response.body
      end

      it "missing file" do
        @test.get "/missing.html"
        assert_equal 404, @test.response.status
      end

      it "found but directory" do
        @test.get "/empty"
        assert_equal 404, @test.response.status
      end
    end

    context "before / after" do
      it "invokes lifecycle callback" do
        @test.get '/'
        assert_nil @test.env.controller.before_invoked
        assert @test.request.message_complete?

        @test.delete "/render"
        assert @test.env.controller.before_invoked
      end
    end
  end
end
