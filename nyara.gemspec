Gem::Specification.new do |s|
  s.name = "nyara"
  s.version = "0.0.1.pre.7"
  s.author = "Zete Lui"
  s.email = "nobody@example.com"
  s.homepage = "https://github.com/luikore/nyara"
  s.platform = Gem::Platform::RUBY
  s.summary = "Fast, slim and fuzzy ruby web framework + server"
  s.description = "Fast, slim and fuzzy ruby web framework + server, based on preforked event queue and Fiber. NO rack NOR eventmachine are used."
  s.required_ruby_version = ">=2.0.0"
  s.licenses = ['BSD 3-Clause']

  s.files = Dir.glob('{rakefile,nyara.gemspec,readme.md,**/*.{rb,h,c,cc,inc}}')
  s.files += Dir.glob('ext/http-parser/{AUTHORS,CONTRIBUTIONS,LICENSE-MIT}')
  s.files += Dir.glob('ext/multipart-parser-c/README.md')
  s.require_paths = ["lib"]
  s.extensions = ["ext/extconf.rb"]
  s.rubygems_version = '2.0.3'
  s.has_rdoc = false
end
