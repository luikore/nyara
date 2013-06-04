require_relative "spec_helper"

module Nyara
  describe Ext, "escape/unescape" do
    context "#parse_parthinfo" do
      before :each do
        @output = ''
      end

      it "parses" do
        i = '/%23+%24'
        assert_equal i.bytesize, parse(i)
        assert_equal "/\x23 \x24", @output
      end

      it "truncates ? after %" do
        i = '/hello%f3%?world'
        len = parse i
        assert_equal '/hello%f3%?'.bytesize, len
        assert_equal "/hello\xf3%", @output
      end

      it "truncates ? after begin" do
        i = '?a'
        len = parse i
        assert_equal 1, len
        assert_equal '', @output
      end

      it "truncates ? before end" do
        i = 'a?'
        len = parse i
        assert_equal 2, len
        assert_equal 'a', @output
      end

      it "truncates ? after unescaped char" do
        i = 'a?a'
        len = parse i
        assert_equal 2, len
        assert_equal 'a', @output
      end

      it "truncates ? after escaped char" do
        i = '%40?'
        len = parse i
        assert_equal 4, len
        assert_equal "\x40", @output
      end

      def parse input
        Ext.parse_pathinfo @output, input
      end
    end
  end
end
