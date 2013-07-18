require_relative "spec_helper"

module Nyara
  describe Command do
    it "#help" do
      assert_include(capture(:stdout) { Nyara::Command.help }, "Usage")
    end

    it "#version" do
      assert_equal(capture(:stdout) { Nyara::Command.version }.strip, "Nyara #{Nyara::VERSION}")
    end

    describe "#new_project" do
      before :all do
        @tmp_dir = Dir.mktmpdir 'nyara'
        @old_dir = File.dirname __dir__
        FileUtils.mkdir_p(@tmp_dir)
        @app_name = "app_#{Time.now.to_i}"
        @stdout = capture(:stdout) do
          Dir.chdir @tmp_dir do
            Nyara::Command.new_project(@app_name)
          end
        end
      end

      after :all do
        FileUtils.rm_rf(@tmp_dir)
      end

      describe "should create app dir" do
        it "should run finish" do
          assert_include(@stdout, "Enjoy!")
        end

        it "should copy same files into new dir" do
          des_files = filter_files Dir.glob(File.join @tmp_dir, @app_name, "**/*")
          assert_not_equal(des_files.count, 0)
          src_files = filter_files Dir.glob("#{@old_dir}/lib/nyara/templates/**/*")
          assert_equal(des_files.count, src_files.count)
        end

        def filter_files files
          files.select do |f|
            File.basename(f) !~ /\.DS_Store|\.gitignore|session\.key/
          end
        end
      end
    end
  end
end
