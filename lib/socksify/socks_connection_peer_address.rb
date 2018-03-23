module Socksify
  class SOCKSConnectionPeerAddress < String
    attr_reader :socks_server, :socks_port

    def initialize(socks_server, socks_port, peer_host)
      @socks_server, @socks_port = socks_server, socks_port
      super peer_host
    end

    def inspect
      "#{to_s} (via #{@socks_server}:#{@socks_port})"
    end

    def peer_host
      to_s
    end
  end
end
