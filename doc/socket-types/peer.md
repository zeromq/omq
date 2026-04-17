# OMQ::PEER

PEER socket type ([RFC 51](https://rfc.zeromq.org/spec/51/)).

True peer-to-peer messaging. Each PEER can both bind and connect, routing by 4-byte connection ID.

## Usage

```ruby
require "omq"
require "omq/peer"

peer1 = OMQ::PEER.bind("tcp://127.0.0.1:5555")
peer2 = OMQ::PEER.connect("tcp://127.0.0.1:5555")

peer2 << "hello from peer2"
msg, routing_id = peer1.receive_with_routing_id
peer1.send_to(routing_id, "hello back")
```
