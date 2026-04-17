# OMQ::RADIO and OMQ::DISH

RADIO and DISH socket types with UDP transport ([RFC 48](https://rfc.zeromq.org/spec/48/)).

Group-based pub/sub. RADIO publishes to named groups; DISH joins groups of interest. Works over TCP, IPC, inproc, and unicast UDP.

`require "omq/radio_dish"` also registers the `udp://` transport scheme with `OMQ::Engine.transports`.

## Usage

```ruby
require "omq"
require "omq/radio_dish"

dish = OMQ::DISH.bind("tcp://127.0.0.1:5555")
dish.join("weather")

radio = OMQ::RADIO.connect("tcp://127.0.0.1:5555")
radio.publish("weather", "sunny")

group, msg = dish.receive  # => ["weather", "sunny"]
```

### UDP

The endpoint scheme is `udp://` and the rest of the API is unchanged:

```ruby
dish = OMQ::DISH.bind("udp://127.0.0.1:5555")
dish.join("weather")

radio = OMQ::RADIO.connect("udp://127.0.0.1:5555")
radio.publish("weather", "sunny")

group, msg = dish.receive  # => ["weather", "sunny"]
```

Each message is a single UDP datagram — there is no handshake, no reconnect, and no delivery guarantee. Payloads must fit inside one datagram (typically ≤ 1472 bytes on Ethernet).
