# PUB/SUB Benchmark

Fan-out throughput: one PUB, N SUB peers each receiving all messages.

OMQ 0.14.0 · Ruby 4.0.2 (+YJIT) · Linux 6.12

## 1 peer

|   Size |             inproc |                ipc |                tcp |              curve |             blake3 |
|    ---:|                ---:|                ---:|                ---:|                ---:|                ---:|
|   64 B | 13.8 MB/s    215k/s | 12.0 MB/s    187k/s | 13.0 MB/s    203k/s |  5.2 MB/s     81k/s |  7.6 MB/s    119k/s |
|  256 B | 72.1 MB/s    282k/s | 39.4 MB/s    154k/s | 48.4 MB/s    189k/s | 18.6 MB/s     73k/s | 24.4 MB/s     95k/s |
|   1 KB | 482.1 MB/s    471k/s | 102.2 MB/s    100k/s | 156.5 MB/s    153k/s | 55.1 MB/s     54k/s | 68.8 MB/s     67k/s |
|   4 KB |  2.1 GB/s    501k/s | 227.2 MB/s     55k/s | 340.3 MB/s     83k/s | 121.0 MB/s     30k/s | 152.5 MB/s     37k/s |
|  64 KB | 28.9 GB/s    440k/s | 627.6 MB/s     10k/s | 746.1 MB/s     11k/s | 254.0 MB/s      4k/s | 328.3 MB/s      5k/s |

## 3 peers

|   Size |             inproc |                ipc |                tcp |              curve |             blake3 |
|    ---:|                ---:|                ---:|                ---:|                ---:|                ---:|
|   64 B | 12.5 MB/s    196k/s |  4.7 MB/s     73k/s |  4.5 MB/s     71k/s |  1.6 MB/s     24k/s |  2.5 MB/s     39k/s |
|  256 B | 42.1 MB/s    165k/s | 14.3 MB/s     56k/s | 16.4 MB/s     64k/s |  5.5 MB/s     21k/s |  8.9 MB/s     35k/s |
|   1 KB | 205.3 MB/s    200k/s | 47.4 MB/s     46k/s | 45.2 MB/s     44k/s | 17.0 MB/s     17k/s | 23.9 MB/s     23k/s |
|   4 KB | 847.5 MB/s    207k/s | 109.3 MB/s     27k/s | 112.6 MB/s     27k/s | 43.3 MB/s     11k/s | 49.5 MB/s     12k/s |
|  64 KB | 11.5 GB/s    176k/s | 249.1 MB/s      4k/s | 277.3 MB/s      4k/s | 79.0 MB/s      1k/s | 99.1 MB/s      2k/s |
