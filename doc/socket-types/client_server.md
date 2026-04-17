# OMQ::CLIENT and OMQ::SERVER

CLIENT and SERVER socket types ([RFC 41](https://rfc.zeromq.org/spec/41/)).

Single-frame, asynchronous request-reply. SERVER routes by 4-byte connection ID; CLIENT round-robins.

## Usage

```ruby
require "omq"
require "omq/client_server"

server = OMQ::SERVER.bind("tcp://127.0.0.1:5555")
client = OMQ::CLIENT.connect("tcp://127.0.0.1:5555")

client << "hello"
msg, routing_id = server.receive_with_routing_id
server.send_to(routing_id, msg.upcase)
reply = client.receive  # => "HELLO"
```
