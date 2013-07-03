module Nyara
  # helper module for session management, cookie based<br>
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
  module Session
    extend self

    CIPHER_BLOCK_SIZE = 256/8
    JSON_DECODE_OPTS = {create_additions: false, object_class: ParamHash}

    # init from config
    def init
      c = Config['session'] ? Config['session'].dup : {}
      @name = (c.delete('name') || 'spare_me_plz').to_s

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

    # encode to value
    def encode h
      str = h.to_json
      sig = @dsa.syssign @dss.digest str
      str = "#{encode64 sig}/#{encode64 str}"
      @cipher_key ? cipher(str) : str
    end

    # encode as header line
    def encode_set_cookie h, secure
      secure = @secure unless @secure.nil?
      expire = (Time.now + @expire).gmtime.rfc2822 if @expire
      "Set-Cookie: #{@name}=#{encode h}; HttpOnly#{'; Secure' if secure}#{"; Expires=#{expire}" if expire}\r\n"
    end

    def decode cookie
      str = cookie[@name].to_s
      return empty_hash if str.empty?

      str = decipher(str) if @cipher_key
      sig, str = str.split '/', 2
      return empty_hash unless str

      begin
        sig = decode64 sig
        str = decode64 str
        if @dsa.sysverify(@dss.digest(str), sig)
          h = JSON.parse str, JSON_DECODE_OPTS
        end
      ensure
        return empty_hash unless h
      end

      if h.is_a?(ParamHash)
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
      iv = rand(36**CIPHER_BLOCK_SIZE).to_s(36).ljust CIPHER_BLOCK_SIZE
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
      ParamHash.new
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
