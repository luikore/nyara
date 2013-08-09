require_relative "spec_helper"

module Nyara
  describe Ext, "url_encoded.c" do
    context "Ext.escape" do
      it "escapes path" do
        s = "/a/path.js"
        assert_equal s, Ext.escape(s, true)
      end

      it "escapes uri component" do
        s = "/a/path.js"
        assert_equal CGI.escape(s), Ext.escape(s, false)
      end
    end

    context "Ext.decode_uri_kv" do
      it "empty k" do
        k, v = Ext.decode_uri_kv "=b"
        assert_equal '', k
        assert_equal 'b', v
      end

      it "empty v" do
        k, v = Ext.decode_uri_kv "a="
        assert_equal 'a', k
        assert_equal '', v
      end

      it "without '='" do
        k, v = Ext.decode_uri_kv "a"
        assert_equal 'a', k
        assert_equal '', v
      end

      it "with escaped chars" do
        k, v = Ext.decode_uri_kv "[b+]"
        assert_equal '[b ]', k
      end

      it "raises for bad kv" do
        assert_raise ArgumentError do
          Ext.decode_uri_kv 'a=&b'
        end
      end
    end

    context "Ext.parse_path" do
      before :each do
        @output = ''
      end

      it "converts '%' bytes but not '+'" do
        i = '/%23+%24'
        assert_equal i.bytesize, parse(i)
        assert_equal "/\x23+\x24", @output
      end

      it "truncates '?' after %" do
        i = '/hello%f3%?world'
        len = parse i
        assert_equal '/hello%f3%?'.bytesize, len
        assert_equal "/hello\xf3%", @output
      end

      it "truncates '?' after begin" do
        i = '?a'
        len = parse i
        assert_equal 1, len
        assert_equal '', @output
      end

      it "truncates '?' before end" do
        i = 'a?'
        len = parse i
        assert_equal 2, len
        assert_equal 'a', @output
      end

      it "truncates '?' after unescaped char" do
        i = 'a?a'
        len = parse i
        assert_equal 2, len
        assert_equal 'a', @output
      end

      it "truncates '?' after escaped char" do
        i = '%40?'
        len = parse i
        assert_equal 4, len
        assert_equal "\x40", @output
      end

      it "removes matrix uri params" do
        i = '/a;matrix;matrix=3'
        len = parse i
        assert_equal i.size, len
        assert_equal "/a", @output

        @output = ''
        i += '?'
        len = parse i
        assert_equal i.size, len
        assert_equal "/a", @output

        @output = ''
        i += 'query'
        len = parse i
        assert_equal i.size - 'query'.size, len
        assert_equal '/a', @output
      end

      def parse input
        Ext.parse_path @output, input
      end
    end
  end
end
