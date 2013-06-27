module Nyara
  # keys ignore case, and values all string<br>
  # TODO check invalid chars in values
  class HeaderHash
    alias has_key? key?

    CONTENT_TYPE = 'Content-Type'.freeze

    def aref_content_type
      self._aref CONTENT_TYPE
    end

    def aset_content_type value
      unless value.index 'charset'
        value = "#{value}; charset=UTF-8"
      end
      self._aset CONTENT_TYPE, value
    end
  end
end
