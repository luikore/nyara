# patch with 2.1 methods if not defined
class String
  unless defined? b
    def b
      dup.force_encoding 'binary'
    end
  end

  unless defined? scrub
    def scrub replacement=nil
      return self if self.valid_encoding?
      self.each_char.map do |char|
        if char.valid_encoding?
          char
        else
          block_given? ? yield(char) : replacement
        end
      end.join
    end
  end
end
