require "json"

# +JSON.parse '{"json_class":"MyClass"}'+ should not create object as MyClass
JSON.load_default_options.merge! create_additions: false
JSON::GenericObject.json_creatable = false

[Object, Array, FalseClass, Float, Hash, Integer, NilClass, String, TrueClass].each do |klass|
  klass.class_eval do
    # Dumps object in JSON (JavaScript Object Notation). See www.json.org for more info.
    # "</" is escaped for convenience use in javascript
    def to_json(options = nil)
      super(options).gsub '</', "<\\/"
    end
  end
end
