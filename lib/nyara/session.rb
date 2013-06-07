module Nyara
  # cookie based
  # usually it's no need to call cache or database data a "session"
  module Session
    extend self

    CIPHER_BLOCK_SIZE = 256/8

    # session is by default DSA + SHA384/SHA1 signed, sub config options are:
    #
    # - name       (session entry name in cookie, default is 'spare_me_plz')
    # - key        (DSA private key string, in der or pem format, use random if not given)
    # - cipher_key (if exist, use aes-256-cbc to cipher the "sig&json", the first 256bit is sliced for iv)

    # init from config
    def init
      c = Config['session'] || {}
      @name = (c['name'] || 'spare_me_plz').to_s

      if c['key']
        @dsa = OpenSSL::PKey::DSA.new c['key']
      else
        @dsa = OpenSSL::PKey::DSA.generate 384
      end

      # DSA can sign on any digest since 1.0.0
      @dss = OpenSSL::VERSION >= '1.0.0' ? OpenSSL::Digest::SHA384 : OpenSSL::Digest::DSS1

      @cipher_key = pad_256_bit c['cipher_key']
    end

    attr_reader :name

    def encode h, cookie
      str = h.to_json
      sig = @dsa.syssign @dss.digest str
      str = "#{Base64.urlsafe_encode64 sig}&#{str}"
      cookie[@name] = @cipher_key ? cipher(str) : str
    end

    def decode cookie
      str = cookie[@name].to_s
      return empty_hash if str.empty?

      str = decipher(str) if @cipher_key
      sig, str = str.split '&', 2
      return empty_hash unless str

      begin
        sig = Base64.urlsafe_decode64 sig
        verified = @dsa.sysverify @dss.digest(str), sig
        if verified
          h = JSON.parse str, create_additions: false, object_class: ParamHash
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

    # private

    def cipher str
      iv = rand(36**CIPHER_BLOCK_SIZE).to_s(36)
      c = new_cipher true, iv
      Base64.urlsafe_encode64(iv.dup << c.update(str) << c.final)
    end

    def decipher str
      str = Base64.urlsafe_decode64 str
      return '' if str.bytesize % CIPHER_BLOCK_SIZE != 0

      iv = str.byteslice 0...CIPHER_BLOCK_SIZE
      return '' if iv.bytesize < CIPHER_BLOCK_SIZE

      str = str.byteslice CIPHER_BLOCK_SIZE..-1
      c = new_cipher false, iv
      begin
        c.update(str) << c.final
      rescue OpenSSL::Cipher::CipherError
        ''
      end
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
