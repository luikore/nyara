module Nyara
  # Extended hash class for the use in configuration.
  class ConfigHash
    # @private
    alias _aref [] # :nodoc:
    # @private
    alias _aset []= # :nodoc:

    # #### Call-seq
    #
    #     config['a', 'very', 'deep', 'key']
    #
    # Equivalent to
    #
    #     config['a']['very']['deep']['key'] rescue nil
    #
    def [] *keys
      h = self
      keys.each do |key|
        if h.has_key?(key)
          if h.is_a?(ConfigHash)
            h = h._aref key
          else
            h = h[key]
          end
        else
          return nil # todo default value?
        end
      end
      h
    end

    # #### Call-seq
    #
    #     config['a', 'very', 'deep', 'key'] = value
    #
    # All intermediate level ConfigHashes are created automatically
    def []= *keys, value
      nested_aset keys.map(&:to_s), value
    end
  end
end
