require_relative "spec_helper"

module Nyara
  describe Ext do
    it ".parse_multipart_boundary" do
      header = HeaderHash.new
      boundary = Ext.parse_multipart_boundary header
      assert_nil boundary

      header['Content-Type'] = 'multipart/form-data; boundary=----WebKitFormBoundaryn3ghstHtZs1Z3VTi'
      boundary = Ext.parse_multipart_boundary header
      assert_equal '------WebKitFormBoundaryn3ghstHtZs1Z3VTi', boundary
    end
  end

  describe Part do
    it "bottom case" do
      p = Part.new({})
      p.final
      assert_equal '', p['data']
    end

    it "parses base64" do
      p = Part.new\
        'Content-Type' => 'image/jpeg; bla bla',
        'Content-Disposition' => "inline; fiLename *= gbk'zh-CN'%C8%CB%B2%CE.jpg; namE= \"file\"",
        'Content-Transfer-Encoding' => 'base64'

      # total length a multiple to 8
      data = [
        "fNfaX7SRKfEfXMcYmHT/AHRXw94r0",
        'G',
        'xXxTqQFlaAC6l/5Yr/AHz7V6nAtam414yhf3',
        'jhzqEoODUt0f/Z'
      ]
      data.each do |datum|
        p.update datum.dup
      end
      p.final

      assert_equal 'base64', p['mechanism']
      assert_equal 'image/jpeg', p['type']
      assert_equal '人参.jpg', p['filename']
      assert_equal 'file', p['name']
      assert_equal data.join, Base64.strict_encode64(p['data'])
    end

    it "parses 7bit data" do
      p = Part.new\
        'Content-Transfer-Encoding' => '7bit'
      p.update 'foo bar'
      assert_equal 'foo bar', p['data']
    end

    it "parses QP data" do
      p = Part.new\
        'Content-Transfer-Encoding' => 'quoted-PrintaBle'
      p.update "a =3F ="
      p.update "04"
      p.final
      assert_equal "a \x3F \x04", p['data']
    end
  end
end
