# Socksify

## What is it?

**Socksify** redirects any TCP connection initiated by a Ruby script through a SOCKS5 proxy. It serves as a small drop-in alternative to [tsocks](http://tsocks.sourceforge.net/), except that it handles Ruby programs only and doesn't leak DNS queries.

### How does it work?

Modifications to class `TCPSocket` - prepends a new initialize method which:

- Calls super to establish a TCP connection to the SOCKS proxy
- Sends the proxying destination
- Checks for errors

Additionally, `Socksify::resolve` can be used to resolve hostnames to IPv4 addresses via SOCKS. There is also `socksify/http` enabling Net::HTTP to work via SOCKS.

## Installation

```
$ gem install socksify
```

## Usage

### Redirect all TCP connections of a Ruby program

Run a Ruby script with redirected TCP through a local [Tor](http://www.torproject.org/) anonymizer:

```
$ socksify_ruby localhost 9050 script.rb
```

### Explicit SOCKS usage in a Ruby program

Set up SOCKS connections for a local [Tor](http://www.torproject.org/) anonymizer, TCPSockets can be used as usual:

```ruby
require 'socksify'

TCPSocket::socks_server = "127.0.0.1"
TCPSocket::socks_port = 9050
rubyforge_www = TCPSocket.new("rubyforge.org", 80)
# => #<TCPSocket:0x...>
```

Using block only:

```ruby
require 'socksify'
require 'open-uri'

Socksify::proxy("127.0.0.1", 9050) {
  open('http://rubyforge.org').read
  # => #<String: rubyforge's html>
}
```

Please note: **socksify is not thread-safe** when used this way! `socks_server` and `socks_port` are stored in class `@@`-variables, and applied to all threads and fibers of application.

### Use Net::HTTP explicitly via SOCKS

Require the additional library `socksify/http` and use the `Net::HTTP.SOCKSProxy` method. It is similar to `Net:HTTP.Proxy` from the Ruby standard library:

```ruby
require 'socksify/http'

uri = URI.parse('http://rubyforge.org/')
Net::HTTP.SOCKSProxy('127.0.0.1', 9050).start(uri.host, uri.port) do |http|
  http.get(uri.path)
end
# => #<Net::HTTPOK 200 OK readbody=true>
```

Note that `Net::HTTP.SOCKSProxy` never relies on `TCPSocket::socks_server`/`socks_port`. You should either set `SOCKSProxy` arguments explicitly or use `Net::HTTP` directly.

### Resolve addresses via SOCKS

```ruby
Socksify::resolve("spaceboyz.net")
# => "87.106.131.203"
```

### Debugging

Colorful diagnostic messages can be enabled via:

```ruby
Socksify::debug = true
```

## Development

This repository can be checked out with:

```
$ git clone git@github.com:astro/socksify-ruby.git
```

Send patches via GitHub.

### Further ideas

*   `Resolv` replacement code, so that programs which resolve by themselves don't leak DNS queries
*   IPv6 address support
*   UDP as soon as [Tor](http://www.torproject.org/) supports it
*   Perhaps using standard exceptions for better compatibility when acting as a drop-in?

## Author

*   [Stephan Maka](mailto:stephan@spaceboyz.net)

## License

Socksify is distributed under the terms of the GNU General Public License version 3 (see file `COPYING`) or the Ruby License (see file `LICENSE`) at your option.
