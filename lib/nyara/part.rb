module Nyara
  # A **part** in multipart<br>
  # for an easy introduction, http://msdn.microsoft.com/en-us/library/ms526943(v=exchg.10).aspx
  #
  # - todo make it possible to store data into /tmp (this requires memory threshold counting)
  # - todo nested multipart?
  class Part < ParamHash
    MECHANISMS = %w[base64 quoted-printable 7bit 8bit binary].freeze
    MECHANISMS.each &:freeze

    # rfc2616
    #
    #     token         := 1*<any CHAR except CTLs or separators>
    #     separators    := "(" | ")" | "<" | ">" | "@"
    #                    | "," | ";" | ":" | "\" | <">
    #                    | "/" | "[" | "]" | "?" | "="
    #                    | "{" | "}" | " " | "\t"
    #     CTL           := <any US-ASCII control character
    #                    (octets 0 - 31) and DEL (127)>
    #
    TOKEN = /[^\x00-\x1f\x7f()<>@,;:\\"\/\[\]?=\{\}\ \t]+/ni

    # rfc5978
    #
    #     attr-char   := ALPHA / DIGIT ; rfc5234
    #                 / "!" / "#" / "$" / "&" / "+" / "-" / "."
    #                 / "^" / "_" / "`" / "|" / "~"
    #
    ATTR_CHAR = /[a-z0-9!#$&+\-\.\^_`|~]/ni

    # rfc5978 (NOTE rfc2231 param continuations is not recommended)
    #
    #     value-chars := pct-encoded / attr-char
    #     pct-encoded := "%" HEXDIG HEXDIG
    #
    EX_PARAM = /\s*;\s*(filename|name)\s*(?:
      = \s* "((?>\\"|[^"])*)"         # quoted string - 2
      | = \s* (#{TOKEN})              # token - 3
      | \*= \s* ([\w\-]+)             # charset - 4
            '[\w\-]+'                 # language
            ((?>%\h\h|#{ATTR_CHAR})+) # value-chars - 5
    )/xni

    # Analyse given `head` and build a param hash representing the part
    #
    # * `head`      - header
    # * `mechanism` - 7bit, 8bit, binary, base64, or quoted-printable
    # * `type`      - mime type
    # * `data`      - decoded data (incomplete before Part#final called)
    # * `filename`  - basename of uploaded data
    # * `name`      - param name
    #
    def initialize head
      self['head'] = head
      if mechanism = head['Content-Transfer-Encoding']
        self['mechanism'] = mechanism.strip.downcase
      end
      if self['type'] = head['Content-Type']
        self['type'] = self['type'][/.*?(?=;|$)/]
      end
      self['data'] = ''.force_encoding('binary')

      disposition = head['Content-Disposition']
      if disposition
        # skip first token
        ex_params = disposition.sub TOKEN, ''

        # store values not so specific as encoded value
        tmp_values = {}
        ex_params.scan EX_PARAM do |name, v1, v2, enc, v3|
          name.downcase!
          if enc
            # value with charset and lang is more specific
            self[name] ||= enc_unescape enc, v3
          else
            tmp_values[name] ||= (v1 || (CGI.unescape(v2) rescue nil))
          end
        end
        self['filename'] ||= tmp_values['filename']
        self['name'] ||= tmp_values['name']
      end
      if self['filename']
        self['filename'] = File.basename self['filename']
      end
      self['name'] ||= head['Content-Id']
    end

    # #### Params
    #
    # - `raw` in binary encoding
    def update raw
      case self['mechanism']
      when 'base64'
        # rfc2045#section-6.8
        raw.gsub! /\s+/n, ''
        if self['tmp']
          raw = (self['tmp'] << raw)
        end
        # last part can be at most 4 bytes and 2 '='s
        size = raw.bytesize - 6
        if size >= 4
          size = size / 4 * 4
          self['data'] << raw.slice!(0...size).unpack('m').first
        end
        self['tmp'] = raw

      when 'quoted-printable'
        # http://en.wikipedia.org/wiki/Quoted-printable
        if self['tmp']
          raw = (self['tmp'] << raw)
        end
        if i = raw.rindex("\r\n")
          s = raw.slice! i
          s.gsub!(/=(?:(\h\h)|\r\n)/n) do
            [$1].pack 'H*'
          end
          self['data'] << s
        end
        self['tmp'] = raw

      else # '7bit', '8bit', 'binary', ...
        self['data'] << raw
      end
    end

    def final
      case self['mechanism']
      when 'base64'
        if tmp = self['tmp']
          self['data'] << tmp.unpack('m').first
          delete 'tmp'
        end

      when 'quoted-printable'
        if tmp = self['tmp']
          self['data'] << tmp.gsub(/=(\h\h)|=\r\n/n) do
            [$1].pack 'H*'
          end
          delete 'tmp'
        end
      end
      self
    end

    # @private
    def enc_unescape enc, v # :nodoc:
      enc = (Encoding.find enc rescue nil)
      v = CGI.unescape v
      v.force_encoding(enc).encode!('utf-8') if enc
      v
    rescue
      nil
    end
  end
end
