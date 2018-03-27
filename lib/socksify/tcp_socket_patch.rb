require 'socksify/socks_error'

module Socksify
  module TCPSocketPatch
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

    module ClassMethods
      attr_accessor :socks_server, :socks_port, :socks_username, :socks_password
      attr_writer :socks_ignores

      def socks_version
        @socks_version ||= '5'
      end

      def socks_version=(version)
        @socks_version = version.to_s
      end

      def unicode_socks_version
        return "\004" if ['4', '4a'].include? socks_version
        "\005"
      end

      def socks_ignores
        @socks_ignores ||= %w(localhost)
      end
    end

    def self.prepended(base)
      base.send :extend, ClassMethods
    end

    # See http://tools.ietf.org/html/rfc1928
    def initialize(host=nil, port=0, local_host=nil, local_port=nil)
      if host.is_a?(SOCKSConnectionPeerAddress)
        socks_peer = host
        socks_server = socks_peer.socks_server
        socks_port = socks_peer.socks_port
        socks_ignores = []
        host = socks_peer.peer_host
      else
        socks_server = self.class.socks_server
        socks_port = self.class.socks_port
        socks_ignores = self.class.socks_ignores
      end

      if socks_server && socks_port && !socks_ignores.include?(host)
        Socksify::debug_notice "Connecting to SOCKS server #{socks_server}:#{socks_port}"

        super socks_server, socks_port

        socks_authenticate unless self.class.socks_version =~ /^4/

        if host
          socks_connect(host, port)
        end
      else
        Socksify::debug_notice "Connecting directly to #{host}:#{port}"
        super host, port, local_host, local_port
        Socksify::debug_debug "Connected to #{host}:#{port}"
      end
    end

    # Authentication
    def socks_authenticate
      if self.class.socks_username || self.class.socks_password
        Socksify::debug_debug "Sending username/password authentication"
        write "\005\001\002"
      else
        Socksify::debug_debug "Sending no authentication"
        write "\005\001\000"
      end
      Socksify::debug_debug "Waiting for authentication reply"
      auth_reply = recv(2)
      if auth_reply.empty?
        raise SOCKSError.new("Server doesn't reply authentication")
      end
      if auth_reply[0..0] != "\004" and auth_reply[0..0] != "\005"
        raise SOCKSError.new("SOCKS version #{auth_reply[0..0]} not supported")
      end
      if self.class.socks_username || self.class.socks_password
        if auth_reply[1..1] != "\002"
          raise SOCKSError.new("SOCKS authentication method #{auth_reply[1..1]} neither requested nor supported")
        end
        auth = "\001"
        auth += self.class.socks_username.to_s.length.chr
        auth += self.class.socks_username.to_s
        auth += self.class.socks_password.to_s.length.chr
        auth += self.class.socks_password.to_s
        write auth
        auth_reply = recv(2)
        if auth_reply[1..1] != "\000"
          raise SOCKSError.new("SOCKS authentication failed")
        end
      else
        if auth_reply[1..1] != "\000"
          raise SOCKSError.new("SOCKS authentication method #{auth_reply[1..1]} neither requested nor supported")
        end
      end
    end

    # Connect
    def socks_connect(host, port)
      port = Socket.getservbyname(port) if port.is_a?(String)
      req = String.new
      Socksify::debug_debug "Sending destination address"
      req << self.class.unicode_socks_version
      Socksify::debug_debug self.class.unicode_socks_version.unpack "H*"
      req << "\001"
      req << "\000" if self.class.socks_version == "5"
      req << [port].pack('n') if self.class.socks_version =~ /^4/

      if self.class.socks_version == "4"
        host = Resolv::DNS.new.getaddress(host).to_s
      end
      Socksify::debug_debug host
      if host =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/  # to IPv4 address
        req << "\001" if self.class.socks_version == "5"
        _ip = [$1.to_i,
               $2.to_i,
               $3.to_i,
               $4.to_i
              ].pack('CCCC')
        req << _ip
      elsif host =~ /^[:0-9a-f]+$/  # to IPv6 address
        raise "TCP/IPv6 over SOCKS is not yet supported (inet_pton missing in Ruby & not supported by Tor"
        req << "\004"
      else                          # to hostname
        if self.class.socks_version == "5"
          req << "\003" + [host.size].pack('C') + host
        else
          req << "\000\000\000\001"
          req << "\007\000"
          Socksify::debug_notice host
          req << host
          req << "\000"
        end
      end
      req << [port].pack('n') if self.class.socks_version == "5"
      write req

      socks_receive_reply
      Socksify::debug_notice "Connected to #{host}:#{port} over SOCKS"
    end

    # returns [bind_addr: String, bind_port: Fixnum]
    def socks_receive_reply
      Socksify::debug_debug "Waiting for SOCKS reply"

      if self.class.socks_version == "5"
        connect_reply = recv(4)
        if connect_reply.empty?
          raise SOCKSError.new("Server doesn't reply")
        end
        Socksify::debug_debug connect_reply.unpack "H*"
        if connect_reply[0..0] != "\005"
          raise SOCKSError.new("SOCKS version #{connect_reply[0..0]} is not 5")
        end
        if connect_reply[1..1] != "\000"
          raise SOCKSError.for_response_code(connect_reply.bytes.to_a[1])
        end
        Socksify::debug_debug "Waiting for bind_addr"
        bind_addr_len = case connect_reply[3..3]
                        when "\001"
                          4
                        when "\003"
                          recv(1).bytes.first
                        when "\004"
                          16
                        else
                          raise SOCKSError.for_response_code(connect_reply.bytes.to_a[3])
                        end
        bind_addr_s = recv(bind_addr_len)
        bind_addr = case connect_reply[3..3]
                    when "\001"
                      bind_addr_s.bytes.to_a.join('.')
                    when "\003"
                      bind_addr_s
                    when "\004"  # Untested!
                      i = 0
                      ip6 = ""
                      bind_addr_s.each_byte do |b|
                        if i > 0 and i % 2 == 0
                          ip6 += ":"
                        end
                        i += 1

                        ip6 += b.to_s(16).rjust(2, '0')
                      end
                    end
        bind_port = recv(bind_addr_len + 2)
        [bind_addr, bind_port.unpack('n')]
      else
        connect_reply = recv(8)
        unless connect_reply[0] == "\000" && connect_reply[1] == "\x5A"
          Socksify::debug_debug connect_reply.unpack 'H'
          raise SOCKSError.new("Failed while connecting througth socks")
        end
      end
    end
  end
end

TCPSocket.prepend Socksify::TCPSocketPatch
