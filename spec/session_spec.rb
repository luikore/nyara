require_relative "spec_helper"

module Nyara
  describe Session do
    context ".encode_set_cookie options" do
      before :all do
        @session = Session.new
        @session['hello'] = 'world'
      end

      it "is HttpOnly" do
        Session.init
        line = Session.encode_set_cookie @session, false
        assert_includes line, '; HttpOnly'
      end

      it "adds Secure" do
        init_configure_with :session, :secure, true
        line = Session.encode_set_cookie @session, false
        assert_includes line, '; Secure'

        init_configure_with :session, :secure, false
        line = Session.encode_set_cookie @session, true
        assert_not_includes line, 'Secure'

        init_configure_with :session, :secure, nil
        line = Session.encode_set_cookie @session, true
        assert_includes line, '; Secure'
        line = Session.encode_set_cookie @session, false
        assert_not_includes line, 'Secure'
      end

      it "adds Expires" do
        init_configure_with :session, :expire, nil
        line = Session.encode_set_cookie @session, false
        assert_not_includes line, 'Expires'

        init_configure_with :session, :expires, 30 * 60
        line = Session.encode_set_cookie @session, false
        assert_includes line, '; Expires='
      end

      it "raises for unkown keys" do
        assert_raise RuntimeError do
          init_configure_with :session, :ciphre_key, 'adsf'
        end
      end

      def init_configure_with *options
        Config.configure do
          reset
          set *options
        end
        Session.init
      end
    end

    context "no cipher" do
      before :all do
        Config.configure do
          reset
          set 'session', 'cipher_key', nil
        end
        Session.init
      end

      it "should encode and decode" do
        cookie = {}
        session = Session.new
        session['hello'] = 'world'
        Session.encode_to_cookie session, cookie

        session_data = cookie[Session.name].split('/')[1]
        assert_includes Base64.urlsafe_decode64(session_data), 'world'

        session2 = Session.decode cookie
        assert_equal 'world', session2[:hello]
      end

      it "drops bad signature" do
        cookie = {}
        session = Session.new
        session['hello'] = 'world'
        Session.encode_to_cookie session, cookie

        cookie[Session.name].sub!(/\w/, &:swapcase)

        session = Session.decode cookie
        assert_empty session
      end
    end

    context "with cipher" do
      before :all do
        Config.configure do
          reset
          set 'session', 'cipher_key', "some cipher key"
        end
        Session.init
      end

      it "encode and decode" do
        cookie = {}
        session = Session.new
        session['hello'] = 'world'
        Session.encode_to_cookie session, cookie

        session_data = cookie[Session.name].split('/')[1]
        if session_data
          assert_not_includes Base64.urlsafe_decode64(session_data), 'world'
        end

        session2 = Session.decode cookie
        assert_equal 'world', session2[:hello]
      end

      it "cipher should not be pure" do
        message = 'OCB is by far the best mode, as it allows encryption and authentication in a single pass. However there are patents on it in USA.'
        r1 = Session.cipher message
        r2 = Session.cipher message
        assert_not_equal r1, r2
      end

      it "decipher returns blank str when message too short" do
        r = Session.decipher Base64.urlsafe_encode64 'short one'
        assert_empty r
        r = Session.decipher Base64.urlsafe_encode64 's' * (256/8)
        assert_empty r
      end
    end
  end
end
