# DEALER/DEALER Benchmark

Bidirectional pipeline: one DEALER (bind), N DEALER peers (connect).

OMQ 0.14.0 · Ruby 4.0.2 (+YJIT) · Linux 6.12

## 1 peer

|   Size |             inproc |                ipc |                tcp |              curve |             blake3 |
|    ---:|                ---:|                ---:|                ---:|                ---:|                ---:|
|   64 B | 19.2 MB/s    301k/s | 12.8 MB/s    200k/s | 13.3 MB/s    209k/s |  5.3 MB/s     84k/s |  7.1 MB/s    111k/s |
|  256 B | 106.6 MB/s    416k/s | 38.9 MB/s    152k/s | 40.3 MB/s    158k/s | 19.3 MB/s     75k/s | 22.4 MB/s     87k/s |
|   1 KB | 573.5 MB/s    560k/s | 124.6 MB/s    122k/s | 170.3 MB/s    166k/s | 48.9 MB/s     48k/s | 74.2 MB/s     72k/s |
|   4 KB |  2.8 GB/s    681k/s | 276.4 MB/s     67k/s | 397.8 MB/s     97k/s | 124.1 MB/s     30k/s | 156.9 MB/s     38k/s |
|  64 KB | 37.4 GB/s    570k/s | 667.7 MB/s     10k/s | 883.5 MB/s     13k/s | 256.0 MB/s      4k/s | 312.3 MB/s      5k/s |

## 3 peers

|   Size |             inproc |                ipc |                tcp |              curve |             blake3 |
|    ---:|                ---:|                ---:|                ---:|                ---:|                ---:|
|   64 B | 26.2 MB/s    409k/s | 11.2 MB/s    175k/s | 11.9 MB/s    186k/s |  4.3 MB/s     67k/s |  7.5 MB/s    117k/s |
|  256 B | 111.0 MB/s    433k/s | 33.6 MB/s    131k/s | 41.9 MB/s    164k/s | 13.7 MB/s     54k/s | 19.7 MB/s     77k/s |
|   1 KB | 498.6 MB/s    487k/s | 127.8 MB/s    125k/s | 135.2 MB/s    132k/s | 47.2 MB/s     46k/s | 64.1 MB/s     63k/s |
|   4 KB |  1.9 GB/s    458k/s | 327.9 MB/s     80k/s | 375.6 MB/s     92k/s | 115.5 MB/s     28k/s | 149.8 MB/s     37k/s |
|  64 KB | 60.2 GB/s    919k/s | 769.6 MB/s     12k/s | 848.9 MB/s     13k/s | 236.3 MB/s      4k/s | 300.1 MB/s      5k/s |
