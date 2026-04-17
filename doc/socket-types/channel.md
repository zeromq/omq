# OMQ::CHANNEL

CHANNEL socket type ([RFC 52](https://rfc.zeromq.org/spec/52/)).

Single-frame, bidirectional, exclusive pair. Like PAIR but restricted to single-frame messages (draft socket).

## Usage

```ruby
require "omq"
require "omq/channel"

ch1 = OMQ::CHANNEL.bind("tcp://127.0.0.1:5555")
ch2 = OMQ::CHANNEL.connect("tcp://127.0.0.1:5555")

ch1 << "ping"
ch2.receive  # => "ping"
ch2 << "pong"
ch1.receive  # => "pong"
```
