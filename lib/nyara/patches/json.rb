require "json"

# +JSON.parse '{"json_class":"MyClass"}'+ should not visit MyClass
JSON.load_default_options.merge! create_additions: false

# +{a:'</script>'}.to_json+ should escape tag chars
JSON.dump_default_options.merge! quirks_mode: false

# should not be able to create GenericObject
JSON::GenericObject.json_creatable = true
