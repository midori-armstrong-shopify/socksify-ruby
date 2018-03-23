# frozen_string_literal: true
require 'socksify'
require 'minitest/autorun'
require 'webmock/minitest'
require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = 'test/cassettes'
  config.hook_into :webmock
  config.allow_http_connections_when_no_cassette = true
end
