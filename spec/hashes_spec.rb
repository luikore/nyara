require_relative "spec_helper"

module Nyara
  describe ParamHash do
    it "symbol/string keys in ParamHash are the same" do
      h = ParamHash.new
      h[:a] = 3
      assert_equal 3, h['a']
      assert_equal true, h.key?(:a)
      assert_equal true, h.key?('a')
      assert_equal 1, h.size
    end

    context ".split_name" do
      it "many entries" do
        assert_equal ['a', 'b', '', '', 'c'], ParamHash.split_name("a[b][][][c]")
      end

      it "only 1 entry" do
        assert_equal ['a'], ParamHash.split_name('a')
      end

      %w(  a[  [  a]  a[b]c  a[[b]  a[[b]]  ).each do |k|
        it "detects bad key: #{k}" do
          assert_raise ArgumentError do
            ParamHash.split_name k
          end
        end
      end

      it "detects empty key" do
        assert_raise ArgumentError do
          ParamHash.split_name ''
        end
      end
    end

    it "#nested_aset" do
      h = ParamHash.new
      h.nested_aset ['a', '', 'b'], 'c'
      assert_equal({'a' => [{'b' => 'c'}]}, h)
    end

    context ".parse_cookie" do
      it "parses complex cookie" do
        history = CGI.escape '历史'
        cookie = "pgv_pvi; pgv_si= ; pgv_pvi=som; sid=1d6c75f0 ; PLHistory=<#{history}>;"
        h = ParamHash.parse_cookie ParamHash.new, cookie
        assert_equal '1d6c75f0', h['sid']
        assert_equal '', h['pgv_si']
        assert_equal '', h['pgv_pvi'] # left orverrides right
        assert_equal '<历史>', h['PLHistory']
      end

      it "parses empty cookie" do
        cookie = ''
        h = ParamHash.parse_cookie ParamHash.new, cookie
        assert_empty h
      end

      it "parses cookie start with ','" do
        h = ParamHash.parse_cookie ParamHash.new, ',a'
        assert_equal 1, h.size
        assert_equal '', h['a']

        h = ParamHash.parse_cookie ParamHash.new, ' ,b = 1,a'
        assert_equal 2, h.size
        assert_equal '', h['a']
        assert_equal '1', h['b']
      end

      it "parses cookie end with ';'" do
        h = ParamHash.parse_cookie ParamHash.new, 'a ;'
        assert_equal 1, h.size
        assert_equal '', h['a']

        h = ParamHash.parse_cookie ParamHash.new, 'b = 1; a ;'
        assert_equal 2, h.size
        assert_equal '', h['a']
        assert_equal '1', h['b']
      end

      it "parses cookie with space around =" do

      end

      it "refuses to parse cookie into HeaderHash" do
        assert_raise ArgumentError do
          ParamHash.parse_cookie HeaderHash.new, 'session=3'
        end
      end
    end

    context ".parse_param" do
      it "parses single char" do
        h = ParamHash.parse_param ParamHash.new, 'a'
        assert_equal '', h['a']
      end

      it "parses str end with '&'" do
        h = ParamHash.parse_param ParamHash.new, 'a=b&'
        assert_equal({'a' => 'b'}, h)
      end

      it "parses str begin with '&'" do
        h = ParamHash.parse_param ParamHash.new, '&a=b'
        assert_equal({'a' => 'b'}, h)
      end

      it "parses param with non-utf-8 chars" do
        bad_s = CGI.escape "\xE2"
        h = ParamHash.parse_param ParamHash.new, bad_s
        assert_equal "", h["\xE2"]
      end

      it "parses nested kv and preserves hash class" do
        h = ParamHash.parse_param ParamHash.new, "a[b][]=c"
        assert_equal({'a' => {'b' => ['c']}}, h)
        assert_equal ParamHash, h['a'].class
      end

      it "parses k without v and preserves hash class" do
        h = ParamHash.parse_param ConfigHash.new, "a[][b]"
        assert_equal({'a' => [{'b' => ''}]}, h)
        assert_equal Array, h[:a].class
        assert_equal ConfigHash, h[:a].first.class
      end

      it "parses blank string" do
        h = ParamHash.parse_param({}, '')
        assert h.empty?
      end

      it "raises for HeaderHash" do
        assert_raise ArgumentError do
          ParamHash.parse_param(HeaderHash.new, '')
        end
      end
    end
  end

  describe HeaderHash do
    it "ignores case in key" do
      h = HeaderHash.new
      h['a-bc'] = 'good'
    end

    it "headerlizes key and stringify value" do
      h = HeaderHash.new
      h['Content-type'] = 'text/html'
      h[:'content-tYpe'] = :'text/plain'
      assert_equal 1, h.size
      assert_equal ['Content-Type', 'text/plain'], h.to_a.first
    end

    it "can serialize into an array" do
      h = HeaderHash.new
      h['Content-Length'] = 3
      h['X-Weird'] = '奇怪'
      arr = h.serialize
      assert_equal ["Content-Length: 3\r\n", "X-Weird: 奇怪\r\n"], arr
    end

    class HaHash < HeaderHash
    end

    it "#reverse_merge! raises error if other is not HeaderHash" do
      h = HeaderHash.new
      h.reverse_merge! HaHash.new # :)
      assert_raise ArgumentError do
        h.reverse_merge!({})
      end
    end

    it "#reverse_merge!" do
      h = HeaderHash.new
      g = HeaderHash.new
      h['a'] = 'h'
      g['a'] = 'g'
      g['b'] = 'b'
      h.reverse_merge! g
      assert_equal 2, h.size
      assert_equal 'h', h['a']
      assert_equal 'b', h['b']
    end
  end

  describe ConfigHash do
    it "deep key assignment" do
      h = ConfigHash.new
      h['a', 'deep', 'key1'] = 'value1'
      h['a', 'deep', :key2] = 'value2'
      assert_equal 'value1', h['a', 'deep', :key1]
      assert_equal 'value2', h['a']['deep']['key2']
    end

    it "works when last available key exists as other hash type" do
      h = ConfigHash.new
      other_h = {}
      h['a'] = other_h
      h['a', 'b'] = 3
      assert_equal 3, h['a', 'b']
      assert_equal other_h.object_id, h['a'].object_id
    end
  end
end
