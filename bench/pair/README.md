# PAIR Benchmark

Exclusive pair throughput: one PAIR ↔ one PAIR.

OMQ 0.14.0 · Ruby 4.0.2 (+YJIT) · Linux 6.12

## 1 peer

|   Size |             inproc |                ipc |                tcp |              curve |             blake3 |
|    ---:|                ---:|                ---:|                ---:|                ---:|                ---:|
|   64 B | 20.3 MB/s    317k/s | 13.2 MB/s    207k/s | 13.9 MB/s    217k/s |  5.0 MB/s     78k/s |  7.0 MB/s    109k/s |
|  256 B | 101.1 MB/s    395k/s | 45.1 MB/s    176k/s | 42.1 MB/s    164k/s | 19.2 MB/s     75k/s | 25.0 MB/s     98k/s |
|   1 KB | 625.7 MB/s    611k/s | 130.8 MB/s    128k/s | 178.0 MB/s    174k/s | 52.2 MB/s     51k/s | 81.0 MB/s     79k/s |
|   4 KB |  2.4 GB/s    593k/s | 302.8 MB/s     74k/s | 434.9 MB/s    106k/s | 124.3 MB/s     30k/s | 182.8 MB/s     45k/s |
|  64 KB | 40.7 GB/s    621k/s | 674.8 MB/s     10k/s | 807.4 MB/s     12k/s | 259.7 MB/s      4k/s | 325.1 MB/s      5k/s |
