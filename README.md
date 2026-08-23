# PERFDIAG.R4X

`PERFDIAG.R4X` is an independent R4OS diagnostic program implemented in Zig.

## Package

- Version: `0.3.2`
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

`/BASELINE` captures a summary before any optional workload. `/CONFORMANCE`
runs the state-changing contract probes and does not claim a performance
threshold. `/BENCHMARK /BLIT` runs only the repeated display workload, while
`/BENCHMARK /CLOCK` measures 10,000 high-resolution monotonic-clock queries
per sample. Every successful run ends with a delimited, versioned NDJSON v2
result block containing clock source and quality, the event backend and exact
rate, run metadata, raw samples, distributions, checks, missing measurement
flags, and measured summary-query overhead.

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
