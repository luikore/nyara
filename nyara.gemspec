Gem::Specification.new do |s|
  s.name = "nyara"
  s.version = "0.1.pre.1"
  s.author = "Zete Lui"
  s.email = "nobody@example.com"
  s.homepage = "https://github.com/luikore/nyara"
  s.platform = Gem::Platform::RUBY
  s.summary = "Fast and fuzzy ruby web framework + server"
  s.description = "Fast and fuzzy ruby web framework + server"
  s.required_ruby_version = ">=2.0.0"
  s.licenses = ['BSD 3-Clause']

  s.files = Dir.glob('{rakefile,nyara.gemspec,readme.md,copying,changes,**/*.{rb,h,c,cc,inc}}')
  s.files += Dir.glob('spec/**/*')
  s.files += Dir.glob('ext/http-parser/{AUTHORS,CONTRIBUTIONS,LICENSE-MIT}')
  s.files += Dir.glob('ext/multipart-parser-c/README.md')
  s.files += Dir.glob('lib/nyara/templates/**/*') - %w[.DS_Store]
  s.files.uniq!
  s.require_paths = ["lib"]
  s.executables << 'nyara'
  s.extensions = ["ext/extconf.rb"]
  s.rubygems_version = '2.0.3'
  s.add_runtime_dependency 'tilt', '>= 1.3'
  s.add_runtime_dependency 'listen', '>= 1.1.3'
  s.add_runtime_dependency 'thor', '>= 0.18'

  s.rdoc_options += %w[
    -v
    --markup=markdown
    --main readme.md
    --line-numbers
    -x ext/http-parser/.*
    -x ext/multipart-parser-c/.*
    -x ext/inc/.*
    -x .*\.o
    -x .*\.bundle
    -x .*\.so
  ]
end
