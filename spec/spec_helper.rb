require 'rspec/core'
require 'rspec/mocks'
require 'rspec/autorun'
require "pry"
require "slim"
require "erb"
require "erubis"
require "haml"
require "liquid"
require "open-uri"
require "base64"
require 'pp'

if ENV['COVERAGE']
  require "simplecov"
  SimpleCov.start do
    coverage_dir '.coverage'
    add_group 'lib', 'lib'
  end
end
require_relative "../lib/nyara/nyara"
require_relative "../lib/nyara/test"

RSpec.configure do |config|
  config.expect_with :stdlib
  if config.formatters.first.class.to_s =~ /TextMate/
    def puts *xs
      xs.each do |x|
        $stdout.puts "<pre style='word-wrap:break-word;word-break:break-all;'>#{CGI.escape_html x.to_s}</pre>"
      end
      nil
    end

    def print *xs
      $stdout.print "<span style='word-wrap:break-word;word-break:break-all;'>"
      xs.each do |x|
        $stdout.print CGI.escape_html x.to_s
      end
      $stdout.print "</span>"
      nil
    end

    def p *xs
      xs.each do |x|
        $stdout.puts "<pre style='word-wrap:break-word;word-break:break-all;'>#{CGI.escape_html x.inspect}</pre>"
      end
      xs
    end

    module Kernel
      def pp obj
        s = CGI.escape_html(PP.pp obj, '')
        $stdout.puts "<pre style='word-wrap:break-word;word-break:break-all;'>#{s}</pre>"
        obj
      end
    end
  end

  if ENV['STRESS']
    puts "Enabling GC.stress mode"

    config.before :each do
      GC.stress = true
    end

    config.after :each do
      GC.stress = false
    end
  end
end

configure do
  set :env, 'test'
end
