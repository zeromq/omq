# ZMTP over TLS

| Field       | Value                                          |
|-------------|------------------------------------------------|
| Status      | Raw                                            |
| Editor      | Patrik Wenger <paddor@gmail.com>               |
| References  | [23/ZMTP](https://rfc.zeromq.org/spec/23/), [37/ZMTP](https://rfc.zeromq.org/spec/37/), [SP-TLS](https://nanomsg.org/rfcs/sp-tls-v1.html) |

This specification defines a mapping of ZMTP 3.1 over TLS-secured TCP
connections, using the URI scheme `tls+tcp://`.

## License

Copyright (c) 2026 Patrik Wenger.

This Specification is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 3 of the License, or (at your option) any
later version.

## Language

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD",
"SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be
interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

## Goals

ZMTP assumes a reliable, ordered byte stream but does not mandate a specific
transport. In practice, ZMTP runs over bare TCP, leaving transport-level
encryption to VPNs or application wrappers.

Several independent implementations of "TLS for ZeroMQ" exist, but without a
specification they diverge on URI scheme, version requirements, and how TLS
interacts with ZMTP's own security mechanisms. This specification pins down
those choices so implementations can interoperate.

### Why TLS alongside CURVE?

CURVE (25/ZMTP-CURVE) provides message-level encryption and authentication
within ZMTP. TLS provides transport-level encryption with X.509 PKI. They
solve different problems:

* **TLS integrates with existing infrastructure** — certificate authorities,
  OCSP, CRLs, mTLS policies — that organizations already operate.
* **TLS enables PLAIN.** RFC 24/ZMTP-PLAIN transmits credentials in cleartext.
  Over bare TCP this is unusable in production. Over TLS it becomes safe,
  analogous to HTTP Basic Auth over HTTPS.
* **TLS 1.3 is competitive on performance.** Its 1-RTT handshake matches
  CURVE's. The multi-roundtrip overhead of TLS 1.2 no longer applies.

Neither replaces the other. They compose (see *Interoperability* below).

## Transport Layering

```
ZMTP 3.1        greeting, mechanism handshake, message framing
TLS 1.3         encryption, authentication, integrity
TCP              reliable ordered byte stream
```

TLS is transparent to ZMTP. The greeting, mechanism handshake, commands, and
message frames are carried as TLS application data without modification.

## URI Scheme

Endpoints MUST use the scheme `tls+tcp://`:

```
tls+tcp://host:port
```

* **host** — DNS hostname, IPv4 address, or bracketed IPv6 address (`[::1]`).
* **port** — TCP port number. `0` selects an ephemeral port (bind only).
* The wildcard `*` binds to all interfaces (equivalent to `0.0.0.0`).

The scheme is `tls+tcp` (not `tls`, `tcps`, `zmtps`, or `ssl`) to make the
transport stack explicit and to align with
[SP-TLS](https://nanomsg.org/rfcs/sp-tls-v1.html).

## TLS Version

Implementations MUST use TLS 1.3 or higher. TLS 1.2 and older MUST NOT be
accepted, even for backwards compatibility.

Rationale: TLS 1.3 removes renegotiation, compression, and weak cipher suites
by design. Allowing older versions reintroduces downgrade attacks and protocol
complexity that TLS 1.3 was created to eliminate. The 1-RTT handshake removes
the latency argument against TLS.

## TLS Context Scope

The TLS context (certificate, private key, CA trust store, protocol
parameters) is configured **per socket**, not per endpoint. All connections
made or accepted by a socket share the same TLS context.

Rationale: ZMTP sockets may bind or connect to multiple endpoints. Per-endpoint
contexts would complicate reconnection (the context must survive across
reconnect cycles) and break the symmetry with ZMTP's `mechanism` option, which
is also per-socket. Applications needing different certificates for different
endpoints should use separate sockets.

The TLS context MUST be treated as immutable once the first `bind` or `connect`
is performed. Implementations SHOULD enforce this (e.g. by freezing or copying
the context).

## Connection Lifecycle

### Connecting Peer

1. Establish a TCP connection to the target host and port.
2. Create a TLS client session from the socket's TLS context.
3. Set the SNI hostname to the host from the endpoint URI.
4. Perform the TLS handshake.
5. On success, proceed with the ZMTP greeting over the encrypted stream.
6. On failure, close the TCP connection and retry with the socket's normal
   reconnection strategy.

### Accepting Peer

1. Accept an incoming TCP connection.
2. Create a TLS server session from the listener's TLS context.
3. Perform the TLS handshake.
4. On success, proceed with the ZMTP greeting over the encrypted stream.
5. On failure, close the connection. The accept loop MUST continue serving
   new connections — a single bad handshake MUST NOT take down the listener.

### Reconnection

A reconnecting peer MUST establish a new TCP connection and perform a fresh TLS
handshake. TLS session state from a prior connection MUST NOT be carried over.

Rationale: ZeroMQ reconnection can happen after long delays or server restarts.
Assuming session validity across reconnects risks using stale or revoked
credentials. The cost of a fresh TLS 1.3 handshake (1 RTT) is negligible
compared to the security risk.

## Server Name Indication

Connecting peers SHOULD set the TLS SNI extension to the hostname from the
endpoint URI. This allows accepting peers to select the correct certificate
when serving multiple hostnames on a shared port.

When the endpoint host is an IP address, implementations SHOULD still set SNI
to that address (per [RFC 6066 Section 3](https://www.rfc-editor.org/rfc/rfc6066#section-3),
some servers use IP-based SNI).

## Client Authentication

Mutual TLS (mTLS) is OPTIONAL. Whether the accepting peer requests a client
certificate is controlled by the TLS context configuration, not by this
specification.

## Interoperability with ZMTP Mechanisms

TLS and ZMTP security mechanisms are **independent layers**:

| Stack                 | Transport      | ZMTP Auth         | Typical Use                        |
|-----------------------|----------------|-------------------|------------------------------------|
| `tls+tcp://` + NULL   | TLS encryption | none              | Encrypted transport, cert-only auth |
| `tls+tcp://` + PLAIN  | TLS encryption | username/password | Credentials safe over TLS          |
| `tls+tcp://` + CURVE  | TLS encryption | CurveZMQ keys    | Defense in depth                   |
| `tcp://` + CURVE      | plaintext TCP  | CurveZMQ keys    | End-to-end encryption without PKI  |
| `tcp://` + NULL       | plaintext TCP  | none              | Development / trusted network only |

An implementation MUST NOT treat TLS as a ZMTP mechanism. TLS does not appear
in the ZMTP greeting's mechanism field. The mechanism field carries NULL, PLAIN,
CURVE, or another ZMTP-level mechanism as usual.

## Security Considerations

* **No downgrade.** An endpoint configured as `tls+tcp://` MUST NOT fall back
  to unencrypted `tcp://` during reconnection or misconfiguration. The URI
  scheme is the source of truth.

* **Multi-hop is not end-to-end.** TLS secures individual connections, not
  message paths. In broker topologies (e.g. ROUTER intermediaries), each hop
  is a separate TLS session. The broker sees plaintext ZMTP frames. For
  end-to-end confidentiality across intermediaries, use CURVE or
  application-level encryption.

* **Greeting is encrypted.** The ZMTP greeting (including the mechanism name)
  is TLS application data. A passive network observer cannot determine the
  ZMTP socket type or security mechanism in use.

* **Certificate validation is mandatory.** Implementations MUST validate peer
  certificates according to the TLS context. Disabling validation (e.g.
  `VERIFY_NONE` on the client) defeats the purpose of TLS and MUST NOT be
  the default.
