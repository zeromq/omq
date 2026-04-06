# REQ/REP Benchmark

Request-reply round-trip latency: one REP echoing back, one REQ sending.

OMQ 0.14.0 · Ruby 4.0.2 (+YJIT) · Linux 6.12

## 1 peer

|   Size |             inproc |                ipc |                tcp |              curve |             blake3 |
|    ---:|                ---:|                ---:|                ---:|                ---:|                ---:|
|   64 B |  3.9 MB/s     61k/s |  1.0 MB/s     16k/s |  0.8 MB/s     13k/s |  0.5 MB/s      8k/s |  0.7 MB/s     10k/s |
|  256 B | 16.4 MB/s     64k/s |  3.6 MB/s     14k/s |  3.2 MB/s     13k/s |  2.0 MB/s      8k/s |  2.2 MB/s      9k/s |
|   1 KB | 66.9 MB/s     65k/s | 14.2 MB/s     14k/s | 12.2 MB/s     12k/s |  7.5 MB/s      7k/s |  8.7 MB/s      9k/s |
|   4 KB | 265.3 MB/s     65k/s | 47.0 MB/s     11k/s | 47.0 MB/s     11k/s | 26.9 MB/s      7k/s | 28.5 MB/s      7k/s |
|  64 KB |  4.1 GB/s     63k/s | 295.2 MB/s      5k/s | 363.4 MB/s      6k/s | 118.4 MB/s      2k/s | 142.9 MB/s      2k/s |

## 3 peers

|   Size |             inproc |                ipc |                tcp |              curve |             blake3 |
|    ---:|                ---:|                ---:|                ---:|                ---:|                ---:|
|   64 B |  4.2 MB/s     65k/s |  1.0 MB/s     15k/s |  0.8 MB/s     13k/s |  0.5 MB/s      8k/s |  0.6 MB/s     10k/s |
|  256 B | 16.3 MB/s     64k/s |  3.7 MB/s     14k/s |  3.4 MB/s     13k/s |  2.0 MB/s      8k/s |  2.2 MB/s      9k/s |
|   1 KB | 66.3 MB/s     65k/s | 14.4 MB/s     14k/s | 12.7 MB/s     12k/s |  7.7 MB/s      7k/s |  8.8 MB/s      9k/s |
|   4 KB | 259.7 MB/s     63k/s | 53.4 MB/s     13k/s | 49.8 MB/s     12k/s | 26.2 MB/s      6k/s | 30.3 MB/s      7k/s |
|  64 KB |  4.1 GB/s     62k/s | 383.6 MB/s      6k/s | 371.7 MB/s      6k/s | 118.7 MB/s      2k/s | 148.3 MB/s      2k/s |
