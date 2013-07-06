require_relative "spec_helper"
unless ENV['SKIP_PERFORMANCE']

# run benchmarks in performance/, each output is a hash dumped with Marshal
#
#   { subject: used_time }
#
describe 'performance' do
  def bm name
    bm = __dir__ + '/performance/' + name + '.rb'
    assert File.exist?(bm), "file not found: #{bm}"
    res = IO.popen ['ruby', bm] do |io|
      data = io.read
      Marshal.load data
    end
    assert_nil $!, "an error stops script #{bm}"
    res
  end

  it "[parse_accept_value] faster than sinatra" do
    res = bm 'parse_accept_value'
    assert res[:nyara] * 1.5 < res[:sinatra], res.inspect
  end

  it "[parse_param] faster than parse in pure ruby" do
    res = bm 'parse_param'
    assert res[:nyara] * 8 < res[:ruby], res.inspect
  end

  it "[layout_render] faster than using tilt" do
    res = bm 'layout_render'
    assert res[:nyara] * 1.1 < res[:tilt], res.inspect
  end

  it "[escape] faster than CGI.escape" do
    res = bm 'escape'
    assert res[:nyara] * 8 < res[:cgi], res.inspect
  end
end

end # unless
