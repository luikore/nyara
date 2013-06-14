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

    it "forbids setting Content-Length" do
      h = HeaderHash.new
      assert_raise ArgumentError do
        h['Content-length'] = 3
      end
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
