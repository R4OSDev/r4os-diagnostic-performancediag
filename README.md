# PERFDIAG.R4X

`PERFDIAG.R4X` is an independent R4OS diagnostic program implemented in Zig.

## Package

- Version: `0.3.12`
- Image target: `/R4OS/SOFTWARE/TERMINAL/DIAG/PERFDIAG.R4X`
- Image scope: `test`
- Canonical project manifest: `module.R4MF`

The manifest is the single source of truth for the artifact, imports, image
target, and package metadata.

## Build

On Windows:

    Build.bat

On Linux or macOS:

    ./Build.sh

## Runtime modes

Running `PERFDIAG` without arguments is intentionally passive. The supported
modes are:

    PERFDIAG /BASELINE
    PERFDIAG /CONFORMANCE
    PERFDIAG /BENCHMARK /BLIT /REPEAT:5 /COLD
    PERFDIAG /BENCHMARK /BLIT /REPEAT:5 /WARM
    PERFDIAG /BENCHMARK /CLOCK /REPEAT:5 /WARM
    PERFDIAG /BENCHMARK /SERVICE-REGISTRY /REPEAT:5 /WARM
    PERFDIAG /BENCHMARK /KERNEL-IPC /REPEAT:5 /WARM
    PERFDIAG /BENCHMARK /DRIVER-WORK /REPEAT:5 /WARM
    PERFDIAG /BENCHMARK /PCI-INVENTORY /REPEAT:5 /WARM
    PERFDIAG /BENCHMARK /MEMORY-METADATA /REPEAT:5 /WARM

`/BASELINE` captures a summary before any optional workload. `/CONFORMANCE`
runs the state-changing contract probes and does not claim a performance
threshold. `/BENCHMARK /BLIT` runs only the repeated display workload, while
`/BENCHMARK /CLOCK` measures 10,000 high-resolution monotonic-clock queries
per sample. `/BENCHMARK /SERVICE-REGISTRY` measures 100 complete enumerations
per sample in separate ServiceInfo, ServiceDetail, and ServiceManager-DIAG-
equivalent phases. It records API calls, refresh visits, program-instance
lookups, end markers, elapsed time, and the exact legacy quadratic work
reference. `/BENCHMARK /KERNEL-IPC` measures status and error requests on all
four network channels plus maximum-sized requests through the central kernel
channel worker. It records caller, queue, handler and end-to-end latency with
byte, queue and backpressure counters. The workload temporarily stops the
DHCPSVC, DNSSVC, UDPSVC, and TCPSVC userland proxies with bounded transitions,
remembers exactly which services it stopped, and restores those services in
reverse order on every exit path. Warm runs then require 250 ms of bounded
quiescence on those four channel slots; per-channel snapshots exclude unrelated
global IPC traffic. A sample containing fully accounted concurrent traffic on
a measured channel is discarded and retried at most twice. Real IPC errors,
failed isolation or restoration, a failed 10-second quiescence bound, and an
exhausted three-attempt bound still fail the run. Isolation, quiescence,
discard counts, and the accepted attempt number remain visible in the
human-readable and NDJSON v7 output.
`/BENCHMARK /DRIVER-WORK` measures a
fixed HDA workload against the active driver owner. `/BENCHMARK
/PCI-INVENTORY` performs 100 complete DeviceInventory summary-and-record
workloads per sample and proves with before/after counters that the cached
consumer path performs no PCI configuration or ECAM mapping work. Every
`/BENCHMARK /MEMORY-METADATA` measures eight-page reserve/commit, demand-fault,
Page-State, and multi-frame reclaim phases separately. It preserves physical
block, range, local span, and persistent reclaim-cursor step counters so tail
scans remain visible beside latency distributions. Every successful run ends
with a delimited, versioned NDJSON v7
result block containing clock source and quality, the event backend and exact
rate, run metadata, raw samples, distributions, checks, missing measurement
flags, measured summary-query overhead, and a storage-dispatch record. That
record preserves controller/worker parallelism, direct-versus-bounce deltas,
completion timeouts, and filesystem/block tail ticks outside the timed loop.

Conformance gates use stable ABI, capacity, error, and consistency invariants.
Legacy exact-state aggregates remain visible as observations, but are not
treated as contract failures when asynchronous subsystem state is valid.
Conformance also validates boot/loader nanosecond availability and the
documented IRQ dispatch/handler timing coverage. Unresolvable early spans are
reported explicitly rather than converted into apparently precise zeros.

The build starters resolve the current local R4OS dependency checkouts through
`Settings.R4S`. The URL and hash entries in `build.zig.zon` record the
last verified standalone dependency identities; workspace builds use the
mapped local checkouts.

## Documentation

Detailed German technical notes from the migration are preserved in
`DOCUMENTATION.de.txt`. Source-transfer provenance is recorded in
`PROVENANCE.txt`.

## License

Original R4OS material is licensed under Apache License 2.0. See `LICENSE`
and `NOTICE`. Any repository-specific external material is documented in
`THIRD_PARTY_NOTICES.md`.
