require_relative "spec_helper"

describe Nyara do
  context ".reconfig_with_command_line_options" do
    before :each do
      Nyara.config.reset
    end

    def config cmd_opts
      Nyara.send :reconfig_with_command_line_options, cmd_opts
    end

    it "works" do
      config %w'-p 1234 -d'
      assert_equal 1234, Nyara.config['port']
      assert_equal true, Nyara.config['daemon']
    end

    it "works without -d" do
      config %w'-p 100'
      assert_equal 100, Nyara.config['port']
      assert_equal true, !Nyara.config['daemon']
    end

    it "raises for bad options" do
      assert_raise RuntimeError do
        config %w'xx'
      end
    end

    it "recognizes --daemon and --port" do
      config %w'--port=1245 --daemon'
      assert_equal 1245, Nyara.config['port']
      assert_equal true, Nyara.config['daemon']
    end

    it "raises for bad port" do
      assert_raise RuntimeError do
        config %w'--port 100000'
      end
    end
  end
end
