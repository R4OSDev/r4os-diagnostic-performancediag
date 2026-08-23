const std = @import("std");

pub const result_schema = "r4os.perfdiag.ndjson";
pub const result_schema_version: u32 = 5;
pub const default_repetitions: u8 = 5;
pub const min_repetitions: u8 = 3;
pub const max_repetitions: u8 = 20;
pub const blit_min_duration_ms: u64 = 250;
pub const clock_calls_per_sample: u64 = 10_000;
pub const service_registry_iterations_per_sample: u64 = 100;
pub const service_registry_phase_count: usize = 3;
pub const kernel_ipc_iterations_per_sample: u64 = 64;
pub const kernel_ipc_status_requests_per_iteration: u64 = 4;
pub const kernel_ipc_small_error_requests_per_iteration: u64 = 4;
pub const kernel_ipc_small_requests_per_iteration: u64 = kernel_ipc_status_requests_per_iteration + kernel_ipc_small_error_requests_per_iteration;
pub const kernel_ipc_max_requests_per_iteration: u64 = 1;
pub const kernel_ipc_requests_per_iteration: u64 = kernel_ipc_small_requests_per_iteration + kernel_ipc_max_requests_per_iteration;
pub const driver_work_owner_capacity: usize = 16;
pub const driver_work_audio_writes_per_sample: u64 = 8;
pub const driver_work_audio_bytes_per_write: usize = 4096;
pub const driver_work_audio_write_spacing_ms: u64 = 25;
pub const bytes_per_kb: u64 = 1024;
pub const kb_per_mb: u64 = 1024;
pub const bytes_per_mb: u64 = bytes_per_kb * kb_per_mb;

pub const Mode = enum {
    baseline,
    conformance,
    benchmark,

    pub fn name(self: Mode) []const u8 {
        return switch (self) {
            .baseline => "baseline",
            .conformance => "conformance",
            .benchmark => "benchmark",
        };
    }
};

pub const CacheState = enum {
    unspecified,
    cold,
    warm,

    pub fn name(self: CacheState) []const u8 {
        return switch (self) {
            .unspecified => "unspecified",
            .cold => "cold",
            .warm => "warm",
        };
    }
};

pub const BenchmarkKind = enum {
    blit,
    clock,
    service_registry,
    kernel_ipc,
    driver_work,

    pub fn name(self: BenchmarkKind) []const u8 {
        return switch (self) {
            .blit => "blit",
            .clock => "clock",
            .service_registry => "service-registry",
            .kernel_ipc => "kernel-ipc",
            .driver_work => "driver-work",
        };
    }
};

pub const ServiceRegistryPhase = enum(u8) {
    service_info,
    service_detail,
    servman_diag,

    pub fn name(self: ServiceRegistryPhase) []const u8 {
        return switch (self) {
            .service_info => "service-info",
            .service_detail => "service-detail",
            .servman_diag => "servman-diag",
        };
    }
};

pub const ParseError = enum {
    none,
    conflicting_mode,
    conflicting_benchmark,
    conflicting_cache_state,
    invalid_repetitions,
    unknown_argument,

    pub fn name(self: ParseError) []const u8 {
        return switch (self) {
            .none => "none",
            .conflicting_mode => "conflicting-mode",
            .conflicting_benchmark => "conflicting-benchmark",
            .conflicting_cache_state => "conflicting-cache-state",
            .invalid_repetitions => "invalid-repetitions",
            .unknown_argument => "unknown-argument",
        };
    }
};

pub const Config = struct {
    mode: Mode = .baseline,
    mode_explicit: bool = false,
    cache_state: CacheState = .unspecified,
    benchmark_kind: BenchmarkKind = .blit,
    benchmark_explicit: bool = false,
    repetitions: u8 = default_repetitions,
    show_help: bool = false,
    parse_error: ParseError = .none,

    pub fn valid(self: Config) bool {
        return self.parse_error == .none;
    }
};

pub const Distribution = struct {
    count: u8 = 0,
    minimum: u64 = 0,
    p50: u64 = 0,
    p95: u64 = 0,
    p99: u64 = 0,
    maximum: u64 = 0,
    mean: u64 = 0,
};

pub fn parseArgs(args: []const u8) Config {
    var config = Config{};
    var tokens = std.mem.tokenizeAny(u8, args, " \t\r\n");
    while (tokens.next()) |token| {
        if (equalsIgnoreCase(token, "/?") or equalsIgnoreCase(token, "/HELP")) {
            config.show_help = true;
        } else if (equalsIgnoreCase(token, "/BASELINE")) {
            selectMode(&config, .baseline);
        } else if (equalsIgnoreCase(token, "/CONFORMANCE")) {
            selectMode(&config, .conformance);
        } else if (equalsIgnoreCase(token, "/BENCHMARK")) {
            selectMode(&config, .benchmark);
        } else if (equalsIgnoreCase(token, "/BLIT")) {
            selectMode(&config, .benchmark);
            selectBenchmark(&config, .blit);
        } else if (equalsIgnoreCase(token, "/CLOCK")) {
            selectMode(&config, .benchmark);
            selectBenchmark(&config, .clock);
        } else if (equalsIgnoreCase(token, "/SERVICE-REGISTRY")) {
            selectMode(&config, .benchmark);
            selectBenchmark(&config, .service_registry);
        } else if (equalsIgnoreCase(token, "/KERNEL-IPC")) {
            selectMode(&config, .benchmark);
            selectBenchmark(&config, .kernel_ipc);
        } else if (equalsIgnoreCase(token, "/DRIVER-WORK")) {
            selectMode(&config, .benchmark);
            selectBenchmark(&config, .driver_work);
        } else if (equalsIgnoreCase(token, "/COLD")) {
            selectCacheState(&config, .cold);
        } else if (equalsIgnoreCase(token, "/WARM")) {
            selectCacheState(&config, .warm);
        } else if (valueAfterPrefix(token, "/REPEAT:") orelse valueAfterPrefix(token, "/REPEAT=")) |value| {
            const parsed = parseDecimalU8(value) orelse {
                setParseError(&config, .invalid_repetitions);
                continue;
            };
            if (parsed < min_repetitions or parsed > max_repetitions) {
                setParseError(&config, .invalid_repetitions);
            } else {
                config.repetitions = parsed;
            }
        } else {
            setParseError(&config, .unknown_argument);
        }
    }
    return config;
}

pub fn ticksForMilliseconds(hz: u32, milliseconds: u64) u64 {
    if (hz == 0 or milliseconds == 0) return 0;
    const numerator = @as(u128, hz) * @as(u128, milliseconds) + 999;
    return @intCast(numerator / 1000);
}

pub fn throughputKbPerSecond(bytes: u64, elapsed_ticks: u64, hz: u32) u64 {
    if (bytes == 0 or elapsed_ticks == 0 or hz == 0) return 0;
    const numerator = @as(u128, bytes) * @as(u128, hz);
    const denominator = @as(u128, elapsed_ticks) * bytes_per_kb;
    return @intCast(numerator / denominator);
}

pub fn throughputKbPerSecondNs(bytes: u64, elapsed_ns: u64) u64 {
    if (bytes == 0 or elapsed_ns == 0) return 0;
    const numerator = @as(u128, bytes) * 1_000_000_000;
    const denominator = @as(u128, elapsed_ns) * bytes_per_kb;
    return @intCast(numerator / denominator);
}

pub fn summarize(values: []const u64) Distribution {
    if (values.len == 0) return .{};
    std.debug.assert(values.len <= max_repetitions);

    var sorted: [max_repetitions]u64 = .{0} ** max_repetitions;
    var sum: u128 = 0;
    for (values, 0..) |value, index| {
        sorted[index] = value;
        sum += value;
    }
    insertionSort(sorted[0..values.len]);

    return .{
        .count = @intCast(values.len),
        .minimum = sorted[0],
        .p50 = nearestRank(sorted[0..values.len], 50),
        .p95 = nearestRank(sorted[0..values.len], 95),
        .p99 = nearestRank(sorted[0..values.len], 99),
        .maximum = sorted[values.len - 1],
        .mean = @intCast(sum / values.len),
    };
}

fn selectMode(config: *Config, next: Mode) void {
    if (config.mode_explicit and config.mode != next) {
        setParseError(config, .conflicting_mode);
        return;
    }
    config.mode = next;
    config.mode_explicit = true;
}

fn selectCacheState(config: *Config, next: CacheState) void {
    if (config.cache_state != .unspecified and config.cache_state != next) {
        setParseError(config, .conflicting_cache_state);
        return;
    }
    config.cache_state = next;
}

fn selectBenchmark(config: *Config, next: BenchmarkKind) void {
    if (config.benchmark_explicit and config.benchmark_kind != next) {
        setParseError(config, .conflicting_benchmark);
        return;
    }
    config.benchmark_kind = next;
    config.benchmark_explicit = true;
}

fn setParseError(config: *Config, value: ParseError) void {
    if (config.parse_error == .none) config.parse_error = value;
}

fn equalsIgnoreCase(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

fn valueAfterPrefix(value: []const u8, prefix: []const u8) ?[]const u8 {
    if (value.len < prefix.len) return null;
    if (!equalsIgnoreCase(value[0..prefix.len], prefix)) return null;
    return value[prefix.len..];
}

fn parseDecimalU8(value: []const u8) ?u8 {
    if (value.len == 0) return null;
    var result: u16 = 0;
    for (value) |ch| {
        if (ch < '0' or ch > '9') return null;
        result = result * 10 + (ch - '0');
        if (result > 255) return null;
    }
    return @intCast(result);
}

fn insertionSort(values: []u64) void {
    var index: usize = 1;
    while (index < values.len) : (index += 1) {
        const value = values[index];
        var position = index;
        while (position > 0 and values[position - 1] > value) : (position -= 1) {
            values[position] = values[position - 1];
        }
        values[position] = value;
    }
}

fn nearestRank(sorted: []const u64, percentile: u8) u64 {
    const rank = (@as(usize, percentile) * sorted.len + 99) / 100;
    return sorted[@max(rank, 1) - 1];
}

test "arguments default to a passive baseline" {
    const config = parseArgs("");
    try std.testing.expect(config.valid());
    try std.testing.expectEqual(Mode.baseline, config.mode);
    try std.testing.expect(!config.mode_explicit);
    try std.testing.expectEqual(default_repetitions, config.repetitions);
}

test "arguments select a labeled repeated blit benchmark" {
    const config = parseArgs("/benchmark /blit /repeat:7 /warm");
    try std.testing.expect(config.valid());
    try std.testing.expectEqual(Mode.benchmark, config.mode);
    try std.testing.expect(config.mode_explicit);
    try std.testing.expectEqual(BenchmarkKind.blit, config.benchmark_kind);
    try std.testing.expectEqual(CacheState.warm, config.cache_state);
    try std.testing.expectEqual(@as(u8, 7), config.repetitions);
}

test "arguments select the monotonic clock benchmark" {
    const config = parseArgs("/benchmark /clock /repeat=3 /warm");
    try std.testing.expect(config.valid());
    try std.testing.expectEqual(Mode.benchmark, config.mode);
    try std.testing.expectEqual(BenchmarkKind.clock, config.benchmark_kind);
    try std.testing.expectEqual(@as(u8, 3), config.repetitions);
}

test "arguments select the service registry benchmark" {
    const config = parseArgs("/benchmark /service-registry /repeat=5 /warm");
    try std.testing.expect(config.valid());
    try std.testing.expectEqual(Mode.benchmark, config.mode);
    try std.testing.expectEqual(BenchmarkKind.service_registry, config.benchmark_kind);
    try std.testing.expectEqual(CacheState.warm, config.cache_state);
    try std.testing.expectEqual(@as(u8, 5), config.repetitions);
}

test "arguments select the kernel IPC benchmark" {
    const config = parseArgs("/benchmark /kernel-ipc /repeat=5 /warm");
    try std.testing.expect(config.valid());
    try std.testing.expectEqual(Mode.benchmark, config.mode);
    try std.testing.expectEqual(BenchmarkKind.kernel_ipc, config.benchmark_kind);
    try std.testing.expectEqual(CacheState.warm, config.cache_state);
    try std.testing.expectEqual(@as(u8, 5), config.repetitions);
}

test "arguments select the driver work benchmark" {
    const config = parseArgs("/benchmark /driver-work /repeat=5 /warm");
    try std.testing.expect(config.valid());
    try std.testing.expectEqual(Mode.benchmark, config.mode);
    try std.testing.expectEqual(BenchmarkKind.driver_work, config.benchmark_kind);
    try std.testing.expectEqual(CacheState.warm, config.cache_state);
    try std.testing.expectEqual(@as(u8, 5), config.repetitions);
}

test "arguments reject conflicting modes states and repetition bounds" {
    try std.testing.expectEqual(ParseError.conflicting_mode, parseArgs("/baseline /conformance").parse_error);
    try std.testing.expectEqual(ParseError.conflicting_benchmark, parseArgs("/blit /clock").parse_error);
    try std.testing.expectEqual(ParseError.conflicting_cache_state, parseArgs("/cold /warm").parse_error);
    try std.testing.expectEqual(ParseError.invalid_repetitions, parseArgs("/benchmark /repeat:2").parse_error);
    try std.testing.expectEqual(ParseError.invalid_repetitions, parseArgs("/benchmark /repeat:no").parse_error);
    try std.testing.expectEqual(ParseError.unknown_argument, parseArgs("/mystery").parse_error);
}

test "duration derives from the captured timer frequency" {
    try std.testing.expectEqual(@as(u64, 25), ticksForMilliseconds(100, 250));
    try std.testing.expectEqual(@as(u64, 250), ticksForMilliseconds(1000, 250));
    try std.testing.expectEqual(@as(u64, 0), ticksForMilliseconds(0, 250));
}

test "throughput uses 1024-byte KB and the captured frequency" {
    const ten_mb = 10 * bytes_per_mb;
    try std.testing.expectEqual(@as(u64, 10 * kb_per_mb), throughputKbPerSecond(ten_mb, 100, 100));
    try std.testing.expectEqual(@as(u64, 10 * kb_per_mb), throughputKbPerSecond(ten_mb, 1000, 1000));
    try std.testing.expectEqual(@as(u64, 0), throughputKbPerSecond(ten_mb, 0, 1000));
}

test "nanosecond throughput preserves the 1024-byte KB convention" {
    const ten_mb = 10 * bytes_per_mb;
    try std.testing.expectEqual(@as(u64, 10 * kb_per_mb), throughputKbPerSecondNs(ten_mb, 1_000_000_000));
    try std.testing.expectEqual(@as(u64, 0), throughputKbPerSecondNs(ten_mb, 0));
}

test "distribution preserves small differences and tail values" {
    const values = [_]u64{ 1000, 1001, 999, 1002, 998 };
    const result = summarize(values[0..]);
    try std.testing.expectEqual(@as(u8, 5), result.count);
    try std.testing.expectEqual(@as(u64, 998), result.minimum);
    try std.testing.expectEqual(@as(u64, 1000), result.p50);
    try std.testing.expectEqual(@as(u64, 1002), result.p95);
    try std.testing.expectEqual(@as(u64, 1002), result.p99);
    try std.testing.expectEqual(@as(u64, 1002), result.maximum);
    try std.testing.expectEqual(@as(u64, 1000), result.mean);
}
