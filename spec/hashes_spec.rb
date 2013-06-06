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
  end

  describe ConfigHash do
    it "deep key assignment" do
      h = ConfigHash.new
      h['a', 'deep', 'key1'] = 'value1'
      h['a', 'deep', :key2] = 'value2'
      assert_equal 'value1', h['a', 'deep', :key1]
      assert_equal 'value2', h['a']['deep']['key2']
    end
  end
end
