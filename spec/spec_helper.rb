require_relative "../lib/nyara/nyara"
require 'rspec/core'
require 'rspec/mocks'
require 'rspec/autorun'
require "pry"

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

    require 'pp'
    module Kernel
      def pp obj
        s = CGI.escape_html(PP.pp obj, '')
        $stdout.puts "<pre style='word-wrap:break-word;word-break:break-all;'>#{s}</pre>"
        obj
      end
    end
  end
end

configure do
  set :env, 'test'
end

# todo a test helper to compile routes after app loaded
