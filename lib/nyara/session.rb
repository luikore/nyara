module Nyara
  # cookie based session<br>
  # (usually it's no need to call cache or database data a "session")<br><br>
  # session is by default DSA + SHA2/SHA1 signed, sub config options are:
  #
  # [name]       session entry name in cookie, default is +'spare_me_plz'+
  # [expire]     expire session after seconds. default is +nil+, which means session expires when browser is closed<br>
  # [expires]    same as +expire+
  # [secure]     - +nil+(default): if request is https, add +Secure+ option to it
  #              - +true+: always add +Secure+
  #              - +false+: always no +Secure+
  # [key]        DSA private key string, in der or pem format, use random if not given
  # [cipher_key] if exist, use aes-256-cbc to cipher the "sig/json"<br>
  #              NOTE: it's no need to set +cipher_key+ if using https
  #
  # = example
  #
  #   configure do
  #     set 'session', 'key', File.read(project_path 'config/session.key')
  #     set 'session', 'expire', 30 * 60
  #   end
  #
  class Session < ParamHash
    attr_reader :init_digest, :init_data

    # if the session is init with nothing, and flash is clear
    def vanila?
      if @init_digest.nil?
        empty? or size == 1 && has_key?('flash.next') && self['flash.next'].empty?
      end
    end
  end

  class << Session
    CIPHER_BLOCK_SIZE = 256/8
    CIPHER_RAND_MAX = 36**CIPHER_BLOCK_SIZE
    JSON_DECODE_OPTS = {create_additions: false, object_class: Session}

    # init from config
    def init
      c = Config['session'] ? Config['session'].dup : {}
      @name = Ext.escape (c.delete('name') || 'spare_me_plz').to_s, false

      if c['key']
        @dsa = OpenSSL::PKey::DSA.new c.delete 'key'
      else
        @dsa = generate_key
      end

      # DSA can sign on any digest since 1.0.0
      @dss = OpenSSL::VERSION >= '1.0.0' ? OpenSSL::Digest::SHA256 : OpenSSL::Digest::DSS1

      @cipher_key = pad_256_bit c.delete 'cipher_key'

      @expire = c.delete('expire') || c.delete('expires')
      @secure = c.delete('secure')

      unless c.empty?
        raise "unknown options in Nyara::Config[:session]: #{c.inspect}"
      end
    end

    attr_reader :name

    # encode into a cookie hash, for test environment
    def encode_to_cookie h, cookie
      cookie[@name] = encode h
    end

    # encode to value<br>
    # return nil if not changed
    def encode h
      return if h.vanila?
      str = h.to_json
      str = @cipher_key ? cipher(str) : encode64(str)
      digest = @dss.digest str
      return h.init_data if digest == h.init_digest

      sig = @dsa.syssign digest
      "#{encode64 sig}/#{str}"
    end

    # encode as header line
    def encode_set_cookie h, secure
      secure = @secure unless @secure.nil?
      expire = (Time.now + @expire).gmtime.rfc2822 if @expire
      "Set-Cookie: #{@name}=#{encode h}; Path=/; HttpOnly#{'; Secure' if secure}#{"; Expires=#{expire}" if expire}\r\n"
    end

    # decode the session hash from cookie
    def decode cookie
      data = cookie[@name].to_s
      return empty_hash if data.empty?

      sig, str = data.split '/', 2
      return empty_hash unless str

      h = nil
      digest = nil
      begin
        sig = decode64 sig
        digest = @dss.digest str
        if @dsa.sysverify(digest, sig)
          str = @cipher_key ? decipher(str) : decode64(str)
          h = JSON.parse str, JSON_DECODE_OPTS
        end
      ensure
        return empty_hash unless h
      end

      if h.is_a?(Session)
        h.instance_variable_set :@init_digest, digest
        h.instance_variable_set :@init_data, data
        h
      else
        empty_hash
      end
    end

    def generate_key
      OpenSSL::PKey::DSA.generate 256
    end

    # private

    def encode64 s
      [s].pack('m0').tr("+/", "-_")
    end

    def decode64 s
      s.tr("-_", "+/").unpack('m0').first
    end

    def cipher str
      iv = rand(CIPHER_RAND_MAX).to_s(36).ljust CIPHER_BLOCK_SIZE
      c = new_cipher true, iv
      encode64(iv.dup << c.update(str) << c.final)
    end

    def decipher str
      str = decode64 str
      iv = str.byteslice 0...CIPHER_BLOCK_SIZE
      str = str.byteslice CIPHER_BLOCK_SIZE..-1
      return '' if !str or str.empty?
      c = new_cipher false, iv
      c.update(str) << c.final rescue ''
    end

    def pad_256_bit s
      s = s.to_s
      return nil if s.empty?
      len = CIPHER_BLOCK_SIZE
      s[0...len].ljust len, '*'
    end

    def empty_hash
      # todo invoke hook?
      Session.new
    end

    def new_cipher encrypt, iv
      c = OpenSSL::Cipher.new 'aes-256-cbc'
      encrypt ? c.encrypt : c.decrypt
      c.key = @cipher_key
      c.iv = iv
      c
    end
  end
end
