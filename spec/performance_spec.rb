require_relative "spec_helper"

# run benchmarks in performance/, each output is a hash dumped with Marshal
#
#   { subject: used_time }
#
describe 'performance' do
  def bm name
    bm = __dir__ + '/performance/' + name + '.rb'
    assert File.exist?(bm), "File not found: #{bm}"
    IO.popen ['ruby', bm] do |io|
      data = io.read
      Marshal.load data
    end
  end

  it "[parse_accept_value] faster than sinatra 50%" do
    res = bm 'parse_accept_value'
    assert res[:nyara] * 1.5 < res[:sinatra], res.inspect
  end
end
