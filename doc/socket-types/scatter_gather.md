# OMQ::SCATTER and OMQ::GATHER

SCATTER and GATHER socket types ([RFC 49](https://rfc.zeromq.org/spec/49/)).

Single-frame PUSH/PULL equivalent. SCATTER round-robins, GATHER fair-queues.

## Usage

```ruby
require "omq"
require "omq/scatter_gather"

gather  = OMQ::GATHER.bind("tcp://127.0.0.1:5555")
scatter = OMQ::SCATTER.connect("tcp://127.0.0.1:5555")

scatter << "work item"
msg = gather.receive  # => "work item"
```
