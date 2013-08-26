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

    it "timeout default" do
      Config.init
      assert_equal 120, Config['timeout']

      Config['timeout'] = 12.3
      Config.init
      assert_equal 12, Config['timeout']
    end

    it "views, assets and public default" do
      Config[:root] = __dir__
      Config.init
      assert_equal nil, Config['public']
      assert_equal __dir__ + '/views', Config['views']
      assert_equal nil, Config['assets']
    end

    context "#project_path" do
      before :each do
        Config.configure do
          reset
          set :root, __dir__
          init
        end
      end

      it "works" do
        path = Config.project_path 'b/../../c', false
        assert_equal File.dirname(__dir__) + '/c', path
      end

      it "restrict mode ensures dir safety" do
        path = Config.project_path 'b/../../c'
        assert_equal nil, path
      end

      it "restrict mode allows '..' if it doesn't get outside" do
        path = Config.project_path 'b/../c', true
        assert_equal __dir__ + '/c', path
      end
    end

    it "#public_path" do
      Config.configure do
        set :root, __dir__
        set :public, 'a'
        init
      end
      path = Config.public_path '/b'
      assert_equal __dir__ + '/a/b', path
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

    it "#assets_path" do
      Config.configure do
        set :root, '/'
        set :assets, '/a'
        init
      end
      path = Config.assets_path '../..', false
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

    it "root helpers" do
      Config.init
      assert_equal Dir.pwd, Config.root
      Config.set :root, 'aaa'
      assert_equal 'aaa', Config.root
      Config.configure do
        set :root,'bbb'
      end
      assert_equal 'bbb', Config.root
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
