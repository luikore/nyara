module Nyara
  # Keys ignore case and access is indifferent between String keys and Symbol keys.<br>
  # All keys are stored in String form.
  class ParamHash
    alias has_key? key?
  end
end
