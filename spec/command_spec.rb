require_relative "spec_helper"

module Nyara
  describe Command do
    it "#help" do
      assert_include(stdout { Nyara::Command.help }, "Usage")
    end

    it "#version" do
      assert_equal(stdout { Nyara::Command.version }.strip, "Nyara #{Nyara::VERSION}")
    end

    describe "#new_project" do
      before :all do
        @tmp_dir = '/tmp/nyara_test'
        @old_dir = Dir.pwd
        FileUtils.mkdir_p(@tmp_dir)
        Dir.chdir(@tmp_dir)

        @app_name = "app_#{Time.now.to_i}"
      end

      after :all do
        FileUtils.rm_rf(@tmp_dir)
        Dir.chdir(@old_dir)
      end

      describe "should create app dir" do


        it "should run finish" do
          a = stdout { Nyara::Command.new_project(@app_name) }
          assert_include(a, "Enjoy!")
        end


        it "should copy same files and generate one more in to new dir" do
          des_files = Dir.glob("./#{@app_name}/**/*")
          assert_not_equal(des_files.count, 0)
          assert_equal(des_files.count, Dir.glob("#{@old_dir}/lib/nyara/templates/**/*").count + 1)
        end
      end

    end
  end
end
