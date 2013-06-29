require_relative "spec_helper"

module Nyara
  describe Config do
    after :all do
      Config.reset
    end

    it "#workers" do
      Nyara.config.workers '3'
      assert_equal 3, Config['workers']
    end

    it "#port" do
      Config.port '1000'
      assert_equal 1000, Config['port']
    end

    it "env helpers" do
      Config.set :env, 'test'
      assert_equal true, Config.test?
      assert_equal false, Config.development?

      Config.set :env, 'production'
      assert_equal false, Config.test?
    end
  end
end
