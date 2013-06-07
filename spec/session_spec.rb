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
        session = {'hello' => 'world'}
        Session.encode session, cookie

        assert_not_includes cookie[Session.name], 'world'

        session2 = Session.decode cookie
        assert_equal 'world', session2[:hello]
      end

      it "cipher should not be pure" do
        message = 'OCB is by far the best mode, as it allows encryption and authentication in a single pass. However there are patents on it in USA.'
        r1 = Session.cipher message
        r2 = Session.cipher message
        assert_not_equal r1, r2
      end
    end
  end
end
