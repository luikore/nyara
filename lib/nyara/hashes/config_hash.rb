module Nyara
  # Extended hash class for the use in configuration.
  class ConfigHash
    # #### Call-seq
    #
    #     config['a', 'very', 'deep', '', 'key']
    #
    # Equivalent to
    #
    #     config['a']['very']['deep'].last['key'] rescue nil
    #
    def [] *keys
      nested_aref keys.map(&:to_s)
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
