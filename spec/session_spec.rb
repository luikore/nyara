require_relative "spec_helper"

module Nyara
  describe Session do
    context "no cipher" do
      before :all do
        Config['session', 'cipher_key'] = nil
        Session.init
      end

      it "should encode and decode" do
        cookie = {}
        session = {'hello' => 'world'}
        Session.encode session, cookie

        assert_includes cookie[Session.name], 'world'

        session2 = Session.decode cookie
        assert_equal 'world', session2[:hello]
      end

      it "drops bad signature" do
        cookie = {}
        session = {'hello' => 'world'}
        Session.encode session, cookie

        cookie[Session.name].sub!(/\w/, &:swapcase)

        session = Session.decode cookie
        assert_empty session
      end
    end

    context "with cipher" do
      before :all do
        Config['session', 'cipher_key'] = "some cipher key"
        Session.init
      end

      it "encode and decode" do
        cookie = {}
        session = {'hello' => 'world2'}
        Session.encode session, cookie

        # should be 256bit aligned even src length changed
        assert_equal 0, cookie[Session.name].bytesize % (256/8)
        session = {'hello' => 'world'}
        Session.encode session, cookie
        assert_equal 0, cookie[Session.name].bytesize % (256/8)

        session2 = Session.decode cookie
        assert_equal 'world', session2[:hello]
      end
    end
  end
end
