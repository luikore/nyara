require_relative "spec_helper"

module Nyara
  describe Ext, "parse" do
    # note: this method is only used in C code
    context "#parse_url_encoded_seg" do
      [false, true].each do |nested|
        context (nested ? 'nested mode' : 'flat mode') do
          it "normal parse" do
            assert_equal({'a' => 'b'}, parse('a=b', nested))
          end

          it "param seg end with '='" do
            assert_equal({'a' => ''}, parse('a=', nested))
          end

          it "param seg begin with '='" do
            assert_equal({'' => 'b'}, parse('=b', nested))
          end

          it "param seg without value" do
            assert_equal({'a' => ''}, parse('a', nested))
          end

          it "raises error" do
            assert_raise ArgumentError do
              parse 'a=&b'
            end
          end
        end
      end

      context "nested key" do
        it "parses nested key" do
          res = {"a"=>{"b"=>[[{"c"=>"1"}]]}}
          assert_equal res, Ext.parse_url_encoded_seg({}, "a[b][][][c]=1", true)
        end

        it 'allows "[]" as input' do
          res = {""=>[""]}
          assert_equal res, Ext.parse_url_encoded_seg({}, "[]", true)
        end

        it 'ignores empty input' do
          res = {}
          assert_equal res, Ext.parse_url_encoded_seg({}, "", true)
        end

        it "content hash is ParamHash" do
          h = ParamHash.new
          assert_equal ParamHash, Ext.parse_url_encoded_seg(h, "a[b]=c", true)[:a].class
        end
      end

      def parse str, nested
        h = {}
        Ext.parse_url_encoded_seg h, str, nested
      end
    end

    context "#parse_path" do
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

    context ".parse_cookie" do
      it "parses complex cookie" do
        history = CGI.escape '历史'
        cookie = "pgv_pvi; pgv_si= ; pgv_pvi=som; sid=1d6c75f0 ; PLHistory=<#{history}>;"
        h = Ext.parse_cookie ParamHash.new, cookie
        assert_equal '1d6c75f0', h['sid']
        assert_equal '', h['pgv_si']
        assert_equal '', h['pgv_pvi'] # left orverrides right
        assert_equal '<历史>', h['PLHistory']
      end

      it "parses empty cookie" do
        cookie = ''
        h = Ext.parse_cookie ParamHash.new, cookie
        assert_empty h
      end
    end

    context ".parse_param" do
      it "parses param with non-utf-8 chars" do
        bad_s = CGI.escape "\xE2"
        h = Ext.parse_param ParamHash.new, bad_s
        assert_equal "", h["\xE2"]
      end
    end
  end
end
