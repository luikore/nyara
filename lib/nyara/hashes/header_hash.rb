module Nyara
  # This is a hash that Keys ignore case, and values all string, suitable for use in http header<br>
  # TODO check invalid chars in values<br>
  # TODO integrate extra lines
  class HeaderHash
    alias has_key? key?

    CONTENT_TYPE = 'Content-Type'.freeze

    def aref_content_type
      _aref CONTENT_TYPE
    end

    def aset_content_type value
      unless value.index 'charset'
        value = "#{value}; charset=UTF-8"
      end
      _aset CONTENT_TYPE, value
    end
  end
end
