require_relative "spec_helper"

module Nyara
  describe Command do
    before :each do
      @command = Command.new
    end

    it "#version" do
      assert_equal(capture(:stdout) { @command.version }.strip, "Nyara #{Nyara::VERSION}")
    end

    it "#generate" do
      pending
    end

    it "#server" do
      pending
    end

    it "#console" do
      pending
    end

    describe "#new" do
      before :each do
        GC.stress = false
        @tmp_dir = Dir.mktmpdir 'nyara'
        @old_dir = File.dirname __dir__
        FileUtils.mkdir_p(@tmp_dir)
        @app_name = "app_#{Time.now.to_i}"
        Dir.chdir @tmp_dir do
          @stdout = capture(:stdout) do
            @command = Command.new
            @command.new(@app_name)
          end
        end
      end

      after :each do
        FileUtils.rm_rf(@tmp_dir)
      end

      describe "should create app dir" do
        it "should run finish" do
          assert_include(@stdout, "👻")
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
