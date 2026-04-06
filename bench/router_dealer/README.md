# ROUTER/DEALER Benchmark

Asynchronous pipeline: one ROUTER, N DEALER peers.

OMQ 0.14.0 · Ruby 4.0.2 (+YJIT) · Linux 6.12

## 1 peer

|   Size |             inproc |                ipc |                tcp |              curve |             blake3 |
|    ---:|                ---:|                ---:|                ---:|                ---:|                ---:|
|   64 B | 18.3 MB/s    286k/s | 12.0 MB/s    187k/s | 12.4 MB/s    194k/s |  4.9 MB/s     76k/s |  6.7 MB/s    104k/s |
|  256 B | 92.8 MB/s    363k/s | 33.7 MB/s    132k/s | 46.1 MB/s    180k/s | 17.0 MB/s     66k/s | 21.7 MB/s     85k/s |
|   1 KB | 497.0 MB/s    485k/s | 100.2 MB/s     98k/s | 161.2 MB/s    157k/s | 51.9 MB/s     51k/s | 70.9 MB/s     69k/s |
|   4 KB |  2.4 GB/s    584k/s | 255.8 MB/s     62k/s | 412.2 MB/s    101k/s | 123.9 MB/s     30k/s | 160.2 MB/s     39k/s |
|  64 KB | 31.0 GB/s    472k/s | 640.2 MB/s     10k/s | 864.8 MB/s     13k/s | 251.0 MB/s      4k/s | 307.5 MB/s      5k/s |

## 3 peers

|   Size |             inproc |                ipc |                tcp |              curve |             blake3 |
|    ---:|                ---:|                ---:|                ---:|                ---:|                ---:|
|   64 B | 24.4 MB/s    382k/s |  9.7 MB/s    151k/s | 10.6 MB/s    165k/s |  4.1 MB/s     64k/s |  6.8 MB/s    106k/s |
|  256 B | 101.7 MB/s    397k/s | 24.7 MB/s     97k/s | 38.2 MB/s    149k/s | 12.7 MB/s     50k/s | 21.1 MB/s     82k/s |
|   1 KB | 459.8 MB/s    449k/s | 117.2 MB/s    114k/s | 141.4 MB/s    138k/s | 46.9 MB/s     46k/s | 69.4 MB/s     68k/s |
|   4 KB |  1.8 GB/s    429k/s | 363.0 MB/s     89k/s | 351.1 MB/s     86k/s | 120.8 MB/s     29k/s | 138.5 MB/s     34k/s |
|  64 KB | 42.5 GB/s    648k/s | 779.3 MB/s     12k/s | 834.8 MB/s     13k/s | 236.6 MB/s      4k/s | 290.5 MB/s      4k/s |
