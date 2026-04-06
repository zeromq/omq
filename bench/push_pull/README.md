# PUSH/PULL Benchmark

Pipeline throughput: one PULL, N PUSH peers.

OMQ 0.14.0 · Ruby 4.0.2 (+YJIT) · Linux 6.12

## 1 peer

|   Size |             inproc |                ipc |                tcp |              curve |             blake3 |
|    ---:|                ---:|                ---:|                ---:|                ---:|                ---:|
|   64 B | 18.9 MB/s    295k/s | 12.1 MB/s    189k/s | 12.2 MB/s    191k/s |  5.0 MB/s     77k/s |  7.3 MB/s    115k/s |
|  256 B | 95.3 MB/s    372k/s | 43.6 MB/s    170k/s | 47.1 MB/s    184k/s | 17.6 MB/s     69k/s | 23.7 MB/s     93k/s |
|   1 KB | 573.5 MB/s    560k/s | 124.4 MB/s    121k/s | 160.3 MB/s    157k/s | 48.6 MB/s     47k/s | 75.8 MB/s     74k/s |
|   4 KB |  2.6 GB/s    623k/s | 267.4 MB/s     65k/s | 415.5 MB/s    101k/s | 134.4 MB/s     33k/s | 159.3 MB/s     39k/s |
|  64 KB | 39.3 GB/s    600k/s | 671.8 MB/s     10k/s | 915.8 MB/s     14k/s | 256.7 MB/s      4k/s | 315.5 MB/s      5k/s |

## 3 peers

|   Size |             inproc |                ipc |                tcp |              curve |             blake3 |
|    ---:|                ---:|                ---:|                ---:|                ---:|                ---:|
|   64 B | 27.1 MB/s    424k/s | 10.6 MB/s    165k/s | 10.6 MB/s    166k/s |  4.7 MB/s     73k/s |  7.0 MB/s    109k/s |
|  256 B | 76.5 MB/s    299k/s | 31.8 MB/s    124k/s | 40.7 MB/s    159k/s | 14.5 MB/s     57k/s | 20.4 MB/s     80k/s |
|   1 KB | 464.6 MB/s    454k/s | 125.8 MB/s    123k/s | 148.1 MB/s    145k/s | 51.5 MB/s     50k/s | 71.4 MB/s     70k/s |
|   4 KB |  1.9 GB/s    465k/s | 368.8 MB/s     90k/s | 366.5 MB/s     89k/s | 124.0 MB/s     30k/s | 148.9 MB/s     36k/s |
|  64 KB | 44.0 GB/s    672k/s | 821.5 MB/s     13k/s | 904.9 MB/s     14k/s | 242.1 MB/s      4k/s | 303.3 MB/s      5k/s |
