require_relative "spec_helper"

module Nyara
  describe Config do
    before :each do
      Config.reset
    end

    it "Nyara.config forbids block" do
      Nyara.config
      assert_raise ArgumentError do
        Nyara.config{}
      end
    end

    it "convert workers" do
      Config.configure do
        set :workers, '3'
      end
      Config.init
      assert_equal 3, Config['workers']
    end

    it "convert port" do
      Config.configure do
        set :port, '1000'
      end
      Config.init
      assert_equal 1000, Config['port']
    end

    it "port default" do
      Config.init
      assert_equal 3000, Config['port']
    end

    it "views and public default" do
      Config[:root] = '/root'
      Config.init
      assert_equal '/root/public', Config['public']
      assert_equal '/root/views', Config['views']
    end

    context "#project_path" do
      before :each do
        Config.configure do
          reset
          set :root, '/a'
          init
        end
      end

      it "works" do
        path = Config.project_path 'b/../../c', false
        assert_equal '/c', path
      end

      it "restrict mode ensures dir safety" do
        path = Config.project_path 'b/../../c'
        assert_equal nil, path
      end

      it "restrict mode allows '..' if it doesn't get outside" do
        path = Config.project_path 'b/../c', true
        assert_equal '/a/c', path
      end
    end

    it "#public_path" do
      Config.configure do
        set :root, '/root'
        set :public, 'a'
        init
      end
      path = Config.public_path '/b'
      assert_equal '/root/a/b', path
    end

    it "#views_path" do
      Config.configure do
        set :root, '/'
        set :views, '/a'
        init
      end
      path = Config.views_path '../..', false
      assert_equal '/', path
    end

    it "env helpers" do
      Config.set :env, 'test'
      assert_equal true, Config.test?
      assert_equal false, Config.development?

      Config.set :env, 'production'
      assert_equal false, Config.test?
      assert_equal true, Config.production?
      Config.reset
    end

    it "creates logger" do
      assert Nyara.logger
    end

    it "not create logger" do
      Config.set :logger, false
      Config.init
      assert_nil Nyara.logger
    end
  end
end
