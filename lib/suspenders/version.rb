# frozen_string_literal: true
module Suspenders
  RAILS_VERSION = '~> 4.2.0'.freeze
  RUBY_VERSION = IO.read("#{File.dirname(__FILE__)}/../../.ruby-version").strip
  VERSION = '1.35.5'.freeze
end
