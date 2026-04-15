#!/usr/bin/env python3
"""
PUSH/PULL + REQ/REP throughput on CPython + pyzmq.
Counterparts: omq.rb, ffi_rzmq.rb, cztop.rb, jeromq.rb.

Usage: python3 bench/scenarios/ffi_rzmq_vs_omq/pyzmq.py
"""

import os
import sys
import threading
import time

import zmq

SIZES  = (128, 1024)
N      = 1_000_000
WARMUP = 10_000

def bench_push_pull(size):
    payload = b"x" * size

    ctx = zmq.Context()
    pull = ctx.socket(zmq.PULL)
    pull.bind("tcp://127.0.0.1:0")
    ep = pull.getsockopt(zmq.LAST_ENDPOINT).decode().rstrip("\x00")

    push = ctx.socket(zmq.PUSH)
    push.connect(ep)

    def producer():
        for _ in range(WARMUP + N):
            push.send(payload)

    t = threading.Thread(target=producer)
    t.start()

    for _ in range(WARMUP):
        pull.recv()

    t0 = time.monotonic()
    for _ in range(N):
        pull.recv()
    elapsed = time.monotonic() - t0

    t.join()
    push.close(linger=0)
    pull.close(linger=0)

    rate = N / elapsed
    mbps = rate * size / 1e6
    print(f"  PUSH/PULL {size:5d}B  {rate:10.1f} msg/s  {mbps:9.1f} MB/s  ({elapsed:.2f}s, n={N})")


def bench_req_rep(size):
    payload = b"x" * size
    rounds  = 100_000

    ctx = zmq.Context()
    rep = ctx.socket(zmq.REP)
    rep.bind("tcp://127.0.0.1:0")
    ep = rep.getsockopt(zmq.LAST_ENDPOINT).decode().rstrip("\x00")

    req = ctx.socket(zmq.REQ)
    req.connect(ep)

    stop = threading.Event()

    def server():
        while not stop.is_set():
            try:
                msg = rep.recv(flags=zmq.NOBLOCK)
            except zmq.Again:
                continue
            rep.send(msg)

    # Blocking server is simpler and close() unblocks recv via ETERM.
    def server_blocking():
        try:
            while True:
                msg = rep.recv()
                rep.send(msg)
        except zmq.ZMQError:
            pass

    t = threading.Thread(target=server_blocking, daemon=True)
    t.start()

    for _ in range(1000):
        req.send(payload)
        req.recv()

    t0 = time.monotonic()
    for _ in range(rounds):
        req.send(payload)
        req.recv()
    elapsed = time.monotonic() - t0

    req.close(linger=0)
    rep.close(linger=0)

    rate   = rounds / elapsed
    lat_us = elapsed / rounds * 1e6
    print(f"  REQ/REP   {size:5d}B  {rate:10.1f} rtt/s  {lat_us:8.1f} µs/rtt  ({elapsed:.2f}s, n={rounds})")


if __name__ == "__main__" and len(sys.argv) == 1:
    # libzmq 4.3.5 asserts during teardown between successive REQ/REP runs
    # even with fresh contexts (likely the daemon recv thread racing with
    # ctx destruction). Workaround: run each size in a fresh subprocess.
    import subprocess
    print(f"pyzmq {zmq.__version__} → libzmq {zmq.zmq_version()} | CPython {sys.version.split()[0]}")
    print("--- CPython + pyzmq (Cython → libzmq, tcp loopback) ---")
    for pat in ("push_pull", "req_rep"):
        for s in SIZES:
            subprocess.run([sys.executable, "-u", __file__, pat, str(s)], check=True)
    sys.exit(0)

pat, size = sys.argv[1], int(sys.argv[2])
if pat == "push_pull":
    bench_push_pull(size)
else:
    bench_req_rep(size)
os._exit(0)
