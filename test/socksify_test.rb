#!/usr/bin/ruby

require 'test_helper'
require 'net/http'
require 'uri'
require 'openssl'

$:.unshift "#{File::dirname($0)}/../lib/"
require 'socksify/http'

class SocksifyTest < MiniTest::Test
  ACCESSED_URL = 'https://check.torproject.org/'
  ACCESSED_URL_HOST = 'check.torproject.org'
  ACCESSED_URL_REGEX = /Your IP address appears to be:\s*<strong>(\d+\.\d+\.\d+\.\d+)<\/strong>/

  ACCESSED_IP = 'https://213.180.204.62/'
  ACCESSED_IP_HOST = 'yandex.com'
  ACCESSED_IP_PATH = '/internet/'
  ACCESSED_IP_REGEX = /<div class="client__desc">(\d+\.\d+\.\d+\.\d+)/

  SOCKS_SERVER = '127.0.0.1' # localhost - server must be set up locally
  SOCKS_PORT = 9050

  def setup
    Socksify::debug = true
    WebMock.allow_net_connect!
    enable_socks
  end

  def test_connect_to_url
    socks_ip = nil
    VCR.use_cassette('url/with_socks') do
      socks_body = get_http(Net::HTTP, ACCESSED_URL, ACCESSED_URL_HOST)
      socks_ip = find_ip_in_body(socks_body, ACCESSED_URL_REGEX)
    end

    disable_socks

    no_socks_ip = nil
    VCR.use_cassette('url/no_socks') do
      no_socks_body = get_http(Net::HTTP, ACCESSED_URL, ACCESSED_URL_HOST)
      no_socks_ip = find_ip_in_body(no_socks_body, ACCESSED_URL_REGEX)
    end

    refute_equal no_socks_ip, socks_ip
  end

  def test_connect_to_url_via_net_http_proxy
    disable_socks

    http_proxy_ip = nil
    VCR.use_cassette('url/http_proxy') do
      http_proxy_body = get_http(http_tor_proxy, ACCESSED_URL)
      http_proxy_ip = find_ip_in_body(http_proxy_body, ACCESSED_URL_REGEX)
    end

    no_socks_ip = nil
    VCR.use_cassette('url/no_socks') do
      no_socks_body = get_http(Net::HTTP, ACCESSED_URL)
      no_socks_ip = find_ip_in_body(no_socks_body, ACCESSED_URL_REGEX)
    end

    refute_equal no_socks_ip, http_proxy_ip
  end

  def test_connect_to_ip
    socks_ip = nil
    VCR.use_cassette('ip/with_socks') do
      socks_body = get_http(Net::HTTP, ACCESSED_IP, ACCESSED_IP_HOST, ACCESSED_IP_PATH)
      socks_ip = find_ip_in_body(socks_body, ACCESSED_IP_REGEX)
    end

    disable_socks

    no_socks_ip = nil
    VCR.use_cassette('ip/no_socks') do
      no_socks_body = get_http(Net::HTTP, ACCESSED_IP, ACCESSED_IP_HOST, ACCESSED_IP_PATH)
      no_socks_ip = find_ip_in_body(no_socks_body, ACCESSED_IP_REGEX)
    end

    refute_equal no_socks_ip, socks_ip
  end

  def test_connect_to_ip_via_net_http
    disable_socks

    http_proxy_ip = nil
    VCR.use_cassette('ip/http_proxy') do
      http_proxy_body = get_http(http_tor_proxy, ACCESSED_IP, ACCESSED_IP_HOST, ACCESSED_IP_PATH)
      http_proxy_ip = find_ip_in_body(http_proxy_body, ACCESSED_IP_REGEX)
    end

    no_socks_ip = nil
    VCR.use_cassette('ip/no_socks') do
      no_socks_body = get_http(Net::HTTP, ACCESSED_IP, ACCESSED_IP_HOST, ACCESSED_IP_PATH)
      no_socks_ip = find_ip_in_body(no_socks_body, ACCESSED_IP_REGEX)
    end

    refute_equal no_socks_ip, http_proxy_ip
  end

  def test_ignores
    TCPSocket.socks_ignores << ACCESSED_URL_HOST

    socks_ip = nil
    VCR.use_cassette('url/with_socks') do
      socks_body = get_http(Net::HTTP, ACCESSED_URL, ACCESSED_URL_HOST)
      socks_ip = find_ip_in_body(socks_body, ACCESSED_URL_REGEX)
    end

    disable_socks

    no_socks_ip = nil
    VCR.use_cassette('url/no_socks') do
      no_socks_body = get_http(Net::HTTP, ACCESSED_URL)
      no_socks_ip = find_ip_in_body(no_socks_body, ACCESSED_URL_REGEX)
    end

    refute_equal no_socks_ip, socks_ip
  end

  def test_proxy
    default_server = TCPSocket.socks_server
    default_port = TCPSocket.socks_port

    Socksify.proxy('localhost.example.com', 60001) {
      assert_equal TCPSocket.socks_server, 'localhost.example.com'
      assert_equal TCPSocket.socks_port, 60001
    }

    assert_equal TCPSocket.socks_server, default_server
    assert_equal TCPSocket.socks_port, default_port
  end

  def test_proxy_failback
    default_server = TCPSocket.socks_server
    default_port = TCPSocket.socks_port

    assert_raises StandardError do
      Socksify.proxy('localhost.example.com', 60001) {
        raise StandardError.new('error')
      }
    end

    assert_equal TCPSocket.socks_server, default_server
    assert_equal TCPSocket.socks_port, default_port
  end

  # def test_resolve
  #   VCR.use_cassette('resolve/forward_reachable') do
  #     assert_equal '8.8.8.8', Socksify::resolve('google-public-dns-a.google.com')
  #   end

  #   VCR.use_cassette('resolve/forward_unreachable') do
  #     assert_raises Socksify::SOCKSError::HostUnreachable do
  #       Socksify::resolve 'nonexistent.spaceboyz.net'
  #     end
  #   end
  # end

  # def test_resolve_reverse
  #   VCR.use_cassette('resolve/reverse_reachable') do
  #     assert_equal('google-public-dns-a.google.com', Socksify::resolve('8.8.8.8'))
  #   end

  #   VCR.use_cassette('resolve/reverse_unreachable') do
  #     assert_raises Socksify::SOCKSError::HostUnreachable do
  #       Socksify::resolve('0.0.0.0')
  #     end
  #   end
  # end

  def teardown
    disable_socks
    WebMock.disable_net_connect!
  end

  private

  def disable_socks
    TCPSocket.socks_server = nil
    TCPSocket.socks_port = nil
  end

  def enable_socks
    TCPSocket.socks_server = SOCKS_SERVER
    TCPSocket.socks_port = SOCKS_PORT
  end

  def http_tor_proxy
    Net::HTTP::SOCKSProxy(SOCKS_SERVER, SOCKS_PORT)
  end

  def get_http(net_http_klass, url, host_header = nil, path = nil)
    uri = URI.parse(url)

    body = nil
    net_http_klass.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', verify_mode: OpenSSL::SSL::VERIFY_NONE) do |http|
      req = Net::HTTP::Get.new(path || '/')
      req['Host'] = host_header || uri.host
      req['User-Agent'] = 'ruby-socksify test'
      body = http.request(req)&.body
    end

    body
  end

  def find_ip_in_body(body, regex)
    return $1 if body =~ regex
    raise 'Bogus response: No IP'
  end
end
