const r4os = @import("r4os");
const measurement = @import("measurement.zig");

const module_version = "0.3.19";

const backing_store_path = "C:\\TEMP\\R4PAGE.BIN";
const missing_backing_store_path = "C:\\TEMP\\R4MISS.SWP";
const memory_metadata_backing_store_path = "D:\\TEMP\\R4MEMIDX.BIN";
const backing_store_bytes: u64 = 64 * 1024;
const memory_metadata_backing_store_bytes: u64 = 256 * 1024;
const backing_store_slot_count: u64 = backing_store_bytes / 4096;
const backing_store_slot_reserve: u64 = 4;
const backing_store_slot_owner: u32 = 0x50455246;
const task_state_unused: u32 = 0;
const task_state_ready: u32 = 1;
const task_state_running: u32 = 2;
const task_state_blocked: u32 = 3;
const task_state_dead: u32 = 4;
const backing_store_gate_bytes: u64 = 8 * 4096;
const backing_store_lifecycle_vm_slots: u64 = 2;
const backing_store_lifecycle_region_bytes: u64 = 4 * 4096;
var preemption_burn_sink: u64 = 0;
var service_registry_benchmark_sink: u64 = 0;
var pci_inventory_benchmark_sink: u64 = 0;
var preemption_worker_stop: u32 = 0;
var avx_worker_results: [2]u32 = .{ 0, 0 };
// 0.56.12: Frame-Puffer fuer den Blit-Durchsatz-Benchmark (320x64 XRGB).
var blit_bench_frame: [320 * 64]u32 = .{0} ** (320 * 64);
var driver_work_bench_pcm: [measurement.driver_work_audio_bytes_per_write]u8 = .{0} ** measurement.driver_work_audio_bytes_per_write;
const max_check_results = 256;
const max_service_registry_samples = measurement.service_registry_phase_count * measurement.max_repetitions;
const service_registry_max_entries: u32 = 64;
const kernel_ipc_channels = [_]u32{
    r4os.abi.ipc_channel_net_dhcp,
    r4os.abi.ipc_channel_net_dns,
    r4os.abi.ipc_channel_net_tcp,
    r4os.abi.ipc_channel_net_udp,
};
const KernelIpcPerformanceSnapshots = [kernel_ipc_channels.len]r4os.abi.IpcPerformanceSummary;
const kernel_ipc_proxy_services = [_][:0]const u8{
    "DHCPSVC",
    "DNSSVC",
    "UDPSVC",
    "TCPSVC",
};

const CheckResult = struct {
    label: []const u8 = &.{},
    ok: bool = false,
};

const BlitSample = struct {
    iterations: u64 = 0,
    elapsed_ticks: u64 = 0,
    elapsed_ns: u64 = 0,
    bytes: u64 = 0,
    kb_per_second: u64 = 0,
};

const ClockSample = struct {
    calls: u64 = 0,
    elapsed_ns: u64 = 0,
    ns_per_call: u64 = 0,
    min_positive_delta_ns: u64 = 0,
    zero_deltas: u64 = 0,
    regressions: u64 = 0,
};

const ServiceRegistrySample = struct {
    phase: measurement.ServiceRegistryPhase = .service_info,
    repetition: u8 = 0,
    iterations: u64 = 0,
    services_per_enumeration: u64 = 0,
    entries: u64 = 0,
    api_calls: u64 = 0,
    api_end_markers: u64 = 0,
    api_errors: u64 = 0,
    elapsed_ns: u64 = 0,
    ns_per_enumeration: u64 = 0,
    index_queries: u64 = 0,
    refresh_requests: u64 = 0,
    refresh_visits: u64 = 0,
    instance_lookups: u64 = 0,
    counter_end_markers: u64 = 0,
    legacy_reference_refresh_visits: u64 = 0,
    checksum: u64 = 0,
};

const ServiceRegistryWork = struct {
    entries: u64 = 0,
    api_calls: u64 = 0,
    end_markers: u64 = 0,
    errors: u64 = 0,
    services_per_enumeration: u64 = 0,
    checksum: u64 = 0xcbf29ce484222325,
};

const KernelIpcSample = struct {
    repetition: u8 = 0,
    attempt: u8 = 0,
    iterations: u64 = 0,
    requests: u64 = 0,
    status_requests: u64 = 0,
    error_requests: u64 = 0,
    small_requests: u64 = 0,
    max_requests: u64 = 0,
    elapsed_ns: u64 = 0,
    caller_ns_per_request: u64 = 0,
    handler_queued: u64 = 0,
    handler_completed: u64 = 0,
    handler_failures: u64 = 0,
    handler_direct: u64 = 0,
    handler_waits: u64 = 0,
    handler_wait_timeouts: u64 = 0,
    handler_queue_ns: u64 = 0,
    handler_queue_ns_per_request: u64 = 0,
    handler_queue_max_before_ns: u64 = 0,
    handler_queue_max_ns: u64 = 0,
    handler_run_ns: u64 = 0,
    handler_run_ns_per_request: u64 = 0,
    handler_run_max_before_ns: u64 = 0,
    handler_run_max_ns: u64 = 0,
    handler_e2e_ns: u64 = 0,
    handler_e2e_ns_per_request: u64 = 0,
    handler_e2e_max_before_ns: u64 = 0,
    handler_e2e_max_ns: u64 = 0,
    request_bytes: u64 = 0,
    response_bytes: u64 = 0,
    payload_copy_bytes: u64 = 0,
    payload_clear_bytes: u64 = 0,
    queue_full: u64 = 0,
    queue_empty: u64 = 0,
    admission_waits: u64 = 0,
    admission_timeouts: u64 = 0,
    recv_buffer_small: u64 = 0,
    response_search_slots: u64 = 0,
    stale_drops: u64 = 0,
    lock_contentions: u64 = 0,
    irq_denied: u64 = 0,
    queue_used_after: u32 = 0,
};

const DriverWorkSample = struct {
    repetition: u8 = 0,
    owner: u32 = 0,
    audio_writes: u64 = 0,
    audio_bytes: u64 = 0,
    submitted: u64 = 0,
    submitted_actual_irq: u64 = 0,
    submitted_actual_task: u64 = 0,
    submitted_irq_class: u64 = 0,
    submitted_task_class: u64 = 0,
    started: u64 = 0,
    completed: u64 = 0,
    failed: u64 = 0,
    cancelled: u64 = 0,
    dropped: u64 = 0,
    full_rejections: u64 = 0,
    retained_full_rejections: u64 = 0,
    releases: u64 = 0,
    release_busy: u64 = 0,
    release_wakes: u64 = 0,
    publication_pending_releases: u64 = 0,
    waiter_blocked_releases: u64 = 0,
    claimed_releases: u64 = 0,
    invalid_handles: u64 = 0,
    stale_handles: u64 = 0,
    wait_timeouts: u64 = 0,
    wait_failed: u64 = 0,
    wake_publications: u64 = 0,
    wake_waiters: u64 = 0,
    wake_misses: u64 = 0,
    selection_irq: u64 = 0,
    selection_task: u64 = 0,
    selection_irq_preferred: u64 = 0,
    selection_task_fairness: u64 = 0,
    deadline_submitted: u64 = 0,
    deadline_started: u64 = 0,
    deadline_completed: u64 = 0,
    deadline_misses: u64 = 0,
    deadline_budget_overruns: u64 = 0,
    deadline_queue_rejections: u64 = 0,
    deadline_queue_total_ticks: u64 = 0,
    deadline_queue_max_ticks_after: u64 = 0,
    deadline_lateness_total_ticks: u64 = 0,
    deadline_lateness_max_ticks_after: u64 = 0,
    queue_total_ns: u64 = 0,
    queue_ns_per_started: u64 = 0,
    queue_max_before_ns: u64 = 0,
    queue_max_after_ns: u64 = 0,
    run_total_ns: u64 = 0,
    run_ns_per_completed: u64 = 0,
    run_max_before_ns: u64 = 0,
    run_max_after_ns: u64 = 0,
    e2e_total_ns: u64 = 0,
    e2e_ns_per_completed: u64 = 0,
    e2e_max_before_ns: u64 = 0,
    e2e_max_after_ns: u64 = 0,
    timing_unavailable: u64 = 0,
    completion_age_current_ns_after: u64 = 0,
    completion_age_max_ns_after: u64 = 0,
    scan_passes: u64 = 0,
    scan_slots: u64 = 0,
    critical_sections: u64 = 0,
    critical_from_irq: u64 = 0,
    critical_total_ns: u64 = 0,
    critical_max_before_ns: u64 = 0,
    critical_max_after_ns: u64 = 0,
    critical_timing_samples: u64 = 0,
    critical_timing_unavailable: u64 = 0,
    waiter_enrollments: u64 = 0,
    waiter_wake_returns: u64 = 0,
    long_callbacks: u64 = 0,
    cleanup_calls: u64 = 0,
    cleanup_quiesced: u64 = 0,
    cleanup_failed_context: u64 = 0,
    cleanup_queued_cancelled: u64 = 0,
    cleanup_waits: u64 = 0,
    cleanup_wait_timeouts: u64 = 0,
    cleanup_wait_failures: u64 = 0,
    cleanup_released: u64 = 0,
    cleanup_late_finishes: u64 = 0,
    cleanup_scan_passes: u64 = 0,
    cleanup_scan_slots: u64 = 0,
    free_slots_after: u32 = 0,
    used_slots_after: u32 = 0,
    queued_slots_after: u32 = 0,
    running_slots_after: u32 = 0,
    completed_slots_after: u32 = 0,
    cancelled_slots_after: u32 = 0,
    queue_high_water_after: u32 = 0,
    used_high_water_after: u32 = 0,
    retained_high_water_after: u32 = 0,
    waiters_current_after: u32 = 0,
    waiters_max_after: u32 = 0,
    owner_used_slots_after: u32 = 0,
    owner_used_high_water_after: u32 = 0,
    owner_retained_high_water_after: u32 = 0,
    owner_waiters_current_after: u32 = 0,
    owner_waiters_max_after: u32 = 0,
};

const PciInventorySample = struct {
    repetition: u8 = 0,
    iterations: u64 = 0,
    summaries: u64 = 0,
    records: u64 = 0,
    api_errors: u64 = 0,
    elapsed_ns: u64 = 0,
    ns_per_inventory: u64 = 0,
    ecam_read_delta: u64 = 0,
    ecam_write_delta: u64 = 0,
    legacy_read_delta: u64 = 0,
    legacy_write_delta: u64 = 0,
    mapping_check_delta: u64 = 0,
    mapping_miss_delta: u64 = 0,
    mapping_fast_delta: u64 = 0,
    invalid_access_delta: u64 = 0,
    class_find_delta: u64 = 0,
    detail_materialization_delta: u64 = 0,
    interrupt_read_delta: u64 = 0,
    command_read_delta: u64 = 0,
    bar_read_delta: u64 = 0,
    flags: u32 = 0,
    generation: u32 = 0,
    capacity: u32 = 0,
    found: u64 = 0,
    stored: u64 = 0,
    dropped: u64 = 0,
    ecam_stored: u64 = 0,
    legacy_stored: u64 = 0,
    vendor_probes_ecam: u64 = 0,
    vendor_probes_legacy: u64 = 0,
    class_reads: u64 = 0,
    header_reads: u64 = 0,
    enumeration_config_reads: u64 = 0,
    function_pages: u64 = 0,
    early_stops: u64 = 0,
    ecam_config_reads: u64 = 0,
    ecam_config_writes: u64 = 0,
    legacy_config_reads: u64 = 0,
    legacy_config_writes: u64 = 0,
    mapping_checks: u64 = 0,
    mapping_hits: u64 = 0,
    mapping_misses: u64 = 0,
    mapping_fast_accesses: u64 = 0,
    invalid_accesses: u64 = 0,
    class_find_calls: u64 = 0,
    class_candidates: u64 = 0,
    detail_materializations: u64 = 0,
    interrupt_dword_reads: u64 = 0,
    command_reads: u64 = 0,
    bar_reads: u64 = 0,
    enumeration_total_ns: u64 = 0,
    ecam_enumeration_ns: u64 = 0,
    legacy_enumeration_ns: u64 = 0,
    timing_unavailable: u64 = 0,
    checksum: u64 = 0,
};

const MemoryMetadataSample = struct {
    repetition: u8 = 0,
    pages: u64 = 0,
    reserve_commit_elapsed_ns: u64 = 0,
    reserve_commit_ns_per_page: u64 = 0,
    fault_elapsed_ns: u64 = 0,
    fault_ns_per_page: u64 = 0,
    page_state_elapsed_ns: u64 = 0,
    page_state_ns_per_page: u64 = 0,
    reclaim_elapsed_ns: u64 = 0,
    reclaim_ns_per_vm_frame: u64 = 0,
    reclaim_attempts: u32 = 0,
    reclaim_requested_frames: u64 = 0,
    reclaim_returned_frames: u64 = 0,
    reclaim_fs_returned_frames: u64 = 0,
    reclaim_vm_returned_frames: u64 = 0,
    reclaim_vm_page_outs: u64 = 0,
    reclaim_vm_failures: u64 = 0,
    target_committed_pages: u64 = 0,
    target_resident_pages: u64 = 0,
    target_nonresident_pages: u64 = 0,
    target_clean_pages: u64 = 0,
    target_slot_bound_pages: u64 = 0,
    block_physical_index_entries: u32 = 0,
    block_physical_step_max: u32 = 0,
    block_id_index_entries: u32 = 0,
    block_id_step_max: u32 = 0,
    block_free_slot_word_step_max: u32 = 0,
    range_address_entries: u32 = 0,
    range_address_probe_max: u32 = 0,
    commit_span_active: u32 = 0,
    commit_span_step_max: u32 = 0,
    page_state_span_active: u32 = 0,
    page_state_span_step_max: u32 = 0,
    block_physical_lookups: u64 = 0,
    block_physical_steps: u64 = 0,
    block_physical_mutations: u64 = 0,
    block_physical_rebuilds: u64 = 0,
    block_id_lookups: u64 = 0,
    block_id_steps: u64 = 0,
    block_free_slot_lookups: u64 = 0,
    block_free_slot_word_steps: u64 = 0,
    block_claim_transactions: u64 = 0,
    block_claim_rollbacks: u64 = 0,
    range_address_lookups: u64 = 0,
    range_address_probes: u64 = 0,
    commit_span_lookups: u64 = 0,
    commit_span_steps: u64 = 0,
    page_state_span_lookups: u64 = 0,
    page_state_span_steps: u64 = 0,
    reclaim_range_steps: u64 = 0,
    reclaim_span_steps: u64 = 0,
    reclaim_page_steps: u64 = 0,
    reclaim_wraps: u64 = 0,
};

const RunStats = struct {
    summary_query_attempts: u32 = 0,
    summary_query_successes: u32 = 0,
    summary_query_bytes: u64 = 0,
    summary_query_total_ticks: u64 = 0,
    summary_query_max_ticks: u64 = 0,
    checks: [max_check_results]CheckResult = .{CheckResult{}} ** max_check_results,
    check_count: usize = 0,
    dropped_checks: u32 = 0,
    blit_samples: [measurement.max_repetitions]BlitSample = .{BlitSample{}} ** measurement.max_repetitions,
    blit_sample_count: usize = 0,
    clock_samples: [measurement.max_repetitions]ClockSample = .{ClockSample{}} ** measurement.max_repetitions,
    clock_sample_count: usize = 0,
    service_registry_samples: [max_service_registry_samples]ServiceRegistrySample = .{ServiceRegistrySample{}} ** max_service_registry_samples,
    service_registry_sample_count: usize = 0,
    kernel_ipc_samples: [measurement.max_repetitions]KernelIpcSample = .{KernelIpcSample{}} ** measurement.max_repetitions,
    kernel_ipc_sample_count: usize = 0,
    kernel_ipc_discarded_attempts: u32 = 0,
    kernel_ipc_quiescence_wait_ticks: u64 = 0,
    kernel_ipc_quiescence_reached: bool = false,
    kernel_ipc_isolation_stop_attempts: u32 = 0,
    kernel_ipc_isolation_stopped: u32 = 0,
    kernel_ipc_isolation_already_stopped: u32 = 0,
    kernel_ipc_isolation_stop_mask: u32 = 0,
    kernel_ipc_isolation_restore_attempts: u32 = 0,
    kernel_ipc_isolation_restored: u32 = 0,
    kernel_ipc_isolation_restore_ok: bool = false,
    driver_work_samples: [measurement.max_repetitions]DriverWorkSample = .{DriverWorkSample{}} ** measurement.max_repetitions,
    driver_work_sample_count: usize = 0,
    pci_inventory_samples: [measurement.max_repetitions]PciInventorySample = .{PciInventorySample{}} ** measurement.max_repetitions,
    pci_inventory_sample_count: usize = 0,
    memory_metadata_samples: [measurement.max_repetitions]MemoryMetadataSample = .{MemoryMetadataSample{}} ** measurement.max_repetitions,
    memory_metadata_sample_count: usize = 0,
};
const avx_pattern_a: [32]u8 align(32) = .{
    0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
    0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0x0f, 0x10,
    0x21, 0x32, 0x43, 0x54, 0x65, 0x76, 0x87, 0x98,
    0xa9, 0xba, 0xcb, 0xdc, 0xed, 0xfe, 0x1f, 0x20,
};
const avx_pattern_b: [32]u8 align(32) = .{
    0xf0, 0xe1, 0xd2, 0xc3, 0xb4, 0xa5, 0x96, 0x87,
    0x78, 0x69, 0x5a, 0x4b, 0x3c, 0x2d, 0x1e, 0x0f,
    0xef, 0xde, 0xcd, 0xbc, 0xab, 0x9a, 0x89, 0x78,
    0x67, 0x56, 0x45, 0x34, 0x23, 0x12, 0x01, 0xf1,
};

fn storagePerformanceActive(info: r4os.abi.ProgramStoragePerformanceInfo) bool {
    return info.queue_high_water != 0 or
        info.queued_requests != 0 or
        info.dequeued_requests != 0 or
        info.completion_waits != 0 or
        info.completion_signals != 0 or
        info.worker_requests != 0 or
        info.read_ops != 0 or
        info.write_ops != 0 or
        info.flush_ops != 0;
}

fn storagePerformanceOk(info: r4os.abi.ProgramStoragePerformanceInfo) bool {
    if (info.sector_size == 0 or info.queue_depth == 0 or info.completion_timeouts != 0) return false;
    if (!storagePerformanceActive(info)) return true;
    const completion_path_ok =
        (info.worker_requests != 0 and info.worker_completions != 0) or
        (info.worker_requests == 0 and
            info.worker_completions == 0 and
            info.boot_inline_requests == info.queued_requests and
            info.boot_inline_completions == info.dequeued_requests);
    return info.queue_high_water != 0 and
        info.queued_requests != 0 and
        info.dequeued_requests != 0 and
        info.completion_waits != 0 and
        info.completion_signals != 0 and
        completion_path_ok;
}

fn prepareDriverWorkPcm() void {
    var frame: usize = 0;
    while (frame < driver_work_bench_pcm.len / 4) : (frame += 1) {
        const sample: i16 = if (((frame / 48) & 1) == 0) 1200 else -1200;
        const bits: u16 = @bitCast(sample);
        const offset = frame * 4;
        driver_work_bench_pcm[offset] = @intCast(bits & 0xFF);
        driver_work_bench_pcm[offset + 1] = @intCast(bits >> 8);
        driver_work_bench_pcm[offset + 2] = driver_work_bench_pcm[offset];
        driver_work_bench_pcm[offset + 3] = driver_work_bench_pcm[offset + 1];
    }
}

fn driverWorkSlotAccountingOk(info: r4os.abi.ProgramDriverWorkPerformanceInfo) bool {
    return info.free_slots + info.used_slots == info.queue_capacity and
        info.used_slots == info.queued_slots + info.running_slots + info.completed_slots + info.cancelled_slots and
        info.queued_slots == info.irq_queued_slots + info.task_queued_slots + info.deadline_queued_slots and
        info.deadline_queued_slots <= info.deadline_queue_capacity and
        info.deadline_running_slots <= info.running_slots and
        info.queue_high_water <= info.queue_capacity and
        info.used_high_water <= info.queue_capacity and
        info.retained_high_water <= info.queue_capacity;
}

fn driverWorkSnapshotContractOk(info: r4os.abi.ProgramDriverWorkPerformanceInfo) bool {
    const selected_owner_ok = info.selected_owner <= measurement.driver_work_owner_capacity;
    const owner_accounting_ok = info.selected_owner == 0 or
        (info.owner_used_slots == info.owner_queued_slots + info.owner_running_slots +
            info.owner_completed_slots + info.owner_cancelled_slots and
            info.owner_queued_slots == info.owner_irq_queued_slots + info.owner_task_queued_slots + info.owner_deadline_queued_slots and
            info.owner_deadline_running_slots <= info.owner_running_slots and
            info.owner_used_high_water <= info.queue_capacity and
            info.owner_retained_high_water <= info.queue_capacity);
    return info.version >= 2 and
        info.size >= @sizeOf(r4os.abi.ProgramDriverWorkPerformanceInfo) and
        info.initialized != 0 and
        info.worker_started != 0 and
        info.worker_count == 2 and
        info.deadline_worker_started != 0 and
        info.deadline_worker_count == 1 and
        info.deadline_queue_capacity > 0 and
        info.queue_capacity >= r4os.abi.driver_work_queue_capacity and
        info.irq_burst_limit > 0 and
        selected_owner_ok and
        owner_accounting_ok and
        driverWorkSlotAccountingOk(info);
}

const App = struct {
    sys: r4os.r4sys.Context,
    dev: r4os.r4dev.Context,
    draw: r4os.r4draw.Context,
    audio: r4os.r4audio.Context,
    net: ?r4os.r4net.Context,
    config: measurement.Config,
    monotonic_clock: r4os.abi.MonotonicClockInfo = .{},
    monotonic_clock_available: bool = false,
    time_state: r4os.abi.TimeState = .{},
    time_state_available: bool = false,
    kernel_version: ?r4os.abi.KernelVersion = null,
    hardware: ?r4os.abi.HardwareSummary = null,
    stats: RunStats = .{},

    fn init(r4_app: *r4os.App) ?App {
        return .{
            .sys = r4_app.system(),
            .dev = r4_app.devicesLowLevel() orelse return null,
            .draw = r4_app.drawing() orelse return null,
            .audio = r4_app.audioLowLevel() orelse return null,
            .net = r4_app.networkLowLevel(),
            .config = measurement.parseArgs(r4_app.args()),
        };
    }

    fn run(self: *App) i32 {
        if (self.config.show_help) {
            self.printUsage();
            return 0;
        }
        if (!self.config.valid()) {
            self.sys.write("PERFDIAG argument error: ");
            self.sys.println(self.config.parse_error.name());
            self.printUsage();
            return 2;
        }

        // Die passive Momentaufnahme ist absichtlich die erste beobachtende
        // Operation. Ausgabe und optionale Arbeitslast beginnen erst danach.
        const passive_summary = self.captureSummary() orelse {
            self.sys.println("PERFDIAG");
            _ = self.failBool("Passive performance snapshot unavailable");
            self.sys.println("PERFDIAG result: FAILED");
            return 1;
        };
        self.monotonic_clock_available = self.queryMonotonicClock(&self.monotonic_clock);
        if (!self.monotonic_clock_available) {
            self.time_state = self.sys.timeState();
            self.time_state_available = true;
        }

        if (self.config.mode != .benchmark) self.printRunHeader();

        var post_summary = passive_summary;
        var has_post_summary = false;
        var ok = true;
        switch (self.config.mode) {
            .baseline => {
                self.printCheck("Passive performance snapshot", true);
            },
            .conformance => {
                ok = self.runConformance(&post_summary);
                has_post_summary = true;
            },
            .benchmark => {
                ok = switch (self.config.benchmark_kind) {
                    .blit => self.probeBlitThroughput(),
                    .clock => self.probeMonotonicClock(),
                    .service_registry => self.probeServiceRegistry(),
                    .kernel_ipc => self.probeKernelIpc(),
                    .driver_work => self.probeDriverWork(),
                    .pci_inventory => self.probePciInventory(),
                    .memory_metadata => self.probeMemoryMetadata(),
                };
                if (self.captureSummary()) |summary| {
                    post_summary = summary;
                } else {
                    ok = false;
                }
                has_post_summary = true;
                self.printRunHeader();
                switch (self.config.benchmark_kind) {
                    .blit => {
                        self.printBlitResults();
                        self.printCheck("Blit throughput benchmark", ok);
                    },
                    .clock => {
                        self.printClockResults();
                        self.printCheck("Monotonic clock benchmark", ok);
                    },
                    .service_registry => {
                        self.printServiceRegistryResults();
                        self.printCheck("Linear service registry benchmark", ok);
                    },
                    .kernel_ipc => {
                        self.printKernelIpcResults();
                        self.printCheck("Kernel channel IPC benchmark", ok);
                    },
                    .driver_work => {
                        self.printDriverWorkResults();
                        self.printCheck("Driver workqueue benchmark", ok);
                    },
                    .pci_inventory => {
                        self.printPciInventoryResults();
                        self.printCheck("Canonical PCI inventory benchmark", ok);
                    },
                    .memory_metadata => {
                        self.printMemoryMetadataResults();
                        self.printCheck("Indexed memory metadata benchmark", ok);
                    },
                }
            },
        }

        // Metadaten ohne Einfluss auf die passive Baseline oder den isolierten
        // Benchmark erst nach der optionalen Arbeitslast erfassen.
        self.kernel_version = self.dev.kernelVersion();
        self.hardware = self.dev.hardwareSummary();

        self.sys.println("  Passive baseline (captured before workload):");
        self.printBaseline(passive_summary);
        if (has_post_summary and self.config.mode == .conformance) {
            self.sys.println("  Post-conformance snapshot:");
            self.printBaseline(post_summary);
        }
        self.printObserverCost();
        self.printMachineResult(passive_summary, post_summary, ok);

        self.sys.write("PERFDIAG result: ");
        self.sys.println(if (ok) "OK" else "FAILED");
        return if (ok) 0 else 1;
    }

    fn runConformance(self: *App, out_summary: *r4os.abi.ProgramPerformanceSummary) bool {
        var ok = true;
        ok = self.testApiHeader() and ok;
        ok = self.testPciInventorySnapshot() and ok;
        ok = self.testMonotonicClock() and ok;
        self.sys.sleepTicks(1);
        var fs_probe: [64]u8 = undefined;
        _ = self.sys.fileReadAt("C:\\R4OS\\CONFIG\\VERSION.R4S", 0, fs_probe[0..]);
        ok = self.testLocalFpuArithmetic() and ok;
        ok = self.probeDisplayResponsiveness() and ok;
        ok = self.probeAudioLatency() and ok;
        ok = self.probeServiceQueue() and ok;
        ok = self.probeFsPageCache() and ok;
        ok = self.probeFsWriteback() and ok;
        ok = self.probeGlobalReclaim() and ok;
        ok = self.probeBackingStore() and ok;
        ok = self.probeBackingStoreSlots() and ok;
        ok = self.probeBackingStoreLifecycle() and ok;
        ok = self.probePagerGates() and ok;
        ok = self.probePageIo() and ok;
        ok = self.probeVmPageState() and ok;
        ok = self.probeVmEvictionReclaim() and ok;
        ok = self.burnPreemptionWindow() and ok;
        ok = self.probeAvxRegisterState() and ok;
        const summary = self.captureSummary() orelse {
            _ = self.failBool("Performance snapshot unavailable");
            return false;
        };
        out_summary.* = summary;
        ok = self.testSummary(summary) and ok;
        ok = self.testSummaryClock(summary) and ok;
        ok = self.testPreemption(summary) and ok;
        ok = self.testSchedulerLatency(summary) and ok;
        ok = self.testFpuState(summary) and ok;
        ok = self.testAvxState(summary) and ok;
        ok = self.testDriverWork(summary) and ok;
        ok = self.testTasks(summary) and ok;
        ok = self.testStorage(summary) and ok;
        ok = self.testBootPhases(summary) and ok;
        ok = self.testIrqTiming() and ok;
        return ok;
    }

    fn queryMonotonicClock(self: *App, out: *r4os.abi.MonotonicClockInfo) bool {
        out.* = .{};
        return self.sys.hasFn("monotonic_clock") and self.sys.monotonicClock(out) > 0;
    }

    fn captureSummary(self: *App) ?r4os.abi.ProgramPerformanceSummary {
        self.stats.summary_query_attempts +%= 1;
        const start = self.sys.ticks();
        const summary = self.dev.performanceSummary();
        const elapsed = self.sys.ticks() - start;
        self.stats.summary_query_total_ticks +%= elapsed;
        self.stats.summary_query_max_ticks = @max(self.stats.summary_query_max_ticks, elapsed);
        if (summary != null) {
            self.stats.summary_query_successes +%= 1;
            self.stats.summary_query_bytes +%= @sizeOf(r4os.abi.ProgramPerformanceSummary);
        }
        return summary;
    }

    fn printRunHeader(self: *App) void {
        self.sys.println("PERFDIAG");
        self.sys.write("  Mode: ");
        self.sys.println(self.config.mode.name());
        self.sys.write("  Classification: ");
        self.sys.println(runClassification(self.config.mode));
        self.sys.write("  Cache state: ");
        self.sys.println(self.config.cache_state.name());
        if (self.config.mode == .benchmark) {
            self.sys.write("  Benchmark: ");
            self.sys.println(self.config.benchmark_kind.name());
        }
        self.printClockHeader();
        if (!self.config.mode_explicit) {
            self.sys.println("  No mode supplied; passive /BASELINE is the safe default.");
        }
        if (self.config.mode == .conformance) {
            self.sys.println("  Conformance proves contract progress, not a performance threshold.");
        }
        if (self.config.mode == .benchmark and self.config.cache_state == .unspecified) {
            self.sys.println("  Benchmark cache state is unspecified; use /COLD or /WARM for comparisons.");
        }
    }

    fn printUsage(self: *App) void {
        self.sys.println("PERFDIAG usage:");
        self.sys.println("  PERFDIAG /BASELINE");
        self.sys.println("  PERFDIAG /CONFORMANCE");
        self.sys.println("  PERFDIAG /BENCHMARK /BLIT /REPEAT:5 /COLD|/WARM");
        self.sys.println("  PERFDIAG /BENCHMARK /CLOCK /REPEAT:5 /WARM");
        self.sys.println("  PERFDIAG /BENCHMARK /SERVICE-REGISTRY /REPEAT:5 /WARM");
        self.sys.println("  PERFDIAG /BENCHMARK /KERNEL-IPC /REPEAT:5 /WARM");
        self.sys.println("  PERFDIAG /BENCHMARK /DRIVER-WORK /REPEAT:5 /WARM");
        self.sys.println("  PERFDIAG /BENCHMARK /PCI-INVENTORY /REPEAT:5 /WARM");
        self.sys.println("  PERFDIAG /BENCHMARK /MEMORY-METADATA /REPEAT:5 /WARM");
        self.sys.println("No mode runs the passive baseline. Repetitions: 3..20.");
    }

    fn printClockHeader(self: *App) void {
        if (self.monotonic_clock_available) {
            self.sys.write("  Monotonic clock: source=");
            self.sys.write(clockSourceName(self.monotonic_clock.source));
            self.sys.write(" generation=");
            self.sys.printU64(self.monotonic_clock.generation);
            self.sys.write(" resolutionNs=");
            self.sys.printU64(self.monotonic_clock.resolution_ns);
            self.sys.write(" event=");
            self.sys.write(timeBackendName(self.monotonic_clock.event_backend));
            self.sys.write(" eventHz=");
            self.sys.printU64(self.monotonic_clock.event_effective_hz);
            self.sys.println("");
            return;
        }
        self.sys.write("  Monotonic clock: legacy-event fallback backend=");
        self.sys.write(timeBackendName(self.time_state.monotonic_backend));
        self.sys.write(" hz=");
        self.sys.printU64(self.time_state.monotonic_hz);
        self.sys.println("");
    }

    fn eventBackend(self: *const App) u32 {
        return if (self.monotonic_clock_available)
            self.monotonic_clock.event_backend
        else
            self.time_state.monotonic_backend;
    }

    fn eventHz(self: *const App) u32 {
        return if (self.monotonic_clock_available)
            self.monotonic_clock.event_effective_hz
        else
            self.time_state.monotonic_hz;
    }

    fn printObserverCost(self: *App) void {
        self.sys.write("  Summary observer: attempts=");
        self.sys.printU64(self.stats.summary_query_attempts);
        self.sys.write(" successes=");
        self.sys.printU64(self.stats.summary_query_successes);
        self.sys.write(" bytes=");
        self.sys.printU64(self.stats.summary_query_bytes);
        self.sys.write(" ticksTotal=");
        self.sys.printU64(self.stats.summary_query_total_ticks);
        self.sys.write(" ticksMax=");
        self.sys.printU64(self.stats.summary_query_max_ticks);
        self.sys.println(" hotLoopQueries=0");
    }

    fn recordCheck(self: *App, label: []const u8, ok: bool) void {
        if (self.stats.check_count >= self.stats.checks.len) {
            self.stats.dropped_checks +%= 1;
            return;
        }
        self.stats.checks[self.stats.check_count] = .{ .label = label, .ok = ok };
        self.stats.check_count += 1;
    }

    fn printMachineResult(
        self: *App,
        passive_summary: r4os.abi.ProgramPerformanceSummary,
        post_summary: r4os.abi.ProgramPerformanceSummary,
        ok: bool,
    ) void {
        self.sys.println("PERFDIAG machine-result begin");

        self.machineLinePrefix("run");
        self.sys.write(",\"module\":");
        self.printJsonString("PERFDIAG");
        self.sys.write(",\"module_version\":");
        self.printJsonString(module_version);
        self.sys.write(",\"mode\":");
        self.printJsonString(self.config.mode.name());
        self.sys.write(",\"mode_explicit\":");
        self.printJsonBool(self.config.mode_explicit);
        self.sys.write(",\"classification\":");
        self.printJsonString(runClassification(self.config.mode));
        self.sys.write(",\"cache_state\":");
        self.printJsonString(self.config.cache_state.name());
        self.sys.write(",\"benchmark\":");
        self.printJsonString(self.config.benchmark_kind.name());
        self.sys.write(",\"repetitions\":");
        self.sys.printU64(if (self.config.mode == .benchmark) self.config.repetitions else 1);
        self.sys.write(",\"kernel_ipc_discarded_attempts\":");
        self.sys.printU64(self.stats.kernel_ipc_discarded_attempts);
        self.sys.write(",\"kernel_ipc_quiescence_wait_ticks\":");
        self.sys.printU64(self.stats.kernel_ipc_quiescence_wait_ticks);
        self.sys.write(",\"kernel_ipc_quiescence_reached\":");
        self.printJsonBool(self.stats.kernel_ipc_quiescence_reached);
        self.sys.write(",\"kernel_ipc_isolation_stop_attempts\":");
        self.sys.printU64(self.stats.kernel_ipc_isolation_stop_attempts);
        self.sys.write(",\"kernel_ipc_isolation_stopped\":");
        self.sys.printU64(self.stats.kernel_ipc_isolation_stopped);
        self.sys.write(",\"kernel_ipc_isolation_already_stopped\":");
        self.sys.printU64(self.stats.kernel_ipc_isolation_already_stopped);
        self.sys.write(",\"kernel_ipc_isolation_stop_mask\":");
        self.sys.printU64(self.stats.kernel_ipc_isolation_stop_mask);
        self.sys.write(",\"kernel_ipc_isolation_restore_attempts\":");
        self.sys.printU64(self.stats.kernel_ipc_isolation_restore_attempts);
        self.sys.write(",\"kernel_ipc_isolation_restored\":");
        self.sys.printU64(self.stats.kernel_ipc_isolation_restored);
        self.sys.write(",\"kernel_ipc_isolation_restore_ok\":");
        self.printJsonBool(self.stats.kernel_ipc_isolation_restore_ok);
        self.sys.write(",\"clock_available\":");
        self.printJsonBool(self.monotonic_clock_available);
        self.sys.write(",\"clock_source\":");
        self.printJsonString(if (self.monotonic_clock_available) clockSourceName(self.monotonic_clock.source) else "legacy-event");
        self.sys.write(",\"clock_flags\":");
        self.sys.printU64(if (self.monotonic_clock_available) self.monotonic_clock.flags else 0);
        self.sys.write(",\"clock_generation\":");
        self.sys.printU64(if (self.monotonic_clock_available) self.monotonic_clock.generation else 0);
        self.sys.write(",\"clock_resolution_ns\":");
        self.sys.printU64(if (self.monotonic_clock_available) self.monotonic_clock.resolution_ns else 0);
        self.sys.write(",\"event_backend\":");
        self.printJsonString(timeBackendName(self.eventBackend()));
        self.sys.write(",\"event_hz\":");
        self.sys.printU64(self.eventHz());
        self.sys.write(",\"event_frequency_numerator\":");
        self.sys.printU64(if (self.monotonic_clock_available) self.monotonic_clock.event_frequency_numerator else self.eventHz());
        self.sys.write(",\"event_frequency_denominator\":");
        self.sys.printU64(if (self.monotonic_clock_available) self.monotonic_clock.event_frequency_denominator else 1);
        self.sys.write(",\"api_version\":");
        self.sys.printU64(self.sys.tableAbiVersion());
        self.sys.write(",\"kernel_major\":");
        self.sys.printU64(if (self.kernel_version) |version| version.major else 0);
        self.sys.write(",\"kernel_minor\":");
        self.sys.printU64(if (self.kernel_version) |version| version.minor else 0);
        self.sys.write(",\"kernel_patch\":");
        self.sys.printU64(if (self.kernel_version) |version| version.patch else 0);
        self.sys.write(",\"cpu_logical_processors\":");
        self.sys.printU64(if (self.hardware) |hardware| hardware.cpu_logical_processors else 0);
        self.sys.write(",\"result\":");
        self.printJsonString(if (ok) "ok" else "failed");
        self.sys.println("}");

        self.machineLinePrefix("baseline");
        self.sys.write(",\"captured_before_workload\":true,\"ticks\":");
        self.sys.printU64(passive_summary.ticks);
        self.sys.write(",\"tick_hz\":");
        self.sys.printU64(passive_summary.tick_hz);
        self.sys.write(",\"flags\":");
        self.sys.printU64(passive_summary.flags);
        self.sys.write(",\"missing_flags\":");
        self.sys.printU64(passive_summary.missing_flags);
        self.sys.println("}");

        self.machineLinePrefix("storage_dispatch");
        self.sys.write(",\"fs_drive_gate_count\":");
        self.sys.printU64(post_summary.fs_drive_gate_count);
        self.sys.write(",\"fs_parallel_active_max\":");
        self.sys.printU64(post_summary.fs_parallel_active_max);
        self.sys.write(",\"controller_count\":");
        self.sys.printU64(post_summary.storage_controller_count);
        self.sys.write(",\"worker_count\":");
        self.sys.printU64(post_summary.storage_worker_count);
        self.sys.write(",\"worker_parallel_active_max\":");
        self.sys.printU64(post_summary.storage_worker_parallel_active_max);
        self.sys.write(",\"worker_start_failure_delta\":");
        self.sys.printU64(delta(post_summary.storage_worker_start_failures, passive_summary.storage_worker_start_failures));
        self.sys.write(",\"direct_request_delta\":");
        self.sys.printU64(delta(post_summary.storage_direct_requests, passive_summary.storage_direct_requests));
        self.sys.write(",\"direct_byte_delta\":");
        self.sys.printU64(delta(post_summary.storage_direct_bytes, passive_summary.storage_direct_bytes));
        self.sys.write(",\"bounce_allocation_delta\":");
        self.sys.printU64(delta(post_summary.storage_bounce_allocations, passive_summary.storage_bounce_allocations));
        self.sys.write(",\"bounce_byte_delta\":");
        self.sys.printU64(delta(post_summary.storage_bounce_bytes, passive_summary.storage_bounce_bytes));
        self.sys.write(",\"bounce_copy_byte_delta\":");
        self.sys.printU64(delta(post_summary.storage_bounce_copy_bytes, passive_summary.storage_bounce_copy_bytes));
        self.sys.write(",\"direct_timeout_wait_delta\":");
        self.sys.printU64(delta(post_summary.storage_direct_timeout_waits, passive_summary.storage_direct_timeout_waits));
        self.sys.write(",\"completion_timeout_delta\":");
        self.sys.printU64(delta(post_summary.storage_completion_timeouts, passive_summary.storage_completion_timeouts));
        self.sys.write(",\"fs_bulk_write_request_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_bulk_write_requests, passive_summary.fs_cache_bulk_write_requests));
        self.sys.write(",\"fs_bulk_write_sector_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_bulk_write_sectors, passive_summary.fs_cache_bulk_write_sectors));
        self.sys.write(",\"fs_selective_flush_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_selective_flushes, passive_summary.fs_cache_selective_flushes));
        self.sys.write(",\"fs_selective_writeback_sector_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_selective_writeback_sectors, passive_summary.fs_cache_selective_writeback_sectors));
        self.sys.write(",\"fs_foreign_dirty_sector_skip_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_selective_foreign_dirty_sectors_skipped, passive_summary.fs_cache_selective_foreign_dirty_sectors_skipped));
        self.sys.write(",\"completion_tail_ticks\":");
        self.sys.printU64(post_summary.storage_completion_max_ticks);
        self.sys.write(",\"fs_tail_ticks\":");
        self.sys.printU64(post_summary.fs_max_ticks);
        self.sys.println("}");

        self.machineLinePrefix("fs_cache_policy");
        self.sys.write(",\"version\":");
        self.sys.printU64(post_summary.fs_cache_policy_version);
        self.sys.write(",\"device_capacity\":");
        self.sys.printU64(post_summary.fs_cache_policy_device_capacity);
        self.sys.write(",\"dirty_low_pages\":");
        self.sys.printU64(post_summary.fs_cache_policy_dirty_low_pages);
        self.sys.write(",\"dirty_high_pages\":");
        self.sys.printU64(post_summary.fs_cache_policy_dirty_high_pages);
        self.sys.write(",\"max_dirty_age_ticks\":");
        self.sys.printU64(post_summary.fs_cache_policy_max_dirty_age_ticks);
        self.sys.write(",\"page_budget\":");
        self.sys.printU64(post_summary.fs_cache_policy_background_page_budget);
        self.sys.write(",\"worker_started\":");
        self.sys.printU64(post_summary.fs_cache_policy_worker_started);
        self.sys.write(",\"worker_wakeup_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_policy_worker_wakeups, passive_summary.fs_cache_policy_worker_wakeups));
        self.sys.write(",\"background_drain_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_policy_background_drains, passive_summary.fs_cache_policy_background_drains));
        self.sys.write(",\"background_sector_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_policy_background_sectors, passive_summary.fs_cache_policy_background_sectors));
        self.sys.write(",\"background_error_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_policy_background_errors, passive_summary.fs_cache_policy_background_errors));
        self.sys.write(",\"clean_device_probe_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_policy_clean_device_probes, passive_summary.fs_cache_policy_clean_device_probes));
        self.sys.write(",\"dirty_device_probe_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_policy_dirty_device_probes, passive_summary.fs_cache_policy_dirty_device_probes));
        self.sys.write(",\"full_scan_fallback_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_policy_full_scan_fallbacks, passive_summary.fs_cache_policy_full_scan_fallbacks));
        self.sys.write(",\"read_ahead_request_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_read_ahead_requests, passive_summary.fs_cache_read_ahead_requests));
        self.sys.write(",\"read_ahead_issued_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_read_ahead_issued, passive_summary.fs_cache_read_ahead_issued));
        self.sys.write(",\"read_ahead_hit_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_read_ahead_hits, passive_summary.fs_cache_read_ahead_hits));
        self.sys.write(",\"capacity_min_pages\":");
        self.sys.printU64(post_summary.fs_cache_capacity_min_pages);
        self.sys.write(",\"capacity_max_pages\":");
        self.sys.printU64(post_summary.fs_cache_capacity_max_pages);
        self.sys.write(",\"capacity_ram_limit_pages\":");
        self.sys.printU64(post_summary.fs_cache_capacity_ram_limit_pages);
        self.sys.write(",\"capacity_active_limit_pages\":");
        self.sys.printU64(post_summary.fs_cache_capacity_active_limit_pages);
        self.sys.write(",\"capacity_pressure_level\":");
        self.sys.printU64(post_summary.fs_cache_capacity_pressure_level);
        self.sys.write(",\"read_ahead_window_pages\":");
        self.sys.printU64(post_summary.fs_cache_read_ahead_window_pages);
        self.sys.write(",\"read_ahead_window_max_pages\":");
        self.sys.printU64(post_summary.fs_cache_read_ahead_window_max_pages);
        self.sys.write(",\"fill_run_request_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_fill_run_requests, passive_summary.fs_cache_fill_run_requests));
        self.sys.write(",\"fill_backend_request_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_fill_run_backend_requests, passive_summary.fs_cache_fill_run_backend_requests));
        self.sys.write(",\"fill_page_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_fill_run_pages, passive_summary.fs_cache_fill_run_pages));
        self.sys.write(",\"fill_sector_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_fill_run_sectors, passive_summary.fs_cache_fill_run_sectors));
        self.sys.write(",\"fill_byte_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_fill_run_bytes, passive_summary.fs_cache_fill_run_bytes));
        self.sys.write(",\"fill_failure_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_fill_run_failures, passive_summary.fs_cache_fill_run_failures));
        self.sys.write(",\"fill_retry_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_fill_run_retries, passive_summary.fs_cache_fill_run_retries));
        self.sys.write(",\"fill_max_pages\":");
        self.sys.printU64(post_summary.fs_cache_fill_run_max_pages);
        self.sys.write(",\"fill_scatter_copy_byte_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_fill_scatter_copy_bytes, passive_summary.fs_cache_fill_scatter_copy_bytes));
        self.sys.write(",\"read_staging_copy_byte_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_read_staging_copy_bytes, passive_summary.fs_cache_read_staging_copy_bytes));
        self.sys.write(",\"read_caller_copy_byte_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_read_caller_copy_bytes, passive_summary.fs_cache_read_caller_copy_bytes));
        self.sys.write(",\"read_publish_lock_drop_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_read_publish_lock_drops, passive_summary.fs_cache_read_publish_lock_drops));
        self.sys.write(",\"fill_lock_drop_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_fill_lock_drops, passive_summary.fs_cache_fill_lock_drops));
        self.sys.write(",\"capacity_reduction_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_capacity_reductions, passive_summary.fs_cache_capacity_reductions));
        self.sys.write(",\"capacity_trimmed_page_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_capacity_trimmed_pages, passive_summary.fs_cache_capacity_trimmed_pages));
        self.sys.write(",\"read_ahead_page_scheduled_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_read_ahead_pages_scheduled, passive_summary.fs_cache_read_ahead_pages_scheduled));
        self.sys.write(",\"read_ahead_page_issued_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_read_ahead_pages_issued, passive_summary.fs_cache_read_ahead_pages_issued));
        self.sys.write(",\"read_ahead_random_reset_delta\":");
        self.sys.printU64(delta(post_summary.fs_cache_read_ahead_random_resets, passive_summary.fs_cache_read_ahead_random_resets));
        self.sys.println("}");

        self.machineLinePrefix("ntfs_metadata_cache");
        self.sys.write(",\"version\":");
        self.sys.printU64(post_summary.ntfs_metadata_cache_version);
        self.sys.write(",\"active_volumes\":");
        self.sys.printU64(post_summary.ntfs_metadata_cache_active_volumes);
        self.sys.write(",\"bytes_per_volume\":");
        self.sys.printU64(post_summary.ntfs_metadata_cache_bytes_per_volume);
        self.sys.write(",\"slot_capacity\":");
        self.sys.printU64(post_summary.ntfs_metadata_cache_slot_capacity);
        self.sys.write(",\"record_capacity\":");
        self.sys.printU64(post_summary.ntfs_metadata_record_capacity);
        self.sys.write(",\"attribute_capacity\":");
        self.sys.printU64(post_summary.ntfs_metadata_attribute_capacity);
        self.sys.write(",\"index_capacity\":");
        self.sys.printU64(post_summary.ntfs_metadata_index_capacity);
        self.sys.write(",\"path_capacity\":");
        self.sys.printU64(post_summary.ntfs_metadata_path_capacity);
        self.sys.write(",\"record_entries\":");
        self.sys.printU64(post_summary.ntfs_metadata_record_entries);
        self.sys.write(",\"attribute_entries\":");
        self.sys.printU64(post_summary.ntfs_metadata_attribute_entries);
        self.sys.write(",\"index_entries\":");
        self.sys.printU64(post_summary.ntfs_metadata_index_entries);
        self.sys.write(",\"path_entries\":");
        self.sys.printU64(post_summary.ntfs_metadata_path_entries);
        self.sys.write(",\"mount_generation\":");
        self.sys.printU64(post_summary.ntfs_metadata_mount_generation);
        self.sys.write(",\"content_generation\":");
        self.sys.printU64(post_summary.ntfs_metadata_content_generation);
        self.sys.write(",\"negative_ttl_ticks\":");
        self.sys.printU64(post_summary.ntfs_metadata_negative_ttl_ticks);
        self.sys.write(",\"record_hit_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_record_hits, passive_summary.ntfs_metadata_record_hits));
        self.sys.write(",\"record_miss_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_record_misses, passive_summary.ntfs_metadata_record_misses));
        self.sys.write(",\"record_store_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_record_stores, passive_summary.ntfs_metadata_record_stores));
        self.sys.write(",\"record_eviction_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_record_evictions, passive_summary.ntfs_metadata_record_evictions));
        self.sys.write(",\"attribute_hit_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_attribute_hits, passive_summary.ntfs_metadata_attribute_hits));
        self.sys.write(",\"attribute_miss_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_attribute_misses, passive_summary.ntfs_metadata_attribute_misses));
        self.sys.write(",\"attribute_store_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_attribute_stores, passive_summary.ntfs_metadata_attribute_stores));
        self.sys.write(",\"attribute_eviction_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_attribute_evictions, passive_summary.ntfs_metadata_attribute_evictions));
        self.sys.write(",\"index_hit_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_index_hits, passive_summary.ntfs_metadata_index_hits));
        self.sys.write(",\"index_miss_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_index_misses, passive_summary.ntfs_metadata_index_misses));
        self.sys.write(",\"index_store_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_index_stores, passive_summary.ntfs_metadata_index_stores));
        self.sys.write(",\"index_eviction_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_index_evictions, passive_summary.ntfs_metadata_index_evictions));
        self.sys.write(",\"path_query_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_path_queries, passive_summary.ntfs_metadata_path_queries));
        self.sys.write(",\"path_positive_hit_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_path_positive_hits, passive_summary.ntfs_metadata_path_positive_hits));
        self.sys.write(",\"path_negative_hit_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_path_negative_hits, passive_summary.ntfs_metadata_path_negative_hits));
        self.sys.write(",\"path_miss_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_path_misses, passive_summary.ntfs_metadata_path_misses));
        self.sys.write(",\"path_positive_store_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_path_positive_stores, passive_summary.ntfs_metadata_path_positive_stores));
        self.sys.write(",\"path_negative_store_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_path_negative_stores, passive_summary.ntfs_metadata_path_negative_stores));
        self.sys.write(",\"path_expiration_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_path_expirations, passive_summary.ntfs_metadata_path_expirations));
        self.sys.write(",\"lookup_tree_walk_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_lookup_tree_walks, passive_summary.ntfs_metadata_lookup_tree_walks));
        self.sys.write(",\"recovery_bypass_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_recovery_cache_bypasses, passive_summary.ntfs_metadata_recovery_cache_bypasses));
        self.sys.write(",\"mount_invalidation_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_mount_invalidations, passive_summary.ntfs_metadata_mount_invalidations));
        self.sys.write(",\"mutation_invalidation_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_mutation_invalidations, passive_summary.ntfs_metadata_mutation_invalidations));
        self.sys.write(",\"external_invalidation_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_external_invalidations, passive_summary.ntfs_metadata_external_invalidations));
        self.sys.write(",\"invalidated_entry_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_invalidated_entries, passive_summary.ntfs_metadata_invalidated_entries));
        self.sys.write(",\"payload_write_retention_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_payload_write_retentions, passive_summary.ntfs_metadata_payload_write_retentions));
        self.sys.write(",\"system_write_retention_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_system_write_retentions, passive_summary.ntfs_metadata_system_write_retentions));
        self.sys.write(",\"targeted_invalidation_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_targeted_invalidations, passive_summary.ntfs_metadata_targeted_invalidations));
        self.sys.write(",\"targeted_record_invalidation_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_targeted_record_invalidations, passive_summary.ntfs_metadata_targeted_record_invalidations));
        self.sys.write(",\"targeted_attribute_invalidation_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_targeted_attribute_invalidations, passive_summary.ntfs_metadata_targeted_attribute_invalidations));
        self.sys.write(",\"targeted_directory_invalidation_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_targeted_directory_invalidations, passive_summary.ntfs_metadata_targeted_directory_invalidations));
        self.sys.write(",\"global_mutation_invalidation_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_global_mutation_invalidations, passive_summary.ntfs_metadata_global_mutation_invalidations));
        self.sys.write(",\"recovery_invalidation_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_recovery_invalidations, passive_summary.ntfs_metadata_recovery_invalidations));
        self.sys.write(",\"mutation_invalidated_record_entry_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_mutation_invalidated_record_entries, passive_summary.ntfs_metadata_mutation_invalidated_record_entries));
        self.sys.write(",\"mutation_invalidated_attribute_entry_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_mutation_invalidated_attribute_entries, passive_summary.ntfs_metadata_mutation_invalidated_attribute_entries));
        self.sys.write(",\"mutation_invalidated_index_entry_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_mutation_invalidated_index_entries, passive_summary.ntfs_metadata_mutation_invalidated_index_entries));
        self.sys.write(",\"mutation_invalidated_path_entry_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_mutation_invalidated_path_entries, passive_summary.ntfs_metadata_mutation_invalidated_path_entries));
        self.sys.write(",\"reclaim_request_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_reclaim_requests, passive_summary.ntfs_metadata_reclaim_requests));
        self.sys.write(",\"reclaim_scan_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_reclaim_scans, passive_summary.ntfs_metadata_reclaim_scans));
        self.sys.write(",\"reclaimed_entry_delta\":");
        self.sys.printU64(delta(post_summary.ntfs_metadata_reclaimed_entries, passive_summary.ntfs_metadata_reclaimed_entries));
        self.sys.println("}");

        var check_index: usize = 0;
        while (check_index < self.stats.check_count) : (check_index += 1) {
            const check = self.stats.checks[check_index];
            self.machineLinePrefix("check");
            self.sys.write(",\"name\":");
            self.printJsonString(check.label);
            self.sys.write(",\"ok\":");
            self.printJsonBool(check.ok);
            self.sys.println("}");
        }

        var rates: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var sample_index: usize = 0;
        while (sample_index < self.stats.blit_sample_count) : (sample_index += 1) {
            const sample = self.stats.blit_samples[sample_index];
            rates[sample_index] = sample.kb_per_second;
            self.machineLinePrefix("blit_sample");
            self.sys.write(",\"sample\":");
            self.sys.printU64(sample_index + 1);
            self.sys.write(",\"iterations\":");
            self.sys.printU64(sample.iterations);
            self.sys.write(",\"elapsed_ticks\":");
            self.sys.printU64(sample.elapsed_ticks);
            self.sys.write(",\"elapsed_ns\":");
            self.sys.printU64(sample.elapsed_ns);
            self.sys.write(",\"event_hz\":");
            self.sys.printU64(self.eventHz());
            self.sys.write(",\"bytes\":");
            self.sys.printU64(sample.bytes);
            self.sys.write(",\"kb_per_second\":");
            self.sys.printU64(sample.kb_per_second);
            self.sys.write(",\"kb_bytes\":");
            self.sys.printU64(measurement.bytes_per_kb);
            self.sys.write(",\"mb_kb\":");
            self.sys.printU64(measurement.kb_per_mb);
            self.sys.println("}");
        }

        var clock_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        sample_index = 0;
        while (sample_index < self.stats.clock_sample_count) : (sample_index += 1) {
            const sample = self.stats.clock_samples[sample_index];
            clock_costs[sample_index] = sample.ns_per_call;
            self.machineLinePrefix("clock_sample");
            self.sys.write(",\"sample\":");
            self.sys.printU64(sample_index + 1);
            self.sys.write(",\"calls\":");
            self.sys.printU64(sample.calls);
            self.sys.write(",\"elapsed_ns\":");
            self.sys.printU64(sample.elapsed_ns);
            self.sys.write(",\"ns_per_call\":");
            self.sys.printU64(sample.ns_per_call);
            self.sys.write(",\"min_positive_delta_ns\":");
            self.sys.printU64(sample.min_positive_delta_ns);
            self.sys.write(",\"zero_deltas\":");
            self.sys.printU64(sample.zero_deltas);
            self.sys.write(",\"regressions\":");
            self.sys.printU64(sample.regressions);
            self.sys.println("}");
        }
        sample_index = 0;
        while (sample_index < self.stats.service_registry_sample_count) : (sample_index += 1) {
            const sample = self.stats.service_registry_samples[sample_index];
            self.machineLinePrefix("service_registry_sample");
            self.sys.write(",\"phase\":");
            self.printJsonString(sample.phase.name());
            self.sys.write(",\"phase_id\":");
            self.sys.printU64(@intFromEnum(sample.phase));
            self.sys.write(",\"sample\":");
            self.sys.printU64(sample.repetition);
            self.sys.write(",\"iterations\":");
            self.sys.printU64(sample.iterations);
            self.sys.write(",\"services_per_enumeration\":");
            self.sys.printU64(sample.services_per_enumeration);
            self.sys.write(",\"entries\":");
            self.sys.printU64(sample.entries);
            self.sys.write(",\"api_calls\":");
            self.sys.printU64(sample.api_calls);
            self.sys.write(",\"api_end_markers\":");
            self.sys.printU64(sample.api_end_markers);
            self.sys.write(",\"api_errors\":");
            self.sys.printU64(sample.api_errors);
            self.sys.write(",\"elapsed_ns\":");
            self.sys.printU64(sample.elapsed_ns);
            self.sys.write(",\"ns_per_enumeration\":");
            self.sys.printU64(sample.ns_per_enumeration);
            self.sys.write(",\"index_queries\":");
            self.sys.printU64(sample.index_queries);
            self.sys.write(",\"refresh_requests\":");
            self.sys.printU64(sample.refresh_requests);
            self.sys.write(",\"refresh_visits\":");
            self.sys.printU64(sample.refresh_visits);
            self.sys.write(",\"instance_lookups\":");
            self.sys.printU64(sample.instance_lookups);
            self.sys.write(",\"counter_end_markers\":");
            self.sys.printU64(sample.counter_end_markers);
            self.sys.write(",\"legacy_reference_refresh_visits\":");
            self.sys.printU64(sample.legacy_reference_refresh_visits);
            self.sys.write(",\"refresh_reduction_basis_points\":");
            self.sys.printU64(reductionBasisPoints(sample.legacy_reference_refresh_visits, sample.refresh_visits));
            self.sys.write(",\"checksum\":");
            self.sys.printU64(sample.checksum);
            self.sys.println("}");
        }
        if (self.stats.clock_sample_count > 0) {
            const distribution = measurement.summarize(clock_costs[0..self.stats.clock_sample_count]);
            self.machineLinePrefix("clock_distribution");
            self.sys.write(",\"unit\":\"ns/call\",\"count\":");
            self.sys.printU64(distribution.count);
            self.sys.write(",\"min\":");
            self.sys.printU64(distribution.minimum);
            self.sys.write(",\"p50\":");
            self.sys.printU64(distribution.p50);
            self.sys.write(",\"p95\":");
            self.sys.printU64(distribution.p95);
            self.sys.write(",\"p99\":");
            self.sys.printU64(distribution.p99);
            self.sys.write(",\"max\":");
            self.sys.printU64(distribution.maximum);
            self.sys.write(",\"mean\":");
            self.sys.printU64(distribution.mean);
            self.sys.println("}");
        }
        if (self.stats.blit_sample_count > 0) {
            const distribution = measurement.summarize(rates[0..self.stats.blit_sample_count]);
            self.machineLinePrefix("blit_distribution");
            self.sys.write(",\"unit\":\"KB/s\",\"count\":");
            self.sys.printU64(distribution.count);
            self.sys.write(",\"min\":");
            self.sys.printU64(distribution.minimum);
            self.sys.write(",\"p50\":");
            self.sys.printU64(distribution.p50);
            self.sys.write(",\"p95\":");
            self.sys.printU64(distribution.p95);
            self.sys.write(",\"p99\":");
            self.sys.printU64(distribution.p99);
            self.sys.write(",\"max\":");
            self.sys.printU64(distribution.maximum);
            self.sys.write(",\"mean\":");
            self.sys.printU64(distribution.mean);
            self.sys.println("}");
        }
        var phase_index: u8 = 0;
        while (phase_index < measurement.service_registry_phase_count) : (phase_index += 1) {
            const phase: measurement.ServiceRegistryPhase = @enumFromInt(phase_index);
            var costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
            var cost_count: usize = 0;
            sample_index = 0;
            while (sample_index < self.stats.service_registry_sample_count) : (sample_index += 1) {
                const sample = self.stats.service_registry_samples[sample_index];
                if (sample.phase != phase) continue;
                costs[cost_count] = sample.ns_per_enumeration;
                cost_count += 1;
            }
            if (cost_count == 0) continue;
            const distribution = measurement.summarize(costs[0..cost_count]);
            self.machineLinePrefix("service_registry_distribution");
            self.sys.write(",\"phase\":");
            self.printJsonString(phase.name());
            self.sys.write(",\"phase_id\":");
            self.sys.printU64(phase_index);
            self.sys.write(",\"unit\":\"ns/enumeration\",\"count\":");
            self.sys.printU64(distribution.count);
            self.sys.write(",\"min\":");
            self.sys.printU64(distribution.minimum);
            self.sys.write(",\"p50\":");
            self.sys.printU64(distribution.p50);
            self.sys.write(",\"p95\":");
            self.sys.printU64(distribution.p95);
            self.sys.write(",\"p99\":");
            self.sys.printU64(distribution.p99);
            self.sys.write(",\"max\":");
            self.sys.printU64(distribution.maximum);
            self.sys.write(",\"mean\":");
            self.sys.printU64(distribution.mean);
            self.sys.println("}");
        }
        self.printKernelIpcMachineResults();
        self.printDriverWorkMachineResults();
        self.printPciInventoryMachineResults();
        self.printMemoryMetadataMachineResults();

        self.machineLinePrefix("observer");
        self.sys.write(",\"summary_query_attempts\":");
        self.sys.printU64(self.stats.summary_query_attempts);
        self.sys.write(",\"summary_query_successes\":");
        self.sys.printU64(self.stats.summary_query_successes);
        self.sys.write(",\"summary_bytes\":");
        self.sys.printU64(self.stats.summary_query_bytes);
        self.sys.write(",\"summary_total_ticks\":");
        self.sys.printU64(self.stats.summary_query_total_ticks);
        self.sys.write(",\"summary_max_ticks\":");
        self.sys.printU64(self.stats.summary_query_max_ticks);
        self.sys.write(",\"summary_hot_loop_queries\":0,\"timer_resolution_ticks\":1,\"zero_tick_samples_possible\":true,\"dropped_checks\":");
        self.sys.printU64(self.stats.dropped_checks);
        self.sys.println("}");

        self.sys.println("PERFDIAG machine-result end");
    }

    fn printKernelIpcMachineResults(self: *App) void {
        var caller_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var queue_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var run_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var e2e_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var index: usize = 0;
        while (index < self.stats.kernel_ipc_sample_count) : (index += 1) {
            const sample = self.stats.kernel_ipc_samples[index];
            caller_costs[index] = sample.caller_ns_per_request;
            queue_costs[index] = sample.handler_queue_ns_per_request;
            run_costs[index] = sample.handler_run_ns_per_request;
            e2e_costs[index] = sample.handler_e2e_ns_per_request;
            self.machineLinePrefix("kernel_ipc_sample");
            self.printJsonU64Field("sample", sample.repetition);
            self.printJsonU64Field("attempt", sample.attempt);
            self.printJsonU64Field("iterations", sample.iterations);
            self.printJsonU64Field("requests", sample.requests);
            self.printJsonU64Field("status_requests", sample.status_requests);
            self.printJsonU64Field("error_requests", sample.error_requests);
            self.printJsonU64Field("small_requests", sample.small_requests);
            self.printJsonU64Field("max_requests", sample.max_requests);
            self.printJsonU64Field("elapsed_ns", sample.elapsed_ns);
            self.printJsonU64Field("caller_ns_per_request", sample.caller_ns_per_request);
            self.printJsonU64Field("handler_queued", sample.handler_queued);
            self.printJsonU64Field("handler_completed", sample.handler_completed);
            self.printJsonU64Field("handler_failures", sample.handler_failures);
            self.printJsonU64Field("handler_direct", sample.handler_direct);
            self.printJsonU64Field("handler_waits", sample.handler_waits);
            self.printJsonU64Field("handler_wait_timeouts", sample.handler_wait_timeouts);
            self.printJsonU64Field("handler_queue_ns", sample.handler_queue_ns);
            self.printJsonU64Field("handler_queue_ns_per_request", sample.handler_queue_ns_per_request);
            self.printJsonU64Field("handler_queue_max_before_ns", sample.handler_queue_max_before_ns);
            self.printJsonU64Field("handler_queue_max_after_ns", sample.handler_queue_max_ns);
            self.printJsonU64Field("handler_run_ns", sample.handler_run_ns);
            self.printJsonU64Field("handler_run_ns_per_request", sample.handler_run_ns_per_request);
            self.printJsonU64Field("handler_run_max_before_ns", sample.handler_run_max_before_ns);
            self.printJsonU64Field("handler_run_max_after_ns", sample.handler_run_max_ns);
            self.printJsonU64Field("handler_e2e_ns", sample.handler_e2e_ns);
            self.printJsonU64Field("handler_e2e_ns_per_request", sample.handler_e2e_ns_per_request);
            self.printJsonU64Field("handler_e2e_max_before_ns", sample.handler_e2e_max_before_ns);
            self.printJsonU64Field("handler_e2e_max_after_ns", sample.handler_e2e_max_ns);
            self.printJsonU64Field("request_bytes", sample.request_bytes);
            self.printJsonU64Field("response_bytes", sample.response_bytes);
            self.printJsonU64Field("payload_copy_bytes", sample.payload_copy_bytes);
            self.printJsonU64Field("payload_clear_bytes", sample.payload_clear_bytes);
            self.printJsonU64Field("queue_full", sample.queue_full);
            self.printJsonU64Field("queue_empty", sample.queue_empty);
            self.printJsonU64Field("admission_waits", sample.admission_waits);
            self.printJsonU64Field("admission_timeouts", sample.admission_timeouts);
            self.printJsonU64Field("recv_buffer_small", sample.recv_buffer_small);
            self.printJsonU64Field("response_search_slots", sample.response_search_slots);
            self.printJsonU64Field("stale_drops", sample.stale_drops);
            self.printJsonU64Field("lock_contentions", sample.lock_contentions);
            self.printJsonU64Field("irq_denied", sample.irq_denied);
            self.printJsonU64Field("queue_used_after", sample.queue_used_after);
            self.sys.println("}");
        }
        if (self.stats.kernel_ipc_sample_count == 0) return;
        self.printKernelIpcMachineDistribution("caller", caller_costs[0..self.stats.kernel_ipc_sample_count]);
        self.printKernelIpcMachineDistribution("handler-queue", queue_costs[0..self.stats.kernel_ipc_sample_count]);
        self.printKernelIpcMachineDistribution("handler-run", run_costs[0..self.stats.kernel_ipc_sample_count]);
        self.printKernelIpcMachineDistribution("handler-e2e", e2e_costs[0..self.stats.kernel_ipc_sample_count]);
    }

    fn printKernelIpcMachineDistribution(self: *App, metric: []const u8, values: []const u64) void {
        const distribution = measurement.summarize(values);
        self.machineLinePrefix("kernel_ipc_distribution");
        self.sys.write(",\"metric\":");
        self.printJsonString(metric);
        self.sys.write(",\"unit\":\"ns/request\"");
        self.printJsonU64Field("count", distribution.count);
        self.printJsonU64Field("min", distribution.minimum);
        self.printJsonU64Field("p50", distribution.p50);
        self.printJsonU64Field("p95", distribution.p95);
        self.printJsonU64Field("p99", distribution.p99);
        self.printJsonU64Field("max", distribution.maximum);
        self.printJsonU64Field("mean", distribution.mean);
        self.sys.println("}");
    }

    fn printDriverWorkMachineResults(self: *App) void {
        if (self.stats.driver_work_sample_count == 0) return;
        var queue_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var run_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var e2e_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var index: usize = 0;
        while (index < self.stats.driver_work_sample_count) : (index += 1) {
            const sample = self.stats.driver_work_samples[index];
            queue_costs[index] = sample.queue_ns_per_started;
            run_costs[index] = sample.run_ns_per_completed;
            e2e_costs[index] = sample.e2e_ns_per_completed;
            self.machineLinePrefix("driver_work_sample");
            self.printJsonU64Field("sample", sample.repetition);
            self.printJsonU64Field("owner", sample.owner);
            self.printJsonU64Field("audio_writes", sample.audio_writes);
            self.printJsonU64Field("audio_bytes", sample.audio_bytes);
            self.printJsonU64Field("submitted", sample.submitted);
            self.printJsonU64Field("submitted_actual_irq", sample.submitted_actual_irq);
            self.printJsonU64Field("submitted_actual_task", sample.submitted_actual_task);
            self.printJsonU64Field("submitted_irq_class", sample.submitted_irq_class);
            self.printJsonU64Field("submitted_task_class", sample.submitted_task_class);
            self.printJsonU64Field("started", sample.started);
            self.printJsonU64Field("completed", sample.completed);
            self.printJsonU64Field("cancelled", sample.cancelled);
            self.printJsonU64Field("failed", sample.failed);
            self.printJsonU64Field("dropped", sample.dropped);
            self.printJsonU64Field("full_rejections", sample.full_rejections);
            self.printJsonU64Field("retained_full_rejections", sample.retained_full_rejections);
            self.printJsonU64Field("releases", sample.releases);
            self.printJsonU64Field("release_busy", sample.release_busy);
            self.printJsonU64Field("release_wakes", sample.release_wakes);
            self.printJsonU64Field("publication_pending_releases", sample.publication_pending_releases);
            self.printJsonU64Field("waiter_blocked_releases", sample.waiter_blocked_releases);
            self.printJsonU64Field("claimed_releases", sample.claimed_releases);
            self.printJsonU64Field("invalid_handles", sample.invalid_handles);
            self.printJsonU64Field("stale_handles", sample.stale_handles);
            self.printJsonU64Field("wait_timeouts", sample.wait_timeouts);
            self.printJsonU64Field("wait_failed", sample.wait_failed);
            self.printJsonU64Field("wake_publications", sample.wake_publications);
            self.printJsonU64Field("wake_waiters", sample.wake_waiters);
            self.printJsonU64Field("wake_misses", sample.wake_misses);
            self.printJsonU64Field("selection_irq", sample.selection_irq);
            self.printJsonU64Field("selection_task", sample.selection_task);
            self.printJsonU64Field("selection_irq_preferred", sample.selection_irq_preferred);
            self.printJsonU64Field("selection_task_fairness", sample.selection_task_fairness);
            self.printJsonU64Field("deadline_submitted", sample.deadline_submitted);
            self.printJsonU64Field("deadline_started", sample.deadline_started);
            self.printJsonU64Field("deadline_completed", sample.deadline_completed);
            self.printJsonU64Field("deadline_misses", sample.deadline_misses);
            self.printJsonU64Field("deadline_budget_overruns", sample.deadline_budget_overruns);
            self.printJsonU64Field("deadline_queue_rejections", sample.deadline_queue_rejections);
            self.printJsonU64Field("deadline_queue_total_ticks", sample.deadline_queue_total_ticks);
            self.printJsonU64Field("deadline_queue_max_ticks_after", sample.deadline_queue_max_ticks_after);
            self.printJsonU64Field("deadline_lateness_total_ticks", sample.deadline_lateness_total_ticks);
            self.printJsonU64Field("deadline_lateness_max_ticks_after", sample.deadline_lateness_max_ticks_after);
            self.printJsonU64Field("queue_total_ns", sample.queue_total_ns);
            self.printJsonU64Field("queue_ns_per_started", sample.queue_ns_per_started);
            self.printJsonU64Field("queue_max_before_ns", sample.queue_max_before_ns);
            self.printJsonU64Field("queue_max_after_ns", sample.queue_max_after_ns);
            self.printJsonU64Field("run_total_ns", sample.run_total_ns);
            self.printJsonU64Field("run_ns_per_completed", sample.run_ns_per_completed);
            self.printJsonU64Field("run_max_before_ns", sample.run_max_before_ns);
            self.printJsonU64Field("run_max_after_ns", sample.run_max_after_ns);
            self.printJsonU64Field("e2e_total_ns", sample.e2e_total_ns);
            self.printJsonU64Field("e2e_ns_per_completed", sample.e2e_ns_per_completed);
            self.printJsonU64Field("e2e_max_before_ns", sample.e2e_max_before_ns);
            self.printJsonU64Field("e2e_max_after_ns", sample.e2e_max_after_ns);
            self.printJsonU64Field("timing_unavailable", sample.timing_unavailable);
            self.printJsonU64Field("completion_age_current_ns_after", sample.completion_age_current_ns_after);
            self.printJsonU64Field("completion_age_max_ns_after", sample.completion_age_max_ns_after);
            self.printJsonU64Field("scan_passes", sample.scan_passes);
            self.printJsonU64Field("scan_slots", sample.scan_slots);
            self.printJsonU64Field("critical_sections", sample.critical_sections);
            self.printJsonU64Field("critical_from_irq", sample.critical_from_irq);
            self.printJsonU64Field("critical_total_ns", sample.critical_total_ns);
            self.printJsonU64Field("critical_max_before_ns", sample.critical_max_before_ns);
            self.printJsonU64Field("critical_max_after_ns", sample.critical_max_after_ns);
            self.printJsonU64Field("critical_timing_samples", sample.critical_timing_samples);
            self.printJsonU64Field("critical_timing_unavailable", sample.critical_timing_unavailable);
            self.printJsonU64Field("waiter_enrollments", sample.waiter_enrollments);
            self.printJsonU64Field("waiter_wake_returns", sample.waiter_wake_returns);
            self.printJsonU64Field("long_callbacks", sample.long_callbacks);
            self.printJsonU64Field("cleanup_calls", sample.cleanup_calls);
            self.printJsonU64Field("cleanup_quiesced", sample.cleanup_quiesced);
            self.printJsonU64Field("cleanup_failed_context", sample.cleanup_failed_context);
            self.printJsonU64Field("cleanup_queued_cancelled", sample.cleanup_queued_cancelled);
            self.printJsonU64Field("cleanup_waits", sample.cleanup_waits);
            self.printJsonU64Field("cleanup_wait_timeouts", sample.cleanup_wait_timeouts);
            self.printJsonU64Field("cleanup_wait_failures", sample.cleanup_wait_failures);
            self.printJsonU64Field("cleanup_released", sample.cleanup_released);
            self.printJsonU64Field("cleanup_late_finishes", sample.cleanup_late_finishes);
            self.printJsonU64Field("cleanup_scan_passes", sample.cleanup_scan_passes);
            self.printJsonU64Field("cleanup_scan_slots", sample.cleanup_scan_slots);
            self.printJsonU64Field("free_slots_after", sample.free_slots_after);
            self.printJsonU64Field("used_slots_after", sample.used_slots_after);
            self.printJsonU64Field("queued_slots_after", sample.queued_slots_after);
            self.printJsonU64Field("running_slots_after", sample.running_slots_after);
            self.printJsonU64Field("completed_slots_after", sample.completed_slots_after);
            self.printJsonU64Field("cancelled_slots_after", sample.cancelled_slots_after);
            self.printJsonU64Field("queue_high_water_after", sample.queue_high_water_after);
            self.printJsonU64Field("used_high_water_after", sample.used_high_water_after);
            self.printJsonU64Field("retained_high_water_after", sample.retained_high_water_after);
            self.printJsonU64Field("waiters_current_after", sample.waiters_current_after);
            self.printJsonU64Field("waiters_max_after", sample.waiters_max_after);
            self.printJsonU64Field("owner_used_slots_after", sample.owner_used_slots_after);
            self.printJsonU64Field("owner_used_high_water_after", sample.owner_used_high_water_after);
            self.printJsonU64Field("owner_retained_high_water_after", sample.owner_retained_high_water_after);
            self.printJsonU64Field("owner_waiters_current_after", sample.owner_waiters_current_after);
            self.printJsonU64Field("owner_waiters_max_after", sample.owner_waiters_max_after);
            self.sys.println("}");
        }
        self.printDriverWorkMachineDistribution("queue", queue_costs[0..self.stats.driver_work_sample_count]);
        self.printDriverWorkMachineDistribution("run", run_costs[0..self.stats.driver_work_sample_count]);
        self.printDriverWorkMachineDistribution("e2e", e2e_costs[0..self.stats.driver_work_sample_count]);
    }

    fn printDriverWorkMachineDistribution(self: *App, metric: []const u8, values: []const u64) void {
        const distribution = measurement.summarize(values);
        self.machineLinePrefix("driver_work_distribution");
        self.sys.write(",\"metric\":");
        self.printJsonString(metric);
        self.sys.write(",\"unit\":\"ns/work\"");
        self.printJsonU64Field("count", distribution.count);
        self.printJsonU64Field("min", distribution.minimum);
        self.printJsonU64Field("p50", distribution.p50);
        self.printJsonU64Field("p95", distribution.p95);
        self.printJsonU64Field("p99", distribution.p99);
        self.printJsonU64Field("max", distribution.maximum);
        self.printJsonU64Field("mean", distribution.mean);
        self.sys.println("}");
    }

    fn printPciInventoryMachineResults(self: *App) void {
        if (self.stats.pci_inventory_sample_count == 0) return;
        var costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var index: usize = 0;
        while (index < self.stats.pci_inventory_sample_count) : (index += 1) {
            const sample = self.stats.pci_inventory_samples[index];
            costs[index] = sample.ns_per_inventory;
            self.machineLinePrefix("pci_inventory_sample");
            self.printJsonU64Field("sample", sample.repetition);
            self.printJsonU64Field("iterations", sample.iterations);
            self.printJsonU64Field("summaries", sample.summaries);
            self.printJsonU64Field("records", sample.records);
            self.printJsonU64Field("api_errors", sample.api_errors);
            self.printJsonU64Field("elapsed_ns", sample.elapsed_ns);
            self.printJsonU64Field("ns_per_inventory", sample.ns_per_inventory);
            self.printJsonU64Field("ecam_read_delta", sample.ecam_read_delta);
            self.printJsonU64Field("ecam_write_delta", sample.ecam_write_delta);
            self.printJsonU64Field("legacy_read_delta", sample.legacy_read_delta);
            self.printJsonU64Field("legacy_write_delta", sample.legacy_write_delta);
            self.printJsonU64Field("mapping_check_delta", sample.mapping_check_delta);
            self.printJsonU64Field("mapping_miss_delta", sample.mapping_miss_delta);
            self.printJsonU64Field("mapping_fast_delta", sample.mapping_fast_delta);
            self.printJsonU64Field("invalid_access_delta", sample.invalid_access_delta);
            self.printJsonU64Field("class_find_delta", sample.class_find_delta);
            self.printJsonU64Field("detail_materialization_delta", sample.detail_materialization_delta);
            self.printJsonU64Field("interrupt_read_delta", sample.interrupt_read_delta);
            self.printJsonU64Field("command_read_delta", sample.command_read_delta);
            self.printJsonU64Field("bar_read_delta", sample.bar_read_delta);
            self.printJsonU64Field("flags", sample.flags);
            self.printJsonU64Field("generation", sample.generation);
            self.printJsonU64Field("capacity", sample.capacity);
            self.printJsonU64Field("found", sample.found);
            self.printJsonU64Field("stored", sample.stored);
            self.printJsonU64Field("dropped", sample.dropped);
            self.printJsonU64Field("ecam_stored", sample.ecam_stored);
            self.printJsonU64Field("legacy_stored", sample.legacy_stored);
            self.printJsonU64Field("vendor_probes_ecam", sample.vendor_probes_ecam);
            self.printJsonU64Field("vendor_probes_legacy", sample.vendor_probes_legacy);
            self.printJsonU64Field("class_reads", sample.class_reads);
            self.printJsonU64Field("header_reads", sample.header_reads);
            self.printJsonU64Field("enumeration_config_reads", sample.enumeration_config_reads);
            self.printJsonU64Field("function_pages", sample.function_pages);
            self.printJsonU64Field("early_stops", sample.early_stops);
            self.printJsonU64Field("ecam_config_reads", sample.ecam_config_reads);
            self.printJsonU64Field("ecam_config_writes", sample.ecam_config_writes);
            self.printJsonU64Field("legacy_config_reads", sample.legacy_config_reads);
            self.printJsonU64Field("legacy_config_writes", sample.legacy_config_writes);
            self.printJsonU64Field("mapping_checks", sample.mapping_checks);
            self.printJsonU64Field("mapping_hits", sample.mapping_hits);
            self.printJsonU64Field("mapping_misses", sample.mapping_misses);
            self.printJsonU64Field("mapping_fast_accesses", sample.mapping_fast_accesses);
            self.printJsonU64Field("invalid_accesses", sample.invalid_accesses);
            self.printJsonU64Field("class_find_calls", sample.class_find_calls);
            self.printJsonU64Field("class_candidates", sample.class_candidates);
            self.printJsonU64Field("detail_materializations", sample.detail_materializations);
            self.printJsonU64Field("interrupt_dword_reads", sample.interrupt_dword_reads);
            self.printJsonU64Field("command_reads", sample.command_reads);
            self.printJsonU64Field("bar_reads", sample.bar_reads);
            self.printJsonU64Field("enumeration_total_ns", sample.enumeration_total_ns);
            self.printJsonU64Field("ecam_enumeration_ns", sample.ecam_enumeration_ns);
            self.printJsonU64Field("legacy_enumeration_ns", sample.legacy_enumeration_ns);
            self.printJsonU64Field("timing_unavailable", sample.timing_unavailable);
            self.printJsonU64Field("checksum", sample.checksum);
            self.sys.println("}");
        }
        const distribution = measurement.summarize(costs[0..self.stats.pci_inventory_sample_count]);
        self.machineLinePrefix("pci_inventory_distribution");
        self.sys.write(",\"unit\":\"ns/inventory\"");
        self.printJsonU64Field("count", distribution.count);
        self.printJsonU64Field("min", distribution.minimum);
        self.printJsonU64Field("p50", distribution.p50);
        self.printJsonU64Field("p95", distribution.p95);
        self.printJsonU64Field("p99", distribution.p99);
        self.printJsonU64Field("max", distribution.maximum);
        self.printJsonU64Field("mean", distribution.mean);
        self.sys.println("}");
    }

    fn printMemoryMetadataMachineResults(self: *App) void {
        if (self.stats.memory_metadata_sample_count == 0) return;
        var reserve_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var fault_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var state_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var reclaim_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var index: usize = 0;
        while (index < self.stats.memory_metadata_sample_count) : (index += 1) {
            const sample = self.stats.memory_metadata_samples[index];
            reserve_costs[index] = sample.reserve_commit_ns_per_page;
            fault_costs[index] = sample.fault_ns_per_page;
            state_costs[index] = sample.page_state_ns_per_page;
            reclaim_costs[index] = sample.reclaim_ns_per_vm_frame;
            self.machineLinePrefix("memory_metadata_sample");
            self.printJsonU64Field("sample", sample.repetition);
            self.printJsonU64Field("pages", sample.pages);
            self.printJsonU64Field("reserve_commit_elapsed_ns", sample.reserve_commit_elapsed_ns);
            self.printJsonU64Field("reserve_commit_ns_per_page", sample.reserve_commit_ns_per_page);
            self.printJsonU64Field("fault_elapsed_ns", sample.fault_elapsed_ns);
            self.printJsonU64Field("fault_ns_per_page", sample.fault_ns_per_page);
            self.printJsonU64Field("page_state_elapsed_ns", sample.page_state_elapsed_ns);
            self.printJsonU64Field("page_state_ns_per_page", sample.page_state_ns_per_page);
            self.printJsonU64Field("reclaim_elapsed_ns", sample.reclaim_elapsed_ns);
            self.printJsonU64Field("reclaim_ns_per_vm_frame", sample.reclaim_ns_per_vm_frame);
            self.printJsonU64Field("reclaim_attempts", sample.reclaim_attempts);
            self.printJsonU64Field("reclaim_requested_frames", sample.reclaim_requested_frames);
            self.printJsonU64Field("reclaim_returned_frames", sample.reclaim_returned_frames);
            self.printJsonU64Field("reclaim_fs_returned_frames", sample.reclaim_fs_returned_frames);
            self.printJsonU64Field("reclaim_vm_returned_frames", sample.reclaim_vm_returned_frames);
            self.printJsonU64Field("reclaim_vm_page_outs", sample.reclaim_vm_page_outs);
            self.printJsonU64Field("reclaim_vm_failures", sample.reclaim_vm_failures);
            self.printJsonU64Field("target_committed_pages", sample.target_committed_pages);
            self.printJsonU64Field("target_resident_pages", sample.target_resident_pages);
            self.printJsonU64Field("target_nonresident_pages", sample.target_nonresident_pages);
            self.printJsonU64Field("target_clean_pages", sample.target_clean_pages);
            self.printJsonU64Field("target_slot_bound_pages", sample.target_slot_bound_pages);
            self.printJsonU64Field("block_physical_index_entries", sample.block_physical_index_entries);
            self.printJsonU64Field("block_physical_step_max", sample.block_physical_step_max);
            self.printJsonU64Field("block_id_index_entries", sample.block_id_index_entries);
            self.printJsonU64Field("block_id_step_max", sample.block_id_step_max);
            self.printJsonU64Field("block_free_slot_word_step_max", sample.block_free_slot_word_step_max);
            self.printJsonU64Field("range_address_entries", sample.range_address_entries);
            self.printJsonU64Field("range_address_probe_max", sample.range_address_probe_max);
            self.printJsonU64Field("commit_span_active", sample.commit_span_active);
            self.printJsonU64Field("commit_span_step_max", sample.commit_span_step_max);
            self.printJsonU64Field("page_state_span_active", sample.page_state_span_active);
            self.printJsonU64Field("page_state_span_step_max", sample.page_state_span_step_max);
            self.printJsonU64Field("block_physical_lookups", sample.block_physical_lookups);
            self.printJsonU64Field("block_physical_steps", sample.block_physical_steps);
            self.printJsonU64Field("block_physical_mutations", sample.block_physical_mutations);
            self.printJsonU64Field("block_physical_rebuilds", sample.block_physical_rebuilds);
            self.printJsonU64Field("block_id_lookups", sample.block_id_lookups);
            self.printJsonU64Field("block_id_steps", sample.block_id_steps);
            self.printJsonU64Field("block_free_slot_lookups", sample.block_free_slot_lookups);
            self.printJsonU64Field("block_free_slot_word_steps", sample.block_free_slot_word_steps);
            self.printJsonU64Field("block_claim_transactions", sample.block_claim_transactions);
            self.printJsonU64Field("block_claim_rollbacks", sample.block_claim_rollbacks);
            self.printJsonU64Field("range_address_lookups", sample.range_address_lookups);
            self.printJsonU64Field("range_address_probes", sample.range_address_probes);
            self.printJsonU64Field("commit_span_lookups", sample.commit_span_lookups);
            self.printJsonU64Field("commit_span_steps", sample.commit_span_steps);
            self.printJsonU64Field("page_state_span_lookups", sample.page_state_span_lookups);
            self.printJsonU64Field("page_state_span_steps", sample.page_state_span_steps);
            self.printJsonU64Field("reclaim_range_steps", sample.reclaim_range_steps);
            self.printJsonU64Field("reclaim_span_steps", sample.reclaim_span_steps);
            self.printJsonU64Field("reclaim_page_steps", sample.reclaim_page_steps);
            self.printJsonU64Field("reclaim_wraps", sample.reclaim_wraps);
            self.sys.println("}");
        }
        self.printMemoryMetadataMachineDistribution("reserve-commit", "ns/page", reserve_costs[0..self.stats.memory_metadata_sample_count]);
        self.printMemoryMetadataMachineDistribution("fault", "ns/page", fault_costs[0..self.stats.memory_metadata_sample_count]);
        self.printMemoryMetadataMachineDistribution("page-state", "ns/page", state_costs[0..self.stats.memory_metadata_sample_count]);
        self.printMemoryMetadataMachineDistribution("reclaim", "ns/frame", reclaim_costs[0..self.stats.memory_metadata_sample_count]);
    }

    fn printMemoryMetadataMachineDistribution(self: *App, metric: []const u8, unit: []const u8, values: []const u64) void {
        const distribution = measurement.summarize(values);
        self.machineLinePrefix("memory_metadata_distribution");
        self.sys.write(",\"metric\":");
        self.printJsonString(metric);
        self.sys.write(",\"unit\":");
        self.printJsonString(unit);
        self.printJsonU64Field("count", distribution.count);
        self.printJsonU64Field("min", distribution.minimum);
        self.printJsonU64Field("p50", distribution.p50);
        self.printJsonU64Field("p95", distribution.p95);
        self.printJsonU64Field("p99", distribution.p99);
        self.printJsonU64Field("max", distribution.maximum);
        self.printJsonU64Field("mean", distribution.mean);
        self.sys.println("}");
    }

    fn printJsonU64Field(self: *App, name: []const u8, value: u64) void {
        self.sys.write(",\"");
        self.sys.write(name);
        self.sys.write("\":");
        self.sys.printU64(value);
    }

    fn machineLinePrefix(self: *App, event_type: []const u8) void {
        self.sys.write("{\"schema\":");
        self.printJsonString(measurement.result_schema);
        self.sys.write(",\"schema_version\":");
        self.sys.printU64(measurement.result_schema_version);
        self.sys.write(",\"type\":");
        self.printJsonString(event_type);
    }

    fn printJsonString(self: *App, value: []const u8) void {
        self.sys.putc('"');
        for (value) |ch| {
            switch (ch) {
                '"' => self.sys.write("\\\""),
                '\\' => self.sys.write("\\\\"),
                '\n' => self.sys.write("\\n"),
                '\r' => self.sys.write("\\r"),
                '\t' => self.sys.write("\\t"),
                0...8, 11...12, 14...31 => self.sys.putc('?'),
                else => self.sys.putc(ch),
            }
        }
        self.sys.putc('"');
    }

    fn printJsonBool(self: *App, value: bool) void {
        self.sys.write(if (value) "true" else "false");
    }

    fn testApiHeader(self: *App) bool {
        const ok = self.sys.contractValid() and
            self.sys.hasFn("monotonic_clock") and
            self.dev.hasFn("performance_summary") and
            self.dev.hasFn("performance_boot_phase_clock") and
            self.dev.hasFn("performance_irq_timing") and
            self.dev.hasFn("performance_driver_work") and
            self.dev.hasFn("performance_pci_inventory") and
            self.dev.hasFn("memory_reclaim_probe") and
            self.dev.hasFn("memory_backing_store_probe") and
            self.dev.hasFn("memory_backing_store_slot_probe") and
            self.dev.hasFn("memory_pager_gate_probe") and
            self.dev.hasFn("memory_page_io_probe") and
            self.dev.hasFn("memory_vm_page_state_probe") and
            self.dev.hasFn("memory_pressure_snapshot");
        self.printCheck("R4SYS/R4DEV performance clock API", ok);
        if (!ok) return false;
        self.sys.write("  API version=");
        self.sys.printU64(self.sys.tableAbiVersion());
        self.sys.write(" size=");
        self.sys.printU64(self.sys.tableSize());
        self.sys.println("");
        return true;
    }

    fn testPciInventorySnapshot(self: *App) bool {
        const snapshot = self.dev.performancePciInventory() orelse {
            self.printCheck("Canonical PCI inventory snapshot", false);
            return false;
        };
        const ok = pciInventorySnapshotContractOk(snapshot);
        self.printCheck("Canonical PCI inventory snapshot", ok);
        self.sys.write("  PCI found/stored/dropped=");
        self.sys.printU64(snapshot.found);
        self.sys.write("/");
        self.sys.printU64(snapshot.stored);
        self.sys.write("/");
        self.sys.printU64(snapshot.dropped);
        self.sys.write(" probes(ecam/legacy)=");
        self.sys.printU64(snapshot.vendor_probes_ecam);
        self.sys.write("/");
        self.sys.printU64(snapshot.vendor_probes_legacy);
        self.sys.write(" map(check/hit/miss)=");
        self.sys.printU64(snapshot.mapping_checks);
        self.sys.write("/");
        self.sys.printU64(snapshot.mapping_hits);
        self.sys.write("/");
        self.sys.printU64(snapshot.mapping_misses);
        self.sys.println("");
        self.sys.write("  PCI flags/generation/capacity=");
        self.sys.printU64(snapshot.flags);
        self.sys.write("/");
        self.sys.printU64(snapshot.generation);
        self.sys.write("/");
        self.sys.printU64(snapshot.capacity);
        self.sys.write(" stored(ecam/legacy)=");
        self.sys.printU64(snapshot.ecam_stored);
        self.sys.write("/");
        self.sys.printU64(snapshot.legacy_stored);
        self.sys.println("");
        self.sys.write("  PCI reads(enum/class/header/pages)=");
        self.sys.printU64(snapshot.enumeration_config_reads);
        self.sys.write("/");
        self.sys.printU64(snapshot.class_reads);
        self.sys.write("/");
        self.sys.printU64(snapshot.header_reads);
        self.sys.write("/");
        self.sys.printU64(snapshot.function_pages);
        self.sys.write(" config(ecam-r/ecam-w/legacy-r/legacy-w)=");
        self.sys.printU64(snapshot.ecam_config_reads);
        self.sys.write("/");
        self.sys.printU64(snapshot.ecam_config_writes);
        self.sys.write("/");
        self.sys.printU64(snapshot.legacy_config_reads);
        self.sys.write("/");
        self.sys.printU64(snapshot.legacy_config_writes);
        self.sys.println("");
        self.sys.write("  PCI map-fast/invalid=");
        self.sys.printU64(snapshot.mapping_fast_accesses);
        self.sys.write("/");
        self.sys.printU64(snapshot.invalid_accesses);
        self.sys.write(" detail(find/candidates/materialized/irq/cmd/bar)=");
        self.sys.printU64(snapshot.class_find_calls);
        self.sys.write("/");
        self.sys.printU64(snapshot.class_candidates);
        self.sys.write("/");
        self.sys.printU64(snapshot.detail_materializations);
        self.sys.write("/");
        self.sys.printU64(snapshot.interrupt_dword_reads);
        self.sys.write("/");
        self.sys.printU64(snapshot.command_reads);
        self.sys.write("/");
        self.sys.printU64(snapshot.bar_reads);
        self.sys.println("");
        self.sys.write("  PCI timing(total/ecam/legacy/unavailable)=");
        self.sys.printU64(snapshot.enumeration_total_ns);
        self.sys.write("/");
        self.sys.printU64(snapshot.ecam_enumeration_ns);
        self.sys.write("/");
        self.sys.printU64(snapshot.legacy_enumeration_ns);
        self.sys.write("/");
        self.sys.printU64(snapshot.timing_unavailable);
        self.sys.println("");
        return ok;
    }

    fn testMonotonicClock(self: *App) bool {
        var first: r4os.abi.MonotonicClockInfo = .{};
        var second: r4os.abi.MonotonicClockInfo = .{};
        const first_ok = self.queryMonotonicClock(&first);
        const second_ok = self.queryMonotonicClock(&second);
        const required_flags = r4os.abi.monotonic_clock_flag_valid |
            r4os.abi.monotonic_clock_flag_continuous;
        const contract_ok = first_ok and second_ok and
            first.version == 1 and
            first.size >= @sizeOf(r4os.abi.MonotonicClockInfo) and
            (first.flags & required_flags) == required_flags and
            first.source != r4os.abi.monotonic_clock_source_unavailable and
            first.frequency_hz == r4os.abi.monotonic_clock_frequency_hz and
            first.resolution_ns > 0 and
            first.source_frequency_hz > 0 and
            first.event_frequency_numerator > 0 and
            first.event_frequency_denominator > 0 and
            first.event_requested_hz > 0 and
            first.event_effective_hz > 0 and
            second.generation == first.generation and
            second.instant_ns >= first.instant_ns;
        self.printCheck("Monotonic clock contract", contract_ok);
        if (!contract_ok) return false;

        const high_resolution = (first.flags & r4os.abi.monotonic_clock_flag_high_resolution) != 0;
        const irq_independent = (first.flags & r4os.abi.monotonic_clock_flag_irq_independent) != 0;
        const degraded = (first.flags & r4os.abi.monotonic_clock_flag_degraded) != 0;
        const quality_ok = (high_resolution and irq_independent and !degraded) or degraded;
        self.printCheck("Monotonic clock quality is explicit", quality_ok);
        if (!quality_ok) return false;

        self.monotonic_clock = second;
        self.monotonic_clock_available = true;
        self.sys.write("  Clock instantNs=");
        self.sys.printU64(second.instant_ns);
        self.sys.write(" sourceHz=");
        self.sys.printU64(second.source_frequency_hz);
        self.sys.write(" eventRate=");
        self.sys.printU64(second.event_frequency_numerator);
        self.sys.write("/");
        self.sys.printU64(second.event_frequency_denominator);
        self.sys.println("");
        return true;
    }

    fn testSummary(self: *App, summary: r4os.abi.ProgramPerformanceSummary) bool {
        const flags_ok =
            (summary.flags & r4os.abi.performance_flag_scheduler_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_boot_perf_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_wait_objects_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_lock_diagnostics_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_storage_request_queue_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_fs_request_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_service_queue_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_preemption_readiness_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_fpu_state_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_fs_page_cache_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_fs_writeback_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_fs_reclaim_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_fs_pmm_reclaim_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_global_reclaim_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_memory_backing_store_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_memory_backing_store_slots_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_memory_pager_gates_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_memory_page_io_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_memory_vm_page_state_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_memory_eviction_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_memory_pager_error_policy_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_productive_preemption_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_scheduler_latency_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_avx_state_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_driver_workqueue_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_storage_driver_completion_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_display_responsiveness_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_audio_latency_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_loader_performance_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_hot_path_index_ready) != 0 and
            (summary.flags & r4os.abi.performance_flag_loader_memory_ready) != 0;
        const wait_missing_ok = (summary.missing_flags & (r4os.abi.performance_missing_blocked_object |
            r4os.abi.performance_missing_wait_latency_histogram |
            r4os.abi.performance_missing_preemption_latency_histogram)) == 0;
        const lock_ok = summary.lock_sleep_checks > 0 and
            summary.lock_order_violations == 0 and
            summary.lock_sleep_under_no_sleep_lock == 0 and
            summary.lock_unlock_mismatches == 0 and
            summary.lock_tracking_drops == 0;
        const service_completion_ok = summary.service_completion_waits > 0 and
            summary.service_completion_wait_rounds == summary.service_completion_waits and
            summary.service_targeted_response_wakes + summary.service_targeted_response_wake_misses == summary.service_responses and
            summary.service_completion_timeouts <= summary.service_timeouts and
            summary.service_admission_timeouts <= summary.service_timeouts and
            summary.service_cancellations <= summary.service_drops;
        const service_payload_ok = summary.service_payload_copy_bytes > 0 and
            summary.service_payload_clear_bytes == 0 and
            summary.service_slot_metadata_resets > 0 and
            summary.service_endpoint_metadata_resets > 0 and
            summary.service_endpoint_payload_reset_bytes == 0;
        var service_lock_ok = summary.service_lock_family_count == 7 and
            summary.service_lock_timing_stride > 0 and
            summary.service_lock_timing_reserved0 == 0 and
            summary.service_queue_scan_passes > 0 and
            summary.service_queue_scan_slots >= summary.service_queue_scan_passes and
            summary.service_queue_scan_slots <= summary.service_queue_scan_passes * 8 and
            summary.service_endpoint_revalidations > 0;
        var service_lock_family: usize = 0;
        while (service_lock_family < summary.service_lock_acquisitions.len) : (service_lock_family += 1) {
            service_lock_ok = service_lock_ok and
                summary.service_lock_acquisitions[service_lock_family] > 0 and
                summary.service_lock_timing_samples[service_lock_family] > 0 and
                summary.service_lock_timing_samples[service_lock_family] <= summary.service_lock_acquisitions[service_lock_family] and
                summary.service_lock_wait_max_ns[service_lock_family] <= summary.service_lock_wait_ns[service_lock_family] and
                summary.service_lock_hold_max_ns[service_lock_family] <= summary.service_lock_hold_ns[service_lock_family] and
                summary.service_lock_timing_unavailable[service_lock_family] <= summary.service_lock_timing_samples[service_lock_family] * 2;
        }
        const display_responsiveness_ok = summary.display_present_count > 0 and
            summary.display_present_bytes_total > 0 and
            summary.display_present_max_ticks >= summary.display_present_last_ticks and
            summary.display_present_total_ticks >= summary.display_present_last_ticks;
        const audio_latency_ok = summary.audio_stream_writes > 0 and
            summary.audio_stream_high_water_bytes > 0 and
            summary.audio_stream_write_max_ticks >= summary.audio_stream_write_last_ticks and
            summary.audio_stream_write_total_ticks >= summary.audio_stream_write_last_ticks and
            summary.audio_backend_write_max_ticks >= summary.audio_backend_write_last_ticks and
            summary.audio_backend_write_total_ticks >= summary.audio_backend_write_last_ticks and
            summary.audio_backend_refill_max_ticks >= summary.audio_backend_refill_last_ticks and
            summary.audio_backend_refill_total_ticks >= summary.audio_backend_refill_last_ticks and
            summary.audio_stream_dropped_bytes == 0;
        const loader_perf_ok = summary.loader_initialized != 0 and
            summary.loader_started != 0 and
            summary.loader_completed != 0 and
            summary.loader_r4p_runtime_started != 0 and
            summary.loader_r4p_runtime_completed != 0 and
            summary.loader_r4l_candidates > 0 and
            summary.loader_r4l_loaded > 0 and
            summary.loader_r4d_candidates > 0 and
            summary.loader_r4d_discovered > 0 and
            summary.loader_r4p_candidates > 0 and
            summary.loader_r4p_active > 0 and
            summary.loader_r4p_blocked > 0 and
            summary.loader_config_bytes > 0 and
            summary.loader_config_driver_count > 0 and
            summary.loader_service_boot_status == r4os.abi.loader_service_boot_status_ran and
            summary.loader_boot_critical_count > 0 and
            summary.loader_lazy_candidate_count > 0;
        const loader_memory_ok = summary.loader_file_active_buffers == 0 and
            summary.loader_file_reserved_bytes == 0 and
            summary.loader_file_committed_bytes == 0 and
            summary.loader_file_range_reads > 0 and
            summary.loader_file_range_read_bytes > 0 and
            summary.loader_file_full_reads == 0 and
            summary.loader_metadata_reader_initializations > 0 and
            summary.loader_metadata_logical_reads > summary.loader_metadata_window_fills and
            summary.loader_metadata_window_hits > 0 and
            summary.loader_metadata_window_fills > 0 and
            summary.loader_metadata_window_fill_bytes > 0 and
            summary.loader_file_range_read_bytes >= summary.loader_metadata_window_fill_bytes and
            summary.loader_metadata_window_capacity_bytes == 8 * 1024 and
            summary.loader_file_peak_reserved_bytes >= summary.loader_file_peak_committed_bytes and
            summary.loader_file_reserve_failures == 0 and
            summary.loader_file_commit_failures == 0 and
            summary.loader_file_read_failures == 0 and
            summary.loader_file_short_reads == 0 and
            summary.loader_file_release_failures == 0 and
            summary.loader_file_pressure_failures == 0;
        const hot_path_ok = summary.hot_path_vm_range_index_capacity >= 2048 and
            summary.hot_path_vm_range_index_entries > 0 and
            summary.hot_path_vm_range_index_entries <= summary.hot_path_vm_range_index_capacity and
            summary.hot_path_vm_range_index_lookups > 0 and
            summary.hot_path_vm_range_index_hits > 0 and
            summary.hot_path_vm_range_index_probe_total >= summary.hot_path_vm_range_index_lookups and
            summary.hot_path_vm_range_index_probe_max >= summary.hot_path_vm_range_index_probe_last and
            summary.hot_path_vm_range_index_insert_failures == 0 and
            summary.hot_path_vm_range_free_slot_lookups > 0 and
            summary.hot_path_vm_range_free_slot_probe_total >= summary.hot_path_vm_range_free_slot_lookups and
            summary.hot_path_vm_range_free_slot_probe_max >= summary.hot_path_vm_range_free_slot_probe_last and
            summary.hot_path_memory_block_physical_index_entries > 0 and
            summary.hot_path_memory_block_physical_step_max > 0 and summary.hot_path_memory_block_physical_step_max <= 32 and
            summary.hot_path_memory_block_id_index_entries > 0 and
            summary.hot_path_memory_block_id_step_max > 0 and summary.hot_path_memory_block_id_step_max <= 128 and
            summary.hot_path_memory_block_free_slot_word_step_max > 0 and summary.hot_path_memory_block_free_slot_word_step_max <= 128 and
            summary.hot_path_memory_block_physical_lookups > 0 and
            summary.hot_path_memory_block_physical_steps >= summary.hot_path_memory_block_physical_lookups and
            summary.hot_path_memory_block_physical_mutations > 0 and
            summary.hot_path_memory_block_physical_rebuilds == 0 and
            summary.hot_path_memory_block_id_lookups > 0 and
            summary.hot_path_memory_block_id_steps >= summary.hot_path_memory_block_id_lookups and
            summary.hot_path_memory_block_free_slot_lookups > 0 and
            summary.hot_path_memory_block_free_slot_word_steps >= summary.hot_path_memory_block_free_slot_lookups and
            summary.hot_path_memory_block_claim_transactions > 0 and
            summary.hot_path_memory_block_claim_rollbacks == 0 and
            summary.hot_path_memory_vm_range_address_entries > 0 and
            summary.hot_path_memory_vm_range_address_probe_max >= summary.hot_path_memory_vm_range_address_probe_last and
            summary.hot_path_memory_vm_range_address_probe_max <= 16 and
            summary.hot_path_memory_vm_range_address_lookups > 0 and
            summary.hot_path_memory_vm_range_address_probe_total >= summary.hot_path_memory_vm_range_address_lookups and
            summary.hot_path_memory_vm_commit_span_active > 0 and
            summary.hot_path_memory_vm_commit_span_step_max > 0 and summary.hot_path_memory_vm_commit_span_step_max <= 64 and
            summary.hot_path_memory_vm_commit_span_lookups > 0 and summary.hot_path_memory_vm_commit_span_steps > 0 and
            summary.hot_path_memory_vm_page_state_span_active > 0 and
            summary.hot_path_memory_vm_page_state_span_step_max > 0 and summary.hot_path_memory_vm_page_state_span_step_max <= 64 and
            summary.hot_path_memory_vm_page_state_span_lookups > 0 and summary.hot_path_memory_vm_page_state_span_steps > 0 and
            summary.hot_path_memory_vm_reclaim_range_steps > 0 and
            summary.hot_path_memory_vm_reclaim_span_steps > 0 and
            summary.hot_path_memory_vm_reclaim_page_steps > 0 and
            summary.hot_path_bounded_block_device_scan_max >= summary.storage_device_count and
            summary.hot_path_bounded_block_device_scan_max <= 8 and
            summary.hot_path_bounded_tcp_connection_scan_max == summary.tcp_max_connections;
        const page_io_last_is_diagnostic_in = summary.memory_page_io_status == r4os.abi.memory_page_io_status_page_in_ok and
            pageIoFlagsOk(summary.memory_page_io_flags, r4os.abi.memory_page_io_operation_page_in) and
            summary.memory_page_io_owner_kind == r4os.abi.memory_backing_store_slot_owner_kind_diagnostic and
            summary.memory_page_io_owner_id == backing_store_slot_owner;
        const page_io_last_is_vm_region_out = summary.memory_page_io_status == r4os.abi.memory_page_io_status_page_out_ok and
            pageIoFlagsOk(summary.memory_page_io_flags, r4os.abi.memory_page_io_operation_page_out) and
            summary.memory_page_io_owner_kind == r4os.abi.memory_backing_store_slot_owner_kind_vm_region and
            summary.memory_page_io_region_id != 0 and
            summary.memory_page_io_owner_id != 0;
        const page_io_last_is_vm_region_in = summary.memory_page_io_status == r4os.abi.memory_page_io_status_page_in_ok and
            pageIoFlagsOk(summary.memory_page_io_flags, r4os.abi.memory_page_io_operation_page_in) and
            summary.memory_page_io_owner_kind == r4os.abi.memory_backing_store_slot_owner_kind_vm_region and
            summary.memory_page_io_region_id != 0 and
            summary.memory_page_io_owner_id != 0;
        const page_io_last_ok = page_io_last_is_diagnostic_in or page_io_last_is_vm_region_out or page_io_last_is_vm_region_in;
        const page_io_valid_slots_ok = if (page_io_last_is_diagnostic_in)
            summary.memory_page_io_valid_slots >= 2
        else
            summary.memory_page_io_valid_slots <= summary.memory_page_io_capacity_slots;
        const page_io_shape_ok = if (page_io_last_is_diagnostic_in)
            summary.memory_page_io_io_bytes == 8192 and
                summary.memory_page_io_io_status == 8192 and
                summary.memory_page_io_page_count == 2 and
                summary.memory_page_io_transfer_bytes == 8192 and
                summary.memory_page_io_region_offset == 0
        else
            summary.memory_page_io_page_count > 0 and
                summary.memory_page_io_io_bytes == summary.memory_page_io_page_count * 4096 and
                summary.memory_page_io_io_bytes <= 0x7fff_ffff and
                summary.memory_page_io_io_status == @as(i32, @intCast(summary.memory_page_io_io_bytes)) and
                summary.memory_page_io_transfer_bytes == summary.memory_page_io_io_bytes and
                summary.memory_page_io_region_offset % 4096 == 0;
        const slot_last_owner_ok =
            (summary.memory_backing_store_slot_last_owner_kind == r4os.abi.memory_backing_store_slot_owner_kind_diagnostic and
                summary.memory_backing_store_slot_last_owner_id == backing_store_slot_owner and
                summary.memory_backing_store_slot_last_region_id == 0) or
            (summary.memory_backing_store_slot_last_owner_kind == r4os.abi.memory_backing_store_slot_owner_kind_vm_region and
                summary.memory_backing_store_slot_last_owner_id != 0 and
                summary.memory_backing_store_slot_last_region_id != 0);
        const slot_last_operation_ok =
            (summary.memory_backing_store_slot_status == r4os.abi.memory_backing_store_slot_status_ready and
                summary.memory_backing_store_slot_operation == r4os.abi.memory_backing_store_slot_operation_probe) or
            (summary.memory_backing_store_slot_status == r4os.abi.memory_backing_store_slot_status_reserved and
                summary.memory_backing_store_slot_operation == r4os.abi.memory_backing_store_slot_operation_reserve) or
            (summary.memory_backing_store_slot_status == r4os.abi.memory_backing_store_slot_status_released and
                summary.memory_backing_store_slot_operation == r4os.abi.memory_backing_store_slot_operation_release);
        const storage_dispatch_ok = summary.fs_drive_gate_count == 26 and
            summary.fs_active_requests <= summary.fs_parallel_active_max and
            summary.fs_parallel_active_max > 0 and
            summary.storage_controller_count > 0 and
            summary.storage_worker_count == summary.storage_controller_count and
            summary.storage_worker_parallel_active <= summary.storage_worker_parallel_active_max and
            summary.storage_worker_parallel_active_max > 0 and
            summary.storage_dispatch_reserved0 == 0 and
            summary.fs_single_drive_requests > 0 and
            summary.storage_worker_start_failures == 0 and
            summary.storage_direct_requests > 0 and
            summary.storage_direct_bytes > 0 and
            summary.storage_bounce_allocations == 0 and
            summary.storage_bounce_bytes == 0 and
            summary.storage_bounce_copy_bytes == 0 and
            summary.storage_direct_timeout_waits == 0 and
            summary.fs_cache_bulk_write_requests <= summary.fs_cache_bulk_write_sectors / 2 and
            summary.fs_cache_selective_flushes <= summary.fs_cache_flushes and
            summary.fs_cache_selective_writeback_sectors <= summary.fs_cache_writeback_sectors;
        const cache_policy_ok = summary.fs_cache_policy_version == 2 and
            summary.fs_cache_policy_device_capacity > 0 and
            summary.fs_cache_policy_device_capacity <= 8 and
            summary.fs_cache_policy_dirty_low_pages > 0 and
            summary.fs_cache_policy_dirty_high_pages > summary.fs_cache_policy_dirty_low_pages and
            summary.fs_cache_policy_dirty_high_pages <= summary.fs_cache_capacity and
            summary.fs_cache_policy_max_dirty_age_ticks > 0 and
            summary.fs_cache_policy_background_page_budget > 0 and
            summary.fs_cache_policy_background_page_budget <= summary.fs_cache_policy_dirty_low_pages and
            summary.fs_cache_policy_worker_started == 1 and
            summary.fs_cache_policy_worker_task_id != 0 and
            summary.fs_cache_policy_device_dirty_high_water <= summary.fs_cache_capacity and
            summary.fs_cache_policy_background_errors == 0 and
            summary.fs_cache_policy_full_scan_fallbacks == 0 and
            summary.fs_cache_read_ahead_hits <= summary.fs_cache_read_ahead_issued and
            summary.fs_cache_capacity_min_pages == 64 and
            summary.fs_cache_capacity_max_pages == 512 and
            summary.fs_cache_capacity_ram_limit_pages >= summary.fs_cache_capacity_min_pages and
            summary.fs_cache_capacity_ram_limit_pages <= summary.fs_cache_capacity_max_pages and
            summary.fs_cache_capacity_active_limit_pages >= summary.fs_cache_capacity_min_pages and
            summary.fs_cache_capacity_active_limit_pages <= summary.fs_cache_capacity_ram_limit_pages and
            summary.fs_cache_capacity_pressure_level <= 3 and
            summary.fs_cache_read_ahead_window_pages == 0 and
            summary.fs_cache_read_ahead_window_max_pages == 0 and
            summary.fs_cache_read_ahead_requests == 0 and
            summary.fs_cache_read_ahead_issued == 0 and
            summary.fs_cache_capacity_reserved0 == 0 and
            summary.fs_cache_fill_run_pages >= summary.fs_cache_fill_run_requests * 2 and
            summary.fs_cache_fill_run_backend_requests == summary.fs_cache_fill_run_requests + summary.fs_cache_fill_run_retries and
            summary.fs_cache_fill_run_sectors >= summary.fs_cache_fill_run_pages and
            summary.fs_cache_fill_run_bytes == summary.fs_cache_fill_run_sectors * 512 and
            summary.fs_cache_fill_run_failures <= summary.fs_cache_fill_run_requests and
            summary.fs_cache_fill_run_max_pages <= 2 and
            summary.fs_cache_fill_scatter_copy_bytes <= summary.fs_cache_fill_run_bytes and
            summary.fs_cache_read_staging_copy_bytes == summary.fs_cache_read_caller_copy_bytes and
            summary.fs_cache_fill_lock_drops == summary.fs_cache_fill_run_requests and
            summary.fs_cache_read_ahead_pages_issued == summary.fs_cache_read_ahead_issued and
            summary.fs_cache_read_ahead_pages_scheduled >= summary.fs_cache_read_ahead_pages_issued;
        const ntfs_active_volumes: u64 = summary.ntfs_metadata_cache_active_volumes;
        const ntfs_capacity_sum = summary.ntfs_metadata_record_capacity +
            summary.ntfs_metadata_attribute_capacity +
            summary.ntfs_metadata_index_capacity +
            summary.ntfs_metadata_path_capacity;
        const ntfs_mutation_invalidated_entries = summary.ntfs_metadata_mutation_invalidated_record_entries +%
            summary.ntfs_metadata_mutation_invalidated_attribute_entries +%
            summary.ntfs_metadata_mutation_invalidated_index_entries +%
            summary.ntfs_metadata_mutation_invalidated_path_entries;
        const ntfs_metadata_cache_ok = summary.ntfs_metadata_cache_version == 2 and
            summary.ntfs_metadata_cache_active_volumes > 0 and
            summary.ntfs_metadata_cache_bytes_per_volume > 0 and
            summary.ntfs_metadata_cache_slot_capacity == 22 and
            summary.ntfs_metadata_cache_slot_capacity == ntfs_capacity_sum and
            summary.ntfs_metadata_record_capacity == 8 and
            summary.ntfs_metadata_attribute_capacity == 4 and
            summary.ntfs_metadata_index_capacity == 2 and
            summary.ntfs_metadata_path_capacity == 8 and
            summary.ntfs_metadata_record_entries <= ntfs_active_volumes * summary.ntfs_metadata_record_capacity and
            summary.ntfs_metadata_attribute_entries <= ntfs_active_volumes * summary.ntfs_metadata_attribute_capacity and
            summary.ntfs_metadata_index_entries <= ntfs_active_volumes * summary.ntfs_metadata_index_capacity and
            summary.ntfs_metadata_path_entries <= ntfs_active_volumes * summary.ntfs_metadata_path_capacity and
            summary.ntfs_metadata_mount_generation > 0 and
            summary.ntfs_metadata_content_generation >= summary.ntfs_metadata_mount_generation and
            summary.ntfs_metadata_negative_ttl_ticks > 0 and
            summary.ntfs_metadata_path_queries == summary.ntfs_metadata_path_positive_hits +%
                summary.ntfs_metadata_path_negative_hits +% summary.ntfs_metadata_path_misses and
            summary.ntfs_metadata_path_positive_stores +% summary.ntfs_metadata_path_negative_stores <=
                summary.ntfs_metadata_path_misses and
            summary.ntfs_metadata_mount_invalidations >= summary.ntfs_metadata_cache_active_volumes and
            summary.ntfs_metadata_payload_write_retentions > 0 and
            summary.ntfs_metadata_system_write_retentions > 0 and
            summary.ntfs_metadata_targeted_invalidations > 0 and
            summary.ntfs_metadata_targeted_invalidations ==
                summary.ntfs_metadata_targeted_record_invalidations +%
                    summary.ntfs_metadata_targeted_attribute_invalidations +%
                    summary.ntfs_metadata_targeted_directory_invalidations and
            summary.ntfs_metadata_global_mutation_invalidations >= summary.ntfs_metadata_recovery_invalidations and
            summary.ntfs_metadata_mutation_invalidations > 0 and
            summary.ntfs_metadata_invalidated_entries > 0 and
            ntfs_mutation_invalidated_entries > 0 and
            ntfs_mutation_invalidated_entries <= summary.ntfs_metadata_invalidated_entries and
            summary.ntfs_metadata_reclaim_requests > 0 and
            summary.ntfs_metadata_reclaim_scans > 0 and
            summary.ntfs_metadata_reclaim_scans <= summary.ntfs_metadata_reclaim_requests * 22 and
            summary.ntfs_metadata_reclaimed_entries > 0 and
            summary.ntfs_metadata_reclaimed_entries <= summary.ntfs_metadata_reclaim_scans;
        const legacy_snapshot_ok = summary.version == r4os.abi.performance_snapshot_version and
            summary.size >= @sizeOf(r4os.abi.ProgramPerformanceSummary) and
            summary.tick_hz > 0 and
            summary.task_count > 0 and
            summary.task_max_count >= summary.task_count and
            summary.boot_phase_count > 0 and
            summary.storage_device_count > 0 and
            summary.service_max_count > 0 and
            summary.tcp_max_connections > 0 and
            summary.wait_object_waits > 0 and
            summary.wait_object_timeouts > 0 and
            summary.wait_queue_waits > 0 and
            summary.wait_queue_timeouts > 0 and
            summary.storage_queued_requests > 0 and
            summary.storage_dequeued_requests > 0 and
            summary.storage_completion_waits > 0 and
            summary.storage_completion_timeouts == 0 and
            summary.storage_queue_high_water_total > 0 and
            summary.storage_worker_started != 0 and
            summary.storage_worker_runtime_requests > 0 and
            summary.storage_worker_runtime_completions > 0 and
            summary.storage_completion_signals > 0 and
            summary.storage_boot_inline_requests > 0 and
            summary.fs_requests > 0 and
            summary.fs_completed > 0 and
            summary.fs_read_requests > 0 and
            summary.fs_lock_acquires > 0 and
            summary.fs_lock_timeouts == 0 and
            summary.fs_cache_capacity > 0 and
            summary.fs_cache_sector_bytes == 512 and
            summary.fs_cache_entries_used > 0 and
            summary.fs_cache_reads > 0 and
            summary.fs_cache_hits > 0 and
            summary.fs_cache_misses > 0 and
            summary.fs_cache_dirty_entries <= summary.fs_cache_entries_used and
            summary.fs_cache_dirty_bytes <= summary.fs_cache_payload_bytes and
            summary.fs_cache_writeback_queue_depth <= summary.fs_cache_writeback_queue_high_water and
            summary.fs_cache_writeback_queue_high_water > 0 and
            summary.fs_cache_deferred_write_requests > 0 and
            summary.fs_cache_writeback_drains > 0 and
            summary.fs_cache_writeback_sectors > 0 and
            summary.fs_cache_writeback_flush_drains > 0 and
            summary.fs_cache_clean_reclaimable_entries > 0 and
            summary.fs_cache_clean_reclaimable_bytes > 0 and
            summary.fs_cache_payload_frame_bytes >= 4096 and
            summary.fs_cache_payload_frames >= summary.fs_cache_entries_used and
            summary.fs_cache_payload_bytes >= summary.fs_cache_clean_reclaimable_bytes and
            summary.fs_cache_pmm_reclaimable_bytes >= summary.fs_cache_clean_reclaimable_bytes and
            summary.fs_cache_pmm_reclaimable_bytes > 0 and
            summary.fs_cache_pmm_dirty_bytes >= summary.fs_cache_dirty_non_reclaimable_bytes and
            summary.fs_cache_payload_allocations > 0 and
            summary.fs_cache_payload_allocation_failures == 0 and
            summary.fs_cache_payload_releases > 0 and
            summary.fs_cache_reclaim_returned_frames > 0 and
            summary.fs_cache_reclaim_returned_bytes >= summary.fs_cache_reclaim_returned_frames * @as(u64, summary.fs_cache_payload_frame_bytes) and
            summary.fs_cache_dirty_non_reclaimable_entries == summary.fs_cache_dirty_entries and
            summary.fs_cache_dirty_non_reclaimable_bytes == summary.fs_cache_dirty_bytes and
            summary.fs_cache_reclaim_scans > 0 and
            summary.fs_cache_reclaim_clean_entries > 0 and
            summary.fs_cache_reclaim_failed_drains == 0 and
            summary.fs_cache_pagefile_ready == 0 and
            pagefileBlockersOk(summary.fs_cache_pagefile_blockers) and
            summary.global_reclaim_attempts > 0 and
            summary.global_reclaim_successes > 0 and
            summary.global_reclaim_failures == 0 and
            summary.global_reclaim_returned_frames > 0 and
            summary.global_reclaim_returned_bytes >= summary.global_reclaim_returned_frames * @as(u64, summary.fs_cache_payload_frame_bytes) and
            summary.global_reclaim_last_reason == r4os.abi.memory_reclaim_reason_diagnostic and
            summary.global_reclaim_last_requested_frames > 0 and
            summary.global_reclaim_last_returned_frames > 0 and
            // Reclaim arbeitet clusterweise und darf deshalb mehr Frames als
            // die angeforderte Untergrenze zurueckgeben.
            summary.global_reclaim_failed_drains == 0 and
            summary.memory_backing_store_status == r4os.abi.memory_backing_store_status_ready and
            backingStoreReadyFlagsOk(summary.memory_backing_store_flags) and
            summary.memory_backing_store_blockers == 0 and
            summary.memory_backing_store_requested_bytes == backing_store_bytes and
            summary.memory_backing_store_available_bytes >= backing_store_bytes and
            summary.memory_backing_store_file_size >= backing_store_bytes and
            summary.memory_backing_store_probe_count >= 2 and
            summary.memory_backing_store_ready_count > 0 and
            summary.memory_backing_store_failure_count > 0 and
            summary.memory_backing_store_cluster_bytes >= 512 and
            summary.memory_backing_store_first_cluster != 0 and
            summary.memory_backing_store_pager_enabled == 0 and
            summary.memory_backing_store_anonymous_paging_enabled == 0 and
            slot_last_operation_ok and
            backingStoreSlotFlagsOk(summary.memory_backing_store_slot_flags) and
            summary.memory_backing_store_slot_blockers == 0 and
            summary.memory_backing_store_slot_bytes == 4096 and
            summary.memory_backing_store_slot_capacity >= backing_store_slot_count and
            summary.memory_backing_store_slot_free + summary.memory_backing_store_slot_reserved == summary.memory_backing_store_slot_capacity and
            summary.memory_backing_store_slot_valid <= summary.memory_backing_store_slot_reserved and
            summary.memory_backing_store_slot_dirty <= summary.memory_backing_store_slot_valid and
            summary.memory_backing_store_slot_error == 0 and
            summary.memory_backing_store_slot_range_count <= summary.memory_backing_store_slot_max_ranges and
            slot_last_owner_ok and
            summary.memory_backing_store_slot_max_ranges >= 16 and
            summary.memory_backing_store_slot_probe_count >= 6 and
            summary.memory_backing_store_slot_reserve_count > 0 and
            summary.memory_backing_store_slot_release_count > 0 and
            summary.memory_backing_store_slot_error_mark_count > 0 and
            summary.memory_backing_store_slot_recovery_count > 0 and
            summary.memory_backing_store_slot_failure_count > 0 and
            summary.memory_backing_store_slot_lifecycle_cleanup_count > 0 and
            summary.memory_backing_store_slot_lifecycle_released_ranges > 0 and
            summary.memory_backing_store_slot_lifecycle_released_slots >= backing_store_lifecycle_vm_slots and
            summary.memory_backing_store_slot_pager_enabled == 0 and
            summary.memory_backing_store_slot_eviction_enabled == 1 and
            summary.memory_backing_store_slot_page_in_enabled == 1 and
            summary.memory_backing_store_slot_page_out_enabled == 1 and
            summary.memory_pager_gate_status == r4os.abi.memory_pager_gate_status_ready and
            pagerGateFlagsOk(summary.memory_pager_gate_flags) and
            summary.memory_pager_gate_blockers == 0 and
            summary.memory_pager_gate_slot_bytes == 4096 and
            summary.memory_pager_gate_requested_bytes == backing_store_gate_bytes and
            summary.memory_pager_gate_committed_bytes >= backing_store_gate_bytes and
            summary.memory_pager_gate_resident_bytes == 0 and
            summary.memory_pager_gate_nonresident_bytes >= backing_store_gate_bytes and
            summary.memory_pager_gate_requested_slots == backing_store_gate_bytes / 4096 and
            summary.memory_pager_gate_prepared_slots == summary.memory_pager_gate_requested_slots and
            summary.memory_pager_gate_capacity_slots >= backing_store_slot_count and
            summary.memory_pager_gate_free_before_slots == summary.memory_pager_gate_capacity_slots and
            summary.memory_pager_gate_free_after_slots == summary.memory_pager_gate_capacity_slots and
            summary.memory_pager_gate_reserved_before_slots == 0 and
            summary.memory_pager_gate_reserved_after_slots == 0 and
            summary.memory_pager_gate_rollback_completed == 1 and
            summary.memory_pager_gate_commit_gate_enabled == 1 and
            summary.memory_pager_gate_fault_gate_enabled == 1 and
            summary.memory_pager_gate_pager_enabled == 0 and
            summary.memory_pager_gate_eviction_enabled == 1 and
            summary.memory_pager_gate_page_in_enabled == 0 and
            summary.memory_pager_gate_page_out_enabled == 0 and
            summary.memory_pager_gate_probe_count >= 4 and
            summary.memory_pager_gate_ready_count > 0 and
            summary.memory_pager_gate_rollback_count > 0 and
            summary.memory_pager_gate_failure_count > 0 and
            page_io_last_ok and
            page_io_shape_ok and
            summary.memory_page_io_blockers == 0 and
            summary.memory_page_io_slot_bytes == 4096 and
            summary.memory_page_io_expected_generation != 0 and
            summary.memory_page_io_pager_enabled == 0 and
            summary.memory_page_io_eviction_enabled == 1 and
            summary.memory_page_io_page_in_enabled == 1 and
            summary.memory_page_io_page_out_enabled == 1 and
            summary.memory_page_io_backing_offset < backing_store_bytes and
            summary.memory_page_io_capacity_slots >= backing_store_slot_count and
            page_io_valid_slots_ok and
            summary.memory_page_io_dirty_slots == 0 and
            summary.memory_page_io_error_slots == 0 and
            summary.memory_page_io_prepare_count >= 2 and
            summary.memory_page_io_page_out_count > 0 and
            summary.memory_page_io_page_in_count > 0 and
            summary.memory_page_io_failure_count > 0 and
            summary.memory_page_io_retry_attempt_count > 0 and
            summary.memory_page_io_retryable_failure_count > 0 and
            summary.memory_page_io_permanent_failure_count > 0 and
            summary.memory_page_io_retry_limit_hit_count > 0 and
            summary.memory_page_io_failed_page_out_count > 0 and
            summary.memory_page_io_failed_page_in_count > 0 and
            summary.memory_page_io_data_preserved_pages > 0 and
            summary.memory_page_io_data_lost_pages == 0 and
            summary.memory_vm_page_state_status == r4os.abi.memory_vm_page_state_status_ready and
            (summary.memory_vm_page_state_flags & r4os.abi.memory_vm_page_state_flag_vm_owned_state) != 0 and
            summary.memory_vm_page_state_page_size == 4096 and
            summary.memory_vm_page_state_max_spans >= 1 and
            summary.memory_vm_page_state_transition_count > 0 and
            summary.memory_vm_page_state_dirty_mark_count > 0 and
            summary.memory_vm_page_state_clean_mark_count > 0 and
            summary.memory_vm_page_state_slot_bind_count > 0 and
            summary.memory_vm_page_state_cleanup_pages > 0 and
            summary.memory_vm_page_state_fault_page_in_count > 0 and
            summary.memory_vm_page_state_page_out_nonresident_pages > 0 and
            summary.memory_vm_eviction_attempt_count > 0 and
            summary.memory_vm_eviction_success_count > 0 and
            summary.memory_vm_eviction_page_out_count > 0 and
            summary.memory_vm_eviction_returned_frames > 0 and
            summary.global_reclaim_vm_returned_frames > 0 and
            summary.global_reclaim_vm_page_outs > 0 and
            summary.memory_vm_pager_failed_page_out_count > 0 and
            summary.memory_vm_pager_data_preserved_pages > 0 and
            summary.memory_vm_pager_dirty_preserved_pages > 0 and
            summary.memory_vm_pager_data_lost_pages == 0 and
            summary.memory_vm_pager_disabled_eviction_gates > 0 and
            summary.fs_cache_read_errors == 0 and
            summary.fs_cache_write_errors == 0 and
            summary.fs_cache_writeback_errors == 0 and
            summary.service_queue_depth_total >= summary.service_endpoints and
            service_completion_ok and
            service_payload_ok and
            service_lock_ok and
            display_responsiveness_ok and
            audio_latency_ok and
            loader_perf_ok and
            loader_memory_ok and
            hot_path_ok and
            storage_dispatch_ok and
            flags_ok and
            wait_missing_ok and
            lock_ok;
        const contract_ok = summary.version == r4os.abi.performance_snapshot_version and
            summary.size >= @sizeOf(r4os.abi.ProgramPerformanceSummary) and
            summary.tick_hz > 0 and
            flags_ok and
            wait_missing_ok and
            summary.task_count > 0 and
            summary.task_count <= summary.task_max_count and
            summary.boot_phase_count > 0 and
            summary.storage_device_count > 0 and
            summary.fs_cache_capacity > 0 and
            summary.fs_cache_entries_used <= summary.fs_cache_capacity and
            summary.fs_cache_writeback_queue_depth <= summary.fs_cache_writeback_queue_high_water and
            summary.fs_cache_read_errors == 0 and
            summary.fs_cache_write_errors == 0 and
            summary.fs_cache_writeback_errors == 0 and
            cache_policy_ok and
            ntfs_metadata_cache_ok and
            summary.storage_completion_timeouts == 0 and
            storage_dispatch_ok and
            summary.service_queue_used_total <= summary.service_queue_depth_total and
            service_payload_ok and
            service_lock_ok and
            lock_ok and
            summary.memory_backing_store_status == r4os.abi.memory_backing_store_status_ready and
            backingStoreReadyFlagsOk(summary.memory_backing_store_flags) and
            summary.memory_backing_store_blockers == 0 and
            slot_last_operation_ok and
            slot_last_owner_ok and
            summary.memory_backing_store_slot_error == 0 and
            summary.memory_backing_store_slot_free + summary.memory_backing_store_slot_reserved == summary.memory_backing_store_slot_capacity and
            page_io_last_ok and
            page_io_shape_ok and
            summary.memory_page_io_blockers == 0 and
            summary.memory_page_io_error_slots == 0 and
            summary.memory_vm_page_state_status == r4os.abi.memory_vm_page_state_status_ready and
            summary.memory_vm_pager_data_lost_pages == 0;
        self.printCheck("Service payload length/reset counters", service_payload_ok);
        self.printCheck("Service endpoint lock/scan counters", service_lock_ok);
        self.printCheck("Parallel storage dispatch/direct buffers", storage_dispatch_ok);
        self.printCheck("FS page cache bounded policy", cache_policy_ok);
        self.printCheck("NTFS metadata cache bounded generations", ntfs_metadata_cache_ok);
        self.printCheck("Performance summary contract", contract_ok);
        if (!legacy_snapshot_ok) {
            self.sys.println("  Legacy exact-state aggregate: OBSERVED (not a contract gate)");
            self.sys.write("  version=");
            self.sys.printU64(summary.version);
            self.sys.write(" size=");
            self.sys.printU64(summary.size);
            self.sys.write(" flags=");
            self.sys.printU64(summary.flags);
            self.sys.write(" tasks=");
            self.sys.printU64(summary.task_count);
            self.sys.write(" storage=");
            self.sys.printU64(summary.storage_device_count);
            self.sys.write(" queued=");
            self.sys.printU64(summary.storage_queued_requests);
            self.sys.write(" cwait=");
            self.sys.printU64(summary.storage_completion_waits);
            self.sys.write(" fsReq=");
            self.sys.printU64(summary.fs_requests);
            self.sys.write(" fsLock=");
            self.sys.printU64(summary.fs_lock_acquires);
            self.sys.write(" cache=");
            self.sys.printU64(summary.fs_cache_hits);
            self.sys.write("/");
            self.sys.printU64(summary.fs_cache_misses);
            self.sys.write(" dirty=");
            self.sys.printU64(summary.fs_cache_dirty_entries);
            self.sys.write(" q=");
            self.sys.printU64(summary.fs_cache_writeback_queue_depth);
            self.sys.write("/");
            self.sys.printU64(summary.fs_cache_writeback_queue_high_water);
            self.sys.write(" deferred=");
            self.sys.printU64(summary.fs_cache_deferred_write_requests);
            self.sys.write(" wb=");
            self.sys.printU64(summary.fs_cache_writeback_sectors);
            self.sys.write(" reclaim=");
            self.sys.printU64(summary.fs_cache_clean_reclaimable_bytes);
            self.sys.write(" pmm=");
            self.sys.printU64(summary.fs_cache_pmm_reclaimable_bytes);
            self.sys.write(" pagefileReady=");
            self.sys.printU64(summary.fs_cache_pagefile_ready);
            self.sys.write(" blockers=");
            self.sys.printU64(summary.fs_cache_pagefile_blockers);
            self.sys.write(" global=");
            self.sys.printU64(summary.global_reclaim_attempts);
            self.sys.write("/");
            self.sys.printU64(summary.global_reclaim_returned_frames);
            self.sys.write(" last=");
            self.sys.printU64(summary.global_reclaim_last_reason);
            self.sys.write("/");
            self.sys.printU64(summary.global_reclaim_last_returned_frames);
            self.sys.write(" backing=");
            self.sys.printU64(summary.memory_backing_store_status);
            self.sys.write("/");
            self.sys.printU64(summary.memory_backing_store_available_bytes);
            self.sys.write(" bFlags=");
            self.sys.printU64(summary.memory_backing_store_flags);
            self.sys.write(" bBlock=");
            self.sys.printU64(summary.memory_backing_store_blockers);
            self.sys.write(" svcQ=");
            self.sys.printU64(summary.service_queue_depth_total);
            self.sys.write("/");
            self.sys.printU64(summary.service_queue_used_total);
            self.sys.write(" svcWait=");
            self.sys.printU64(summary.service_completion_waits);
            self.sys.write(" svcTimeout=");
            self.sys.printU64(summary.service_timeouts);
            self.sys.write("/");
            self.sys.printU64(summary.service_completion_timeouts);
            self.sys.write(" svcCancel=");
            self.sys.printU64(summary.service_cancellations);
            self.sys.write("/");
            self.sys.printU64(summary.service_drops);
            self.sys.write(" lockBad=");
            self.sys.printU64(summary.lock_order_violations +% summary.lock_sleep_under_no_sleep_lock +% summary.lock_unlock_mismatches);
            self.sys.println("");
            self.sys.write("  pageIo status/op/flags=");
            self.sys.printU64(summary.memory_page_io_status);
            self.sys.write("/");
            self.sys.printU64(summary.memory_page_io_operation);
            self.sys.write("/");
            self.sys.printU64(summary.memory_page_io_flags);
            self.sys.write(" owner=");
            self.sys.printU64(summary.memory_page_io_owner_kind);
            self.sys.write("/");
            self.sys.printU64(summary.memory_page_io_owner_id);
            self.sys.write(" region=");
            self.sys.printU64(summary.memory_page_io_region_id);
            self.sys.write(" blockers=");
            self.sys.printU64(summary.memory_page_io_blockers);
            self.sys.write(" slot/io/status=");
            self.sys.printU64(summary.memory_page_io_slot_bytes);
            self.sys.write("/");
            self.sys.printU64(summary.memory_page_io_io_bytes);
            self.sys.write("/");
            self.sys.printU64(@intCast(@max(summary.memory_page_io_io_status, 0)));
            self.sys.write(" page/transfer/gen=");
            self.sys.printU64(summary.memory_page_io_page_count);
            self.sys.write("/");
            self.sys.printU64(summary.memory_page_io_transfer_bytes);
            self.sys.write("/");
            self.sys.printU64(summary.memory_page_io_expected_generation);
            self.sys.write(" offsets=");
            self.sys.printU64(summary.memory_page_io_region_offset);
            self.sys.write("/");
            self.sys.printU64(summary.memory_page_io_backing_offset);
            self.sys.write(" cap=");
            self.sys.printU64(summary.memory_page_io_capacity_slots);
            self.sys.write(" valid/dirty/error=");
            self.sys.printU64(summary.memory_page_io_valid_slots);
            self.sys.write("/");
            self.sys.printU64(summary.memory_page_io_dirty_slots);
            self.sys.write("/");
            self.sys.printU64(summary.memory_page_io_error_slots);
            self.sys.write(" prepare/out/in/fail=");
            self.sys.printU64(summary.memory_page_io_prepare_count);
            self.sys.write("/");
            self.sys.printU64(summary.memory_page_io_page_out_count);
            self.sys.write("/");
            self.sys.printU64(summary.memory_page_io_page_in_count);
            self.sys.write("/");
            self.sys.printU64(summary.memory_page_io_failure_count);
            self.sys.println("");
            self.sys.write("  pageIo policy retry/retryable/perm/limit=");
            self.sys.printU64(summary.memory_page_io_retry_attempt_count);
            self.sys.write("/");
            self.sys.printU64(summary.memory_page_io_retryable_failure_count);
            self.sys.write("/");
            self.sys.printU64(summary.memory_page_io_permanent_failure_count);
            self.sys.write("/");
            self.sys.printU64(summary.memory_page_io_retry_limit_hit_count);
            self.sys.write(" failOut/In=");
            self.sys.printU64(summary.memory_page_io_failed_page_out_count);
            self.sys.write("/");
            self.sys.printU64(summary.memory_page_io_failed_page_in_count);
            self.sys.write(" preserved/lost=");
            self.sys.printU64(summary.memory_page_io_data_preserved_pages);
            self.sys.write("/");
            self.sys.printU64(summary.memory_page_io_data_lost_pages);
            self.sys.println("");
            self.sys.write("  vmState status/op/flags=");
            self.sys.printU64(summary.memory_vm_page_state_status);
            self.sys.write("/");
            self.sys.printU64(summary.memory_vm_page_state_operation);
            self.sys.write("/");
            self.sys.printU64(summary.memory_vm_page_state_flags);
            self.sys.write(" blockers=");
            self.sys.printU64(summary.memory_vm_page_state_blockers);
            self.sys.write(" region=");
            self.sys.printU64(summary.memory_vm_page_state_region_id);
            self.sys.write(" pages res/dirty/slot=");
            self.sys.printU64(summary.memory_vm_page_state_resident_pages);
            self.sys.write("/");
            self.sys.printU64(summary.memory_vm_page_state_dirty_pages);
            self.sys.write("/");
            self.sys.printU64(summary.memory_vm_page_state_slot_bound_pages);
            self.sys.write(" transitions dirty/clean/slot/cleanup=");
            self.sys.printU64(summary.memory_vm_page_state_transition_count);
            self.sys.write("/");
            self.sys.printU64(summary.memory_vm_page_state_dirty_mark_count);
            self.sys.write("/");
            self.sys.printU64(summary.memory_vm_page_state_clean_mark_count);
            self.sys.write("/");
            self.sys.printU64(summary.memory_vm_page_state_slot_bind_count);
            self.sys.write("/");
            self.sys.printU64(summary.memory_vm_page_state_cleanup_pages);
            self.sys.write(" faultIn/faultFail/nonresident=");
            self.sys.printU64(summary.memory_vm_page_state_fault_page_in_count);
            self.sys.write("/");
            self.sys.printU64(summary.memory_vm_page_state_fault_page_in_failure_count);
            self.sys.write("/");
            self.sys.printU64(summary.memory_vm_page_state_page_out_nonresident_pages);
            self.sys.println("");
            self.sys.write("  vmPager policy failOut/In=");
            self.sys.printU64(summary.memory_vm_pager_failed_page_out_count);
            self.sys.write("/");
            self.sys.printU64(summary.memory_vm_pager_failed_page_in_count);
            self.sys.write(" preserved/lost/dirty=");
            self.sys.printU64(summary.memory_vm_pager_data_preserved_pages);
            self.sys.write("/");
            self.sys.printU64(summary.memory_vm_pager_data_lost_pages);
            self.sys.write("/");
            self.sys.printU64(summary.memory_vm_pager_dirty_preserved_pages);
            self.sys.write(" gates=");
            self.sys.printU64(summary.memory_vm_pager_disabled_eviction_gates);
            self.sys.println("");
        }
        return contract_ok;
    }

    fn testSummaryClock(self: *App, summary: r4os.abi.ProgramPerformanceSummary) bool {
        var clock: r4os.abi.MonotonicClockInfo = .{};
        const clock_ok = self.queryMonotonicClock(&clock);
        const metadata_ok = clock_ok and
            summary.version == r4os.abi.performance_snapshot_version and
            summary.version >= 2 and
            summary.size >= @sizeOf(r4os.abi.ProgramPerformanceSummary) and
            summary.monotonic_clock_flags == clock.flags and
            summary.monotonic_clock_source == clock.source and
            summary.monotonic_clock_generation == clock.generation and
            summary.monotonic_event_backend == clock.event_backend and
            summary.monotonic_clock_resolution_ns == clock.resolution_ns and
            summary.monotonic_source_frequency_hz == clock.source_frequency_hz and
            summary.monotonic_event_frequency_numerator == clock.event_frequency_numerator and
            summary.monotonic_event_frequency_denominator == clock.event_frequency_denominator and
            summary.monotonic_event_requested_hz == clock.event_requested_hz and
            summary.monotonic_event_effective_hz == clock.event_effective_hz;
        self.printCheck("Performance summary clock metadata", metadata_ok);

        const boot_available = summary.boot_timing_valid != 0 and summary.boot_total_ns > 0 and summary.boot_now_ns >= summary.boot_total_ns;
        const boot_explicitly_unavailable = summary.boot_timing_valid == 0 and summary.boot_timing_unavailable_spans > 0;
        const loader_available = summary.loader_timing_valid_spans > 0;
        const loader_explicitly_unavailable = summary.loader_timing_valid_spans == 0 and summary.loader_timing_unavailable_spans > 0;
        const availability_ok = (boot_available or boot_explicitly_unavailable) and
            (loader_available or loader_explicitly_unavailable) and
            summary.boot_timing_dropped_spans == 0;
        self.printCheck("Boot/loader timing availability", availability_ok);
        if (!metadata_ok or !availability_ok) {
            self.sys.write("  clock generation=");
            self.sys.printU64(summary.monotonic_clock_generation);
            self.sys.write(" boot valid/unavailable/dropped=");
            self.sys.printU64(summary.boot_timing_valid);
            self.sys.write("/");
            self.sys.printU64(summary.boot_timing_unavailable_spans);
            self.sys.write("/");
            self.sys.printU64(summary.boot_timing_dropped_spans);
            self.sys.write(" loader valid/unavailable=");
            self.sys.printU64(summary.loader_timing_valid_spans);
            self.sys.write("/");
            self.sys.printU64(summary.loader_timing_unavailable_spans);
            self.sys.println("");
        }
        return metadata_ok and availability_ok;
    }

    fn burnPreemptionWindow(self: *App) bool {
        if (!self.sys.hasFn("thread_create_handle") or !self.sys.hasFn("thread_handle_join")) return self.failBool("Preemption workload thread API missing");

        const stop: *volatile u32 = &preemption_worker_stop;
        stop.* = 0;
        var worker_a: r4os.abi.ProgramJoinHandle = .{};
        if (self.sys.threadCreateHandle(preemptionWorkerMain, 0, 128 * 1024, 0, &worker_a) != r4os.abi.thread_ok) {
            stop.* = 1;
            return self.failBool("Preemption workload worker A create failed");
        }
        var worker_b: r4os.abi.ProgramJoinHandle = .{};
        if (self.sys.threadCreateHandle(preemptionWorkerMain, 1, 128 * 1024, 0, &worker_b) != r4os.abi.thread_ok) {
            stop.* = 1;
            var ignored_exit: i32 = 0;
            _ = self.sys.threadHandleJoin(&worker_a, r4os.abi.thread_wait_forever, &ignored_exit);
            return self.failBool("Preemption workload worker B create failed");
        }

        const start = self.sys.ticks();
        var rounds: u32 = 0;
        while (self.sys.ticks() - start < 24 and rounds < 384) : (rounds += 1) {
            spinForPreemption(1);
        }
        stop.* = 1;

        var exit_a: i32 = 0;
        var exit_b: i32 = 0;
        const join_a = self.sys.threadHandleJoin(&worker_a, r4os.abi.thread_wait_forever, &exit_a);
        const join_b = self.sys.threadHandleJoin(&worker_b, r4os.abi.thread_wait_forever, &exit_b);
        const ok = join_a == r4os.abi.thread_ok and join_b == r4os.abi.thread_ok and exit_a == 38 and exit_b == 38 and rounds > 0;
        self.printCheck("Preemption CPU workload", ok);
        if (!ok) {
            self.sys.write("  preempt workload join=");
            self.sys.printU64(@intCast(@max(join_a, 0)));
            self.sys.write("/");
            self.sys.printU64(@intCast(@max(join_b, 0)));
            self.sys.write(" exit=");
            self.sys.printI32(exit_a);
            self.sys.write("/");
            self.sys.printI32(exit_b);
            self.sys.write(" rounds=");
            self.sys.printU64(rounds);
            self.sys.println("");
        }
        return ok;
    }

    fn probeAvxRegisterState(self: *App) bool {
        if (!self.sys.hasFn("thread_create_handle") or !self.sys.hasFn("thread_handle_join")) return self.failBool("AVX workload thread API missing");
        const before = self.captureSummary() orelse return self.failBool("AVX snapshot unavailable");
        const features_ok = (before.flags & r4os.abi.performance_flag_avx_state_ready) != 0 and
            before.fpu_avx_supported == 1 and
            before.fpu_avx_enabled == 1 and
            before.fpu_avx2_supported == 1 and
            before.fpu_avx2_enabled == 1 and
            before.fpu_simd_abi == r4os.abi.performance_simd_abi_avx2 and
            before.fpu_state_backend == r4os.abi.performance_fpu_backend_xsave and
            (before.fpu_xcr0_mask & 0x7) == 0x7;
        if (!features_ok) {
            self.printCheck("AVX/AVX2 task state", false);
            self.printAvxFailure("feature", before, 0, 0, 0, 0);
            return false;
        }

        avx_worker_results = .{ 0, 0 };
        var worker_a: r4os.abi.ProgramJoinHandle = .{};
        if (self.sys.threadCreateHandle(avxWorkerMain, 0, 128 * 1024, 0, &worker_a) != r4os.abi.thread_ok) {
            self.printCheck("AVX/AVX2 task state", false);
            self.printAvxFailure("worker-a-create", before, 0, 0, 0, 0);
            return false;
        }
        var worker_b: r4os.abi.ProgramJoinHandle = .{};
        if (self.sys.threadCreateHandle(avxWorkerMain, 1, 128 * 1024, 0, &worker_b) != r4os.abi.thread_ok) {
            var ignored_exit: i32 = 0;
            _ = self.sys.threadHandleJoin(&worker_a, r4os.abi.thread_wait_forever, &ignored_exit);
            self.printCheck("AVX/AVX2 task state", false);
            self.printAvxFailure("worker-b-create", before, ignored_exit, 0, 0, 0);
            return false;
        }

        var exit_a: i32 = 0;
        var exit_b: i32 = 0;
        const join_a = self.sys.threadHandleJoin(&worker_a, r4os.abi.thread_wait_forever, &exit_a);
        const join_b = self.sys.threadHandleJoin(&worker_b, r4os.abi.thread_wait_forever, &exit_b);
        const ok = join_a == r4os.abi.thread_ok and
            join_b == r4os.abi.thread_ok and
            exit_a == 74 and
            exit_b == 75 and
            avx_worker_results[0] == 1 and
            avx_worker_results[1] == 1;
        self.printCheck("AVX/AVX2 task state", ok);
        if (!ok) self.printAvxFailure("register", before, exit_a, exit_b, avx_worker_results[0], avx_worker_results[1]);
        return ok;
    }

    fn printAvxFailure(self: *App, tag: []const u8, summary: r4os.abi.ProgramPerformanceSummary, exit_a: i32, exit_b: i32, result_a: u32, result_b: u32) void {
        self.sys.write("  avx ");
        self.sys.write(tag);
        self.sys.write(" flags=");
        self.sys.printU64(summary.flags);
        self.sys.write(" abi=");
        self.sys.printU64(summary.fpu_simd_abi);
        self.sys.write(" avx=");
        self.sys.printU64(summary.fpu_avx_supported);
        self.sys.write("/");
        self.sys.printU64(summary.fpu_avx_enabled);
        self.sys.write(" avx2=");
        self.sys.printU64(summary.fpu_avx2_supported);
        self.sys.write("/");
        self.sys.printU64(summary.fpu_avx2_enabled);
        self.sys.write(" backend=");
        self.sys.printU64(summary.fpu_state_backend);
        self.sys.write(" bytes=");
        self.sys.printU64(summary.fpu_state_bytes);
        self.sys.write("/");
        self.sys.printU64(summary.fpu_state_storage_bytes);
        self.sys.write(" xcr0=");
        self.sys.printU64(summary.fpu_xcr0_mask);
        self.sys.write(" exit=");
        self.sys.printI32(exit_a);
        self.sys.write("/");
        self.sys.printI32(exit_b);
        self.sys.write(" result=");
        self.sys.printU64(result_a);
        self.sys.write("/");
        self.sys.printU64(result_b);
        self.sys.println("");
    }

    fn testPreemption(self: *App, summary: r4os.abi.ProgramPerformanceSummary) bool {
        const outcomes = summary.preemption_deferred_no_task +%
            summary.preemption_deferred_no_ready +%
            summary.preemption_deferred_quantum +%
            summary.preemption_deferred_kernel_ip +%
            summary.preemption_deferred_critical +%
            summary.preemption_deferred_disabled +%
            summary.preemption_switch_ticks;
        const eligible_outcomes = summary.preemption_deferred_critical +%
            summary.preemption_deferred_kernel_ip +%
            summary.preemption_deferred_disabled +%
            summary.preemption_switch_ticks;
        const ok = summary.preemption_supported == 1 and
            summary.preemption_enabled == 1 and
            summary.preemption_test_mode == 0 and
            summary.preemption_quantum_ticks > 0 and
            summary.preemption_simulation_ticks > 0 and
            outcomes == summary.preemption_simulation_ticks and
            eligible_outcomes == summary.preemption_eligible_ticks and
            summary.preemption_quantum_expired >= summary.preemption_switch_ticks and
            summary.preemption_switch_ticks > 0 and
            summary.preemption_app_code_ticks >= summary.preemption_switch_ticks and
            summary.preemption_deferred_disabled == 0 and
            summary.preempt_disable_calls > 0 and
            summary.preempt_disable_underflows == 0 and
            (summary.preemption_gate_mask & r4os.abi.performance_preemption_gate_productive_disabled) == 0 and
            (summary.preemption_gate_mask & r4os.abi.performance_preemption_gate_fpu_state) == 0;
        self.printCheck("Productive timer preemption", ok);
        if (!ok) {
            self.sys.write("  preempt supported=");
            self.sys.printU64(summary.preemption_supported);
            self.sys.write(" enabled=");
            self.sys.printU64(summary.preemption_enabled);
            self.sys.write(" test=");
            self.sys.printU64(summary.preemption_test_mode);
            self.sys.write(" quantum=");
            self.sys.printU64(summary.preemption_quantum_ticks);
            self.sys.write(" gate=");
            self.sys.printU64(summary.preemption_gate_mask);
            self.sys.write(" sim=");
            self.sys.printU64(summary.preemption_simulation_ticks);
            self.sys.write(" outcomes=");
            self.sys.printU64(outcomes);
            self.sys.write(" eligible=");
            self.sys.printU64(summary.preemption_eligible_ticks);
            self.sys.write(" disabled=");
            self.sys.printU64(summary.preemption_deferred_disabled);
            self.sys.write(" critical=");
            self.sys.printU64(summary.preemption_deferred_critical);
            self.sys.write(" noReady=");
            self.sys.printU64(summary.preemption_deferred_no_ready);
            self.sys.write(" qdef=");
            self.sys.printU64(summary.preemption_deferred_quantum);
            self.sys.write(" kernelIp=");
            self.sys.printU64(summary.preemption_deferred_kernel_ip);
            self.sys.write(" qexp=");
            self.sys.printU64(summary.preemption_quantum_expired);
            self.sys.write(" app=");
            self.sys.printU64(summary.preemption_app_code_ticks);
            self.sys.write(" switches=");
            self.sys.printU64(summary.preemption_switch_ticks);
            self.sys.write(" calls=");
            self.sys.printU64(summary.preempt_disable_calls);
            self.sys.write("/");
            self.sys.printU64(summary.preempt_enable_calls);
            self.sys.write(" under=");
            self.sys.printU64(summary.preempt_disable_underflows);
            self.sys.println("");
        }
        return ok;
    }

    fn testSchedulerLatency(self: *App, summary: r4os.abi.ProgramPerformanceSummary) bool {
        const quantum_ticks: u64 = @intCast(summary.preemption_quantum_ticks);
        const latency_missing = r4os.abi.performance_missing_wait_latency_histogram |
            r4os.abi.performance_missing_preemption_latency_histogram;
        const ready_ok = summary.scheduler_ready_latency_samples > 0 and
            summary.scheduler_ready_latency_total_ticks >= summary.scheduler_ready_latency_last_ticks and
            summary.scheduler_ready_latency_max_ticks >= summary.scheduler_ready_latency_last_ticks;
        const wait_object_ok = summary.wait_object_waits > 0 and
            summary.wait_object_max_ticks > 0 and
            summary.wait_object_total_ticks >= summary.wait_object_max_ticks and
            summary.wait_object_max_ticks >= summary.wait_object_last_ticks;
        const wait_queue_ok = summary.wait_queue_waits > 0 and
            summary.wait_queue_max_ticks > 0 and
            summary.wait_queue_total_ticks >= summary.wait_queue_max_ticks and
            summary.wait_queue_max_ticks >= summary.wait_queue_last_ticks and
            summary.wait_queue_drops == 0;
        const quantum_ok = summary.scheduler_run_without_switch_max_ticks >= quantum_ticks and
            summary.scheduler_quantum_overrun_count > 0 and
            summary.scheduler_quantum_overrun_max_ticks > 0 and
            summary.scheduler_preemption_deferred_max_ticks >= quantum_ticks;
        const warning_policy_ok = summary.scheduler_long_running_warn_ticks > quantum_ticks and
            summary.scheduler_starvation_warn_ticks >= summary.scheduler_long_running_warn_ticks and
            summary.starvation_warnings == 0;
        const ok = (summary.flags & r4os.abi.performance_flag_scheduler_latency_ready) != 0 and
            (summary.missing_flags & latency_missing) == 0 and
            ready_ok and
            wait_object_ok and
            wait_queue_ok and
            quantum_ok and
            warning_policy_ok;
        self.printCheck("Scheduler latency hardening", ok);
        if (!ok) {
            self.sys.write("  sched latency samples=");
            self.sys.printU64(summary.scheduler_ready_latency_samples);
            self.sys.write(" readyMax=");
            self.sys.printU64(summary.scheduler_ready_latency_max_ticks);
            self.sys.write(" readyWaitMax=");
            self.sys.printU64(summary.scheduler_ready_waiting_max_ticks);
            self.sys.write(" runMax=");
            self.sys.printU64(summary.scheduler_run_without_switch_max_ticks);
            self.sys.write(" overrun=");
            self.sys.printU64(summary.scheduler_quantum_overrun_count);
            self.sys.write("/");
            self.sys.printU64(summary.scheduler_quantum_overrun_max_ticks);
            self.sys.write(" deferMax=");
            self.sys.printU64(summary.scheduler_preemption_deferred_max_ticks);
            self.sys.write(" waitObj=");
            self.sys.printU64(summary.wait_object_total_ticks);
            self.sys.write("/");
            self.sys.printU64(summary.wait_object_max_ticks);
            self.sys.write(" waitQ=");
            self.sys.printU64(summary.wait_queue_total_ticks);
            self.sys.write("/");
            self.sys.printU64(summary.wait_queue_max_ticks);
            self.sys.write(" missing=");
            self.sys.printU64(summary.missing_flags);
            self.sys.write(" warn=");
            self.sys.printU64(summary.long_running_task_warnings);
            self.sys.write("/");
            self.sys.printU64(summary.starvation_warnings);
            self.sys.println("");
        }
        return ok;
    }

    fn testLocalFpuArithmetic(self: *App) bool {
        var a: f64 = 1.25;
        var b: f64 = 3.5;
        var i: u32 = 0;
        while (i < 16) : (i += 1) {
            const step: f64 = @floatFromInt(i + 1);
            a = (a + b) * 1.0009765625 - (step * 0.03125);
            b = b + (step * 0.125);
            self.sys.sleepTicks(1);
        }
        const ok = a > 0.0 and b > 3.5 and a != b;
        self.printCheck("Local FPU/SSE arithmetic", ok);
        if (!ok) {
            self.sys.write("  fpu-local a=");
            self.sys.printI32(@intFromFloat(a));
            self.sys.write(" b=");
            self.sys.printI32(@intFromFloat(b));
            self.sys.println("");
        }
        return ok;
    }

    fn probeDisplayResponsiveness(self: *App) bool {
        if (!self.dev.hasFn("display_summary") or !self.dev.hasFn("performance_summary")) {
            self.printCheck("Display present conformance", false);
            return false;
        }
        const before = self.dev.displaySummary() orelse {
            self.printCheck("Display present conformance", false);
            return false;
        };
        const pixel: [1]u32 = .{0x00_20_60_a0};
        const begin_rc = self.draw.displayBeginFrameRect(0, 0, 1, 1);
        const blit_rc = self.draw.displayBlitXrgb32(0, 0, 1, 1, pixel[0..]);
        const present_rc = self.draw.displayPresent();
        const after = self.dev.displaySummary() orelse {
            self.printCheck("Display present conformance", false);
            return false;
        };
        const ok = begin_rc > 0 and
            blit_rc >= 0 and
            present_rc > 0 and
            after.present_count > before.present_count and
            after.present_bytes_total >= before.present_bytes_total + 4 and
            after.present_max_ticks >= after.present_last_ticks and
            after.present_total_ticks >= before.present_total_ticks;
        self.printCheck("Display present conformance", ok);
        if (!ok) {
            self.sys.write("  display before=");
            self.sys.printU64(before.present_count);
            self.sys.write("/");
            self.sys.printU64(before.present_bytes_total);
            self.sys.write(" after=");
            self.sys.printU64(after.present_count);
            self.sys.write("/");
            self.sys.printU64(after.present_bytes_total);
            self.sys.write(" ticks=");
            self.sys.printU64(after.present_last_ticks);
            self.sys.write("/");
            self.sys.printU64(after.present_max_ticks);
            self.sys.write(" rc=");
            self.sys.printI32(begin_rc);
            self.sys.write("/");
            self.sys.printI32(blit_rc);
            self.sys.write("/");
            self.sys.printI32(present_rc);
            self.sys.println("");
        }
        return ok;
    }

    // Isolierter Blit-Durchsatz-Benchmark. Jede Wiederholung laeuft fuer
    // eine zeitbasierte Mindestdauer. Der periodische Event-Takt beendet
    // die Schleife; die Durchsatzzeit kommt, wenn verfuegbar, aus der
    // backendstabilen Nanosekundenuhr.
    fn probeBlitThroughput(self: *App) bool {
        if (!self.dev.hasFn("display_summary")) return false;
        const width: u32 = 320;
        const height: u32 = 64;
        const pixel_count: usize = @as(usize, width) * height;
        var i: usize = 0;
        while (i < pixel_count) : (i += 1) {
            blit_bench_frame[i] = 0xFF000000 | @as(u32, @intCast((i * 7) & 0xFFFFFF));
        }
        const frequency = self.eventHz();
        const min_ticks = measurement.ticksForMilliseconds(frequency, measurement.blit_min_duration_ms);
        if (min_ticks == 0) return false;

        const max_iters: u64 = 20000;
        self.stats.blit_sample_count = 0;
        var sample_index: usize = 0;
        while (sample_index < self.config.repetitions) : (sample_index += 1) {
            var iterations: u64 = 0;
            var clock_start: r4os.abi.MonotonicClockInfo = .{};
            const clock_sample_available = self.queryMonotonicClock(&clock_start);
            const start = self.sys.ticks();
            var elapsed: u64 = 0;
            while (iterations < max_iters) {
                const begin_rc = self.draw.displayBeginFrameRect(0, 0, width, height);
                const blit_rc = self.draw.displayBlitXrgb32(0, 0, width, height, blit_bench_frame[0..pixel_count]);
                const present_rc = self.draw.displayPresent();
                if (begin_rc <= 0 or blit_rc < 0 or present_rc <= 0) return false;
                iterations += 1;
                elapsed = self.sys.ticks() - start;
                if (elapsed >= min_ticks) break;
            }
            if (elapsed < min_ticks or elapsed == 0) return false;

            var elapsed_ns: u64 = 0;
            if (clock_sample_available) {
                var clock_end: r4os.abi.MonotonicClockInfo = .{};
                if (!self.queryMonotonicClock(&clock_end) or
                    clock_end.generation != clock_start.generation or
                    clock_end.instant_ns < clock_start.instant_ns) return false;
                elapsed_ns = clock_end.instant_ns - clock_start.instant_ns;
                if (elapsed_ns == 0) return false;
            }

            const bytes_total = iterations * @as(u64, pixel_count) * 4;
            self.stats.blit_samples[sample_index] = .{
                .iterations = iterations,
                .elapsed_ticks = elapsed,
                .elapsed_ns = elapsed_ns,
                .bytes = bytes_total,
                .kb_per_second = if (elapsed_ns > 0)
                    measurement.throughputKbPerSecondNs(bytes_total, elapsed_ns)
                else
                    measurement.throughputKbPerSecond(bytes_total, elapsed, frequency),
            };
            self.stats.blit_sample_count += 1;
        }
        return self.stats.blit_sample_count == self.config.repetitions;
    }

    fn printBlitResults(self: *App) void {
        var rates: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var index: usize = 0;
        while (index < self.stats.blit_sample_count) : (index += 1) {
            const sample = self.stats.blit_samples[index];
            rates[index] = sample.kb_per_second;
            self.sys.write("  Blit sample ");
            self.sys.printU64(index + 1);
            self.sys.write(": iterations=");
            self.sys.printU64(sample.iterations);
            self.sys.write(" ticks=");
            self.sys.printU64(sample.elapsed_ticks);
            self.sys.write(" ns=");
            self.sys.printU64(sample.elapsed_ns);
            self.sys.write(" bytes=");
            self.sys.printU64(sample.bytes);
            self.sys.write(" KB/s=");
            self.sys.printU64(sample.kb_per_second);
            self.sys.write(" MB/s=");
            self.sys.printU64(sample.kb_per_second / measurement.kb_per_mb);
            self.sys.println("");
        }
        const distribution = measurement.summarize(rates[0..self.stats.blit_sample_count]);
        self.sys.write("  Blit distribution KB/s: n=");
        self.sys.printU64(distribution.count);
        self.sys.write(" min=");
        self.sys.printU64(distribution.minimum);
        self.sys.write(" p50=");
        self.sys.printU64(distribution.p50);
        self.sys.write(" p95=");
        self.sys.printU64(distribution.p95);
        self.sys.write(" p99=");
        self.sys.printU64(distribution.p99);
        self.sys.write(" max=");
        self.sys.printU64(distribution.maximum);
        self.sys.write(" mean=");
        self.sys.printU64(distribution.mean);
        self.sys.println(" (1 MB = 1024 KB)");
    }

    fn probeMonotonicClock(self: *App) bool {
        if (!self.sys.hasFn("monotonic_clock")) return false;
        self.stats.clock_sample_count = 0;
        var sample_index: usize = 0;
        while (sample_index < self.config.repetitions) : (sample_index += 1) {
            var first: r4os.abi.MonotonicClockInfo = .{};
            if (self.sys.monotonicClock(&first) <= 0 or
                (first.flags & r4os.abi.monotonic_clock_flag_valid) == 0) return false;

            var previous = first.instant_ns;
            var min_positive_delta: u64 = 0;
            var zero_deltas: u64 = 0;
            var regressions: u64 = 0;
            var calls: u64 = 0;
            while (calls < measurement.clock_calls_per_sample) : (calls += 1) {
                var current: r4os.abi.MonotonicClockInfo = .{};
                if (self.sys.monotonicClock(&current) <= 0 or current.generation != first.generation) return false;
                if (current.instant_ns < previous) {
                    regressions +%= 1;
                } else {
                    const sample_delta = current.instant_ns - previous;
                    if (sample_delta == 0) {
                        zero_deltas +%= 1;
                    } else if (min_positive_delta == 0 or sample_delta < min_positive_delta) {
                        min_positive_delta = sample_delta;
                    }
                }
                previous = current.instant_ns;
            }
            if (regressions != 0 or previous <= first.instant_ns or min_positive_delta == 0) return false;
            const elapsed_ns = previous - first.instant_ns;
            self.stats.clock_samples[sample_index] = .{
                .calls = calls,
                .elapsed_ns = elapsed_ns,
                .ns_per_call = elapsed_ns / calls,
                .min_positive_delta_ns = min_positive_delta,
                .zero_deltas = zero_deltas,
                .regressions = regressions,
            };
            self.stats.clock_sample_count += 1;
        }
        return self.stats.clock_sample_count == self.config.repetitions;
    }

    fn printClockResults(self: *App) void {
        var costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var index: usize = 0;
        while (index < self.stats.clock_sample_count) : (index += 1) {
            const sample = self.stats.clock_samples[index];
            costs[index] = sample.ns_per_call;
            self.sys.write("  Clock sample ");
            self.sys.printU64(index + 1);
            self.sys.write(": calls=");
            self.sys.printU64(sample.calls);
            self.sys.write(" elapsedNs=");
            self.sys.printU64(sample.elapsed_ns);
            self.sys.write(" ns/call=");
            self.sys.printU64(sample.ns_per_call);
            self.sys.write(" minDeltaNs=");
            self.sys.printU64(sample.min_positive_delta_ns);
            self.sys.write(" zero=");
            self.sys.printU64(sample.zero_deltas);
            self.sys.write(" regressions=");
            self.sys.printU64(sample.regressions);
            self.sys.println("");
        }
        const distribution = measurement.summarize(costs[0..self.stats.clock_sample_count]);
        self.sys.write("  Clock distribution ns/call: n=");
        self.sys.printU64(distribution.count);
        self.sys.write(" min=");
        self.sys.printU64(distribution.minimum);
        self.sys.write(" p50=");
        self.sys.printU64(distribution.p50);
        self.sys.write(" p95=");
        self.sys.printU64(distribution.p95);
        self.sys.write(" p99=");
        self.sys.printU64(distribution.p99);
        self.sys.write(" max=");
        self.sys.printU64(distribution.maximum);
        self.sys.write(" mean=");
        self.sys.printU64(distribution.mean);
        self.sys.println("");
    }

    fn probeServiceRegistry(self: *App) bool {
        if (!self.sys.hasFn("service_info") or
            !self.sys.hasFn("service_detail") or
            !self.dev.hasFn("performance_summary") or
            !self.monotonic_clock_available) return false;

        self.stats.service_registry_sample_count = 0;
        var expected_services: ?u64 = null;
        var benchmark_ok = true;
        var phase_index: u8 = 0;
        while (phase_index < measurement.service_registry_phase_count) : (phase_index += 1) {
            const phase: measurement.ServiceRegistryPhase = @enumFromInt(phase_index);
            var repetition: u8 = 0;
            while (repetition < self.config.repetitions) : (repetition += 1) {
                const before = self.captureSummary() orelse return false;
                if (!serviceRegistrySummaryContractOk(before)) return false;

                var clock_start: r4os.abi.MonotonicClockInfo = .{};
                if (!self.queryMonotonicClock(&clock_start)) return false;
                var work = self.runServiceRegistryIterations(phase);
                var clock_end: r4os.abi.MonotonicClockInfo = .{};
                if (!self.queryMonotonicClock(&clock_end) or
                    clock_end.generation != clock_start.generation or
                    clock_end.instant_ns <= clock_start.instant_ns) return false;
                const after = self.captureSummary() orelse return false;
                if (!serviceRegistrySummaryContractOk(after)) return false;

                if (expected_services) |service_count| {
                    if (work.services_per_enumeration != service_count) work.errors +%= 1;
                } else {
                    expected_services = work.services_per_enumeration;
                }

                const sample = ServiceRegistrySample{
                    .phase = phase,
                    .repetition = repetition + 1,
                    .iterations = measurement.service_registry_iterations_per_sample,
                    .services_per_enumeration = work.services_per_enumeration,
                    .entries = work.entries,
                    .api_calls = work.api_calls,
                    .api_end_markers = work.end_markers,
                    .api_errors = work.errors,
                    .elapsed_ns = clock_end.instant_ns - clock_start.instant_ns,
                    .ns_per_enumeration = (clock_end.instant_ns - clock_start.instant_ns) /
                        measurement.service_registry_iterations_per_sample,
                    .index_queries = counterDelta(before.service_registry_index_queries, after.service_registry_index_queries),
                    .refresh_requests = counterDelta(before.service_registry_refresh_requests, after.service_registry_refresh_requests),
                    .refresh_visits = counterDelta(before.service_registry_refresh_visits, after.service_registry_refresh_visits),
                    .instance_lookups = counterDelta(before.service_registry_instance_lookups, after.service_registry_instance_lookups),
                    .counter_end_markers = counterDelta(before.service_registry_index_end_markers, after.service_registry_index_end_markers),
                    .legacy_reference_refresh_visits = work.api_calls * work.services_per_enumeration,
                    .checksum = work.checksum,
                };
                self.stats.service_registry_samples[self.stats.service_registry_sample_count] = sample;
                self.stats.service_registry_sample_count += 1;
                service_registry_benchmark_sink +%= sample.checksum;

                const sample_ok = sample.services_per_enumeration > 0 and
                    sample.api_errors == 0 and
                    sample.entries == sample.services_per_enumeration * sample.iterations and
                    sample.api_calls == sample.entries + sample.api_end_markers and
                    sample.api_end_markers == sample.iterations and
                    sample.index_queries == sample.api_calls and
                    sample.refresh_requests == sample.entries and
                    sample.refresh_visits == sample.entries and
                    sample.instance_lookups <= sample.entries and
                    sample.counter_end_markers == sample.api_end_markers and
                    sample.legacy_reference_refresh_visits > sample.refresh_visits;
                benchmark_ok = sample_ok and benchmark_ok;
            }
        }
        return benchmark_ok and
            self.stats.service_registry_sample_count == measurement.service_registry_phase_count * self.config.repetitions;
    }

    fn runServiceRegistryIterations(self: *App, phase: measurement.ServiceRegistryPhase) ServiceRegistryWork {
        var work: ServiceRegistryWork = .{};
        var iteration: u64 = 0;
        while (iteration < measurement.service_registry_iterations_per_sample) : (iteration += 1) {
            const entries_before = work.entries;
            var index: u32 = 0;
            var ended = false;
            while (index <= service_registry_max_entries) {
                var rc: i32 = 0;
                switch (phase) {
                    .service_info => {
                        var info: r4os.abi.ServiceInfo = .{};
                        rc = self.sys.serviceInfo(index, &info);
                        if (rc > 0) consumeServiceInfo(&work.checksum, &info, false);
                    },
                    .service_detail => {
                        var detail: r4os.abi.ServiceDetail = .{};
                        rc = self.sys.serviceDetail(index, &detail);
                        if (rc > 0) consumeServiceDetail(&work.checksum, &detail, false);
                    },
                    .servman_diag => {
                        var detail: r4os.abi.ServiceDetail = .{};
                        rc = self.sys.serviceDetail(index, &detail);
                        if (rc > 0) consumeServiceDetail(&work.checksum, &detail, true);
                    },
                }
                work.api_calls +%= 1;
                if (rc < 0) {
                    work.errors +%= 1;
                    break;
                }
                if (rc == 0) {
                    work.end_markers +%= 1;
                    ended = true;
                    break;
                }
                work.entries +%= 1;
                if (index >= service_registry_max_entries) {
                    work.errors +%= 1;
                    break;
                }
                index += 1;
            }
            if (!ended) work.errors +%= 1;
            const entries_this_iteration = work.entries - entries_before;
            if (iteration == 0) {
                work.services_per_enumeration = entries_this_iteration;
            } else if (entries_this_iteration != work.services_per_enumeration) {
                work.errors +%= 1;
            }
        }
        return work;
    }

    fn printServiceRegistryResults(self: *App) void {
        var index: usize = 0;
        while (index < self.stats.service_registry_sample_count) : (index += 1) {
            const sample = self.stats.service_registry_samples[index];
            self.sys.write("  Registry phase=");
            self.sys.write(sample.phase.name());
            self.sys.write(" sample=");
            self.sys.printU64(sample.repetition);
            self.sys.write(" iterations=");
            self.sys.printU64(sample.iterations);
            self.sys.write(" services=");
            self.sys.printU64(sample.services_per_enumeration);
            self.sys.write(" calls=");
            self.sys.printU64(sample.api_calls);
            self.sys.write(" visits=");
            self.sys.printU64(sample.refresh_visits);
            self.sys.write(" legacyVisits=");
            self.sys.printU64(sample.legacy_reference_refresh_visits);
            self.sys.write(" instanceLookups=");
            self.sys.printU64(sample.instance_lookups);
            self.sys.write(" end=");
            self.sys.printU64(sample.api_end_markers);
            self.sys.write(" errors=");
            self.sys.printU64(sample.api_errors);
            self.sys.write(" elapsedNs=");
            self.sys.printU64(sample.elapsed_ns);
            self.sys.write(" ns/enumeration=");
            self.sys.printU64(sample.ns_per_enumeration);
            self.sys.println("");
        }

        var phase_index: u8 = 0;
        while (phase_index < measurement.service_registry_phase_count) : (phase_index += 1) {
            const phase: measurement.ServiceRegistryPhase = @enumFromInt(phase_index);
            var costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
            var count: usize = 0;
            index = 0;
            while (index < self.stats.service_registry_sample_count) : (index += 1) {
                const sample = self.stats.service_registry_samples[index];
                if (sample.phase != phase) continue;
                costs[count] = sample.ns_per_enumeration;
                count += 1;
            }
            if (count == 0) continue;
            const distribution = measurement.summarize(costs[0..count]);
            self.sys.write("  Registry distribution phase=");
            self.sys.write(phase.name());
            self.sys.write(" ns/enumeration: n=");
            self.sys.printU64(distribution.count);
            self.sys.write(" min=");
            self.sys.printU64(distribution.minimum);
            self.sys.write(" p50=");
            self.sys.printU64(distribution.p50);
            self.sys.write(" p95=");
            self.sys.printU64(distribution.p95);
            self.sys.write(" p99=");
            self.sys.printU64(distribution.p99);
            self.sys.write(" max=");
            self.sys.printU64(distribution.maximum);
            self.sys.write(" mean=");
            self.sys.printU64(distribution.mean);
            self.sys.println("");
        }
    }

    fn probeKernelIpc(self: *App) bool {
        var net = self.net orelse return false;
        if (!net.hasFn("net_service_request") or
            !net.hasFn("ipc_performance") or
            !self.monotonic_clock_available) return false;

        const status_cases = [_]struct { channel: u32, op: u16 }{
            .{ .channel = kernel_ipc_channels[0], .op = r4os.abi.net_service_op_dhcp_status_result },
            .{ .channel = kernel_ipc_channels[1], .op = r4os.abi.net_service_op_dns_status_result },
            .{ .channel = kernel_ipc_channels[2], .op = r4os.abi.net_service_op_tcp_status_result },
            .{ .channel = kernel_ipc_channels[3], .op = r4os.abi.net_service_op_udp_status_result },
        };
        var maximum_payload: [r4os.abi.ipc_max_message_size - r4os.abi.net_service_header_size]u8 = undefined;
        for (&maximum_payload, 0..) |*byte, index| byte.* = @truncate(index *% 131 +% 17);

        const requests = measurement.kernel_ipc_iterations_per_sample * measurement.kernel_ipc_requests_per_iteration;
        const status_requests = measurement.kernel_ipc_iterations_per_sample * measurement.kernel_ipc_status_requests_per_iteration;
        const small_requests = measurement.kernel_ipc_iterations_per_sample * measurement.kernel_ipc_small_requests_per_iteration;
        const max_requests = measurement.kernel_ipc_iterations_per_sample * measurement.kernel_ipc_max_requests_per_iteration;
        const expected_request_bytes = small_requests * r4os.abi.net_service_header_size +
            max_requests * r4os.abi.ipc_max_message_size;
        const minimum_response_bytes = requests * r4os.abi.net_service_header_size;

        self.stats.kernel_ipc_sample_count = 0;
        self.stats.kernel_ipc_discarded_attempts = 0;
        self.stats.kernel_ipc_quiescence_wait_ticks = 0;
        self.stats.kernel_ipc_quiescence_reached = false;
        if (!self.isolateKernelIpcProxyServices()) {
            _ = self.restoreKernelIpcProxyServices();
            return false;
        }
        var services_restored = false;
        defer if (!services_restored) {
            _ = self.restoreKernelIpcProxyServices();
        };
        if (!self.waitForKernelIpcQuiescence(&net)) return false;

        var repetition: u8 = 0;
        while (repetition < self.config.repetitions) : (repetition += 1) {
            var accepted = false;
            var attempt: u8 = 0;
            while (attempt < measurement.kernel_ipc_max_attempts_per_sample) : (attempt += 1) {
                var before: KernelIpcPerformanceSnapshots = .{r4os.abi.IpcPerformanceSummary{}} ** kernel_ipc_channels.len;
                if (!captureKernelIpcPerformance(&net, &before)) return false;

                var clock_start: r4os.abi.MonotonicClockInfo = .{};
                if (!self.queryMonotonicClock(&clock_start)) return false;
                var iteration: u64 = 0;
                while (iteration < measurement.kernel_ipc_iterations_per_sample) : (iteration += 1) {
                    const request_base: u32 = 0x6912_0000 +
                        @as(u32, repetition) * 0x1000 +
                        @as(u32, attempt) * 0x0400 +
                        @as(u32, @intCast(iteration)) * 16;
                    for (status_cases, 0..) |case, case_index| {
                        if (!kernelIpcRequest(
                            &net,
                            case.channel,
                            case.op,
                            request_base + @as(u32, @intCast(case_index)),
                            "",
                            r4os.abi.net_service_result_ok,
                            true,
                        )) return false;
                    }
                    for (status_cases, 0..) |case, case_index| {
                        if (!kernelIpcRequest(
                            &net,
                            case.channel,
                            0xFFFE,
                            request_base + 4 + @as(u32, @intCast(case_index)),
                            "",
                            r4os.abi.net_service_result_bad_op,
                            false,
                        )) return false;
                    }
                    if (!kernelIpcRequest(
                        &net,
                        kernel_ipc_channels[1],
                        0xFFFF,
                        request_base + 8,
                        maximum_payload[0..],
                        r4os.abi.net_service_result_bad_op,
                        false,
                    )) return false;
                }
                var clock_end: r4os.abi.MonotonicClockInfo = .{};
                if (!self.queryMonotonicClock(&clock_end) or
                    clock_end.generation != clock_start.generation or
                    clock_end.instant_ns <= clock_start.instant_ns) return false;
                var after: KernelIpcPerformanceSnapshots = .{r4os.abi.IpcPerformanceSummary{}} ** kernel_ipc_channels.len;
                if (!captureKernelIpcPerformance(&net, &after)) return false;

                const elapsed_ns = clock_end.instant_ns - clock_start.instant_ns;
                var sample = KernelIpcSample{
                    .repetition = repetition + 1,
                    .attempt = attempt + 1,
                    .iterations = measurement.kernel_ipc_iterations_per_sample,
                    .requests = requests,
                    .status_requests = status_requests,
                    .error_requests = requests - status_requests,
                    .small_requests = small_requests,
                    .max_requests = max_requests,
                    .elapsed_ns = elapsed_ns,
                    .caller_ns_per_request = elapsed_ns / requests,
                };
                for (before, after) |channel_before, channel_after| {
                    sample.handler_queued = sample.handler_queued +| counterDelta(channel_before.handler_queued, channel_after.handler_queued);
                    sample.handler_completed = sample.handler_completed +| counterDelta(channel_before.handler_completed, channel_after.handler_completed);
                    sample.handler_failures = sample.handler_failures +| counterDelta(channel_before.handler_failures, channel_after.handler_failures);
                    sample.handler_direct = sample.handler_direct +| counterDelta(channel_before.handler_direct, channel_after.handler_direct);
                    sample.handler_waits = sample.handler_waits +| counterDelta(channel_before.handler_waits, channel_after.handler_waits);
                    sample.handler_wait_timeouts = sample.handler_wait_timeouts +| counterDelta(channel_before.handler_wait_timeouts, channel_after.handler_wait_timeouts);
                    sample.handler_queue_ns = sample.handler_queue_ns +| counterDelta(channel_before.handler_queue_ns, channel_after.handler_queue_ns);
                    sample.handler_queue_max_before_ns = @max(sample.handler_queue_max_before_ns, channel_before.handler_queue_max_ns);
                    sample.handler_queue_max_ns = @max(sample.handler_queue_max_ns, channel_after.handler_queue_max_ns);
                    sample.handler_run_ns = sample.handler_run_ns +| counterDelta(channel_before.handler_run_ns, channel_after.handler_run_ns);
                    sample.handler_run_max_before_ns = @max(sample.handler_run_max_before_ns, channel_before.handler_run_max_ns);
                    sample.handler_run_max_ns = @max(sample.handler_run_max_ns, channel_after.handler_run_max_ns);
                    sample.handler_e2e_ns = sample.handler_e2e_ns +| counterDelta(channel_before.handler_e2e_ns, channel_after.handler_e2e_ns);
                    sample.handler_e2e_max_before_ns = @max(sample.handler_e2e_max_before_ns, channel_before.handler_e2e_max_ns);
                    sample.handler_e2e_max_ns = @max(sample.handler_e2e_max_ns, channel_after.handler_e2e_max_ns);
                    sample.request_bytes = sample.request_bytes +| counterDelta(channel_before.request_bytes, channel_after.request_bytes);
                    sample.response_bytes = sample.response_bytes +| counterDelta(channel_before.response_bytes, channel_after.response_bytes);
                    sample.payload_copy_bytes = sample.payload_copy_bytes +| counterDelta(channel_before.payload_copy_bytes, channel_after.payload_copy_bytes);
                    sample.payload_clear_bytes = sample.payload_clear_bytes +| counterDelta(channel_before.payload_clear_bytes, channel_after.payload_clear_bytes);
                    sample.queue_full = sample.queue_full +| counterDelta(channel_before.queue_full, channel_after.queue_full);
                    sample.queue_empty = sample.queue_empty +| counterDelta(channel_before.queue_empty, channel_after.queue_empty);
                    sample.admission_waits = sample.admission_waits +| counterDelta(channel_before.admission_waits, channel_after.admission_waits);
                    sample.admission_timeouts = sample.admission_timeouts +| counterDelta(channel_before.admission_timeouts, channel_after.admission_timeouts);
                    sample.recv_buffer_small = sample.recv_buffer_small +| counterDelta(channel_before.recv_buffer_small, channel_after.recv_buffer_small);
                    sample.response_search_slots = sample.response_search_slots +| counterDelta(channel_before.response_search_slots, channel_after.response_search_slots);
                    sample.stale_drops = sample.stale_drops +| counterDelta(channel_before.stale_drops, channel_after.stale_drops);
                    sample.lock_contentions = sample.lock_contentions +| counterDelta(channel_before.lock_contentions, channel_after.lock_contentions);
                    sample.irq_denied = sample.irq_denied +| counterDelta(channel_before.irq_denied, channel_after.irq_denied);
                    sample.queue_used_after = sample.queue_used_after +| channel_after.queue_used;
                }
                sample.handler_queue_ns_per_request = sample.handler_queue_ns / requests;
                sample.handler_run_ns_per_request = sample.handler_run_ns / requests;
                sample.handler_e2e_ns_per_request = sample.handler_e2e_ns / requests;

                const sample_ok = sample.handler_queued == requests and
                    sample.handler_completed == requests and
                    sample.handler_failures == 0 and
                    sample.handler_direct == 0 and
                    sample.handler_waits == requests and
                    sample.handler_wait_timeouts == 0 and
                    sample.request_bytes == expected_request_bytes and
                    sample.response_bytes >= minimum_response_bytes and
                    sample.payload_copy_bytes >= sample.request_bytes + sample.response_bytes and
                    sample.payload_clear_bytes == 0 and
                    sample.queue_full == 0 and
                    sample.admission_timeouts == 0 and
                    sample.recv_buffer_small == 0 and
                    sample.response_search_slots == 0 and
                    sample.stale_drops == 0 and
                    sample.irq_denied == 0 and
                    sample.queue_used_after == 0;
                if (sample_ok) {
                    self.stats.kernel_ipc_samples[self.stats.kernel_ipc_sample_count] = sample;
                    self.stats.kernel_ipc_sample_count += 1;
                    accepted = true;
                    break;
                }

                const concurrent_contamination = self.config.cache_state == .warm and
                    kernelIpcSampleHasConcurrentTraffic(sample, requests, expected_request_bytes, minimum_response_bytes);
                if (!concurrent_contamination) return false;
                self.stats.kernel_ipc_discarded_attempts +%= 1;
                if (attempt + 1 < measurement.kernel_ipc_max_attempts_per_sample) self.sys.sleepTicks(1);
            }
            if (!accepted) return false;
        }
        const samples_ok = self.stats.kernel_ipc_sample_count == self.config.repetitions;
        const restore_ok = self.restoreKernelIpcProxyServices();
        services_restored = true;
        return samples_ok and restore_ok;
    }

    fn isolateKernelIpcProxyServices(self: *App) bool {
        self.stats.kernel_ipc_isolation_stop_attempts = 0;
        self.stats.kernel_ipc_isolation_stopped = 0;
        self.stats.kernel_ipc_isolation_already_stopped = 0;
        self.stats.kernel_ipc_isolation_stop_mask = 0;
        self.stats.kernel_ipc_isolation_restore_attempts = 0;
        self.stats.kernel_ipc_isolation_restored = 0;
        self.stats.kernel_ipc_isolation_restore_ok = false;

        const stop_timeout_ticks = self.sys.ticksFromMilliseconds(measurement.kernel_ipc_service_stop_timeout_ms);
        const retry_delay_ticks = @max(self.sys.ticksFromMilliseconds(measurement.kernel_ipc_service_retry_delay_ms), 1);
        if (stop_timeout_ticks == 0) return false;

        for (kernel_ipc_proxy_services, 0..) |service_name, service_index| {
            var settled = false;
            var attempt: u8 = 0;
            while (attempt < measurement.kernel_ipc_service_transition_max_attempts) : (attempt += 1) {
                var info: r4os.abi.ServiceInfo = .{};
                self.stats.kernel_ipc_isolation_stop_attempts +%= 1;
                const rc = self.sys.serviceStop(service_name.ptr, &info, stop_timeout_ticks);
                if (rc == r4os.abi.service_api_result_ok) {
                    self.stats.kernel_ipc_isolation_stop_mask |= @as(u32, 1) << @intCast(service_index);
                    self.stats.kernel_ipc_isolation_stopped +%= 1;
                    settled = true;
                    break;
                }
                if (rc == r4os.abi.service_api_result_not_running) {
                    self.stats.kernel_ipc_isolation_already_stopped +%= 1;
                    settled = true;
                    break;
                }
                if (rc != r4os.abi.service_api_result_busy) return false;
                if (attempt + 1 < measurement.kernel_ipc_service_transition_max_attempts) {
                    self.sys.sleepTicks(retry_delay_ticks);
                }
            }
            if (!settled) return false;
        }
        return true;
    }

    fn restoreKernelIpcProxyServices(self: *App) bool {
        const retry_delay_ticks = @max(self.sys.ticksFromMilliseconds(measurement.kernel_ipc_service_retry_delay_ms), 1);
        var all_restored = true;
        var service_index = kernel_ipc_proxy_services.len;
        while (service_index > 0) {
            service_index -= 1;
            const service_bit = @as(u32, 1) << @intCast(service_index);
            if (self.stats.kernel_ipc_isolation_stop_mask & service_bit == 0) continue;

            const service_name = kernel_ipc_proxy_services[service_index];
            var restored = false;
            var attempt: u8 = 0;
            while (attempt < measurement.kernel_ipc_service_transition_max_attempts) : (attempt += 1) {
                var info: r4os.abi.ServiceInfo = .{};
                self.stats.kernel_ipc_isolation_restore_attempts +%= 1;
                const rc = self.sys.serviceStart(service_name.ptr, &info);
                if (rc == r4os.abi.service_api_result_ok or rc == r4os.abi.service_api_result_running) {
                    self.stats.kernel_ipc_isolation_restored +%= 1;
                    restored = true;
                    break;
                }
                if (rc != r4os.abi.service_api_result_busy) break;
                if (attempt + 1 < measurement.kernel_ipc_service_transition_max_attempts) {
                    self.sys.sleepTicks(retry_delay_ticks);
                }
            }
            if (!restored) all_restored = false;
        }
        self.stats.kernel_ipc_isolation_restore_ok = all_restored and
            self.stats.kernel_ipc_isolation_restored == self.stats.kernel_ipc_isolation_stopped;
        return self.stats.kernel_ipc_isolation_restore_ok;
    }

    fn waitForKernelIpcQuiescence(self: *App, net: *const r4os.r4net.Context) bool {
        if (self.config.cache_state != .warm) {
            self.stats.kernel_ipc_quiescence_reached = true;
            return true;
        }
        const quiet_ticks = measurement.ticksForMilliseconds(self.eventHz(), measurement.kernel_ipc_quiet_period_ms);
        const timeout_ticks = measurement.ticksForMilliseconds(self.eventHz(), measurement.kernel_ipc_quiescence_timeout_ms);
        if (quiet_ticks == 0 or timeout_ticks < quiet_ticks) return false;

        var previous: KernelIpcPerformanceSnapshots = .{r4os.abi.IpcPerformanceSummary{}} ** kernel_ipc_channels.len;
        if (!captureKernelIpcPerformance(net, &previous)) return false;
        var stable_ticks: u64 = 0;
        var waited_ticks: u64 = 0;
        while (waited_ticks < timeout_ticks) {
            self.sys.sleepTicks(1);
            waited_ticks += 1;
            self.stats.kernel_ipc_quiescence_wait_ticks = waited_ticks;

            var current: KernelIpcPerformanceSnapshots = .{r4os.abi.IpcPerformanceSummary{}} ** kernel_ipc_channels.len;
            if (!captureKernelIpcPerformance(net, &current)) return false;
            if (kernelIpcPerformanceQuiet(&previous, &current)) {
                stable_ticks += 1;
            } else {
                stable_ticks = 0;
            }
            previous = current;
            if (stable_ticks >= quiet_ticks) {
                self.stats.kernel_ipc_quiescence_reached = true;
                return true;
            }
        }
        return false;
    }

    fn printKernelIpcResults(self: *App) void {
        self.sys.write("  Kernel IPC proxy isolation stopped=");
        self.sys.printU64(self.stats.kernel_ipc_isolation_stopped);
        self.sys.write(" alreadyStopped=");
        self.sys.printU64(self.stats.kernel_ipc_isolation_already_stopped);
        self.sys.write(" stopAttempts=");
        self.sys.printU64(self.stats.kernel_ipc_isolation_stop_attempts);
        self.sys.write(" restored=");
        self.sys.printU64(self.stats.kernel_ipc_isolation_restored);
        self.sys.write(" restoreAttempts=");
        self.sys.printU64(self.stats.kernel_ipc_isolation_restore_attempts);
        self.sys.write(" restore=");
        self.sys.write(if (self.stats.kernel_ipc_isolation_restore_ok) "OK" else "failed");
        self.sys.println("");
        self.sys.write("  Kernel IPC discarded concurrent attempts=");
        self.sys.printU64(self.stats.kernel_ipc_discarded_attempts);
        self.sys.write(" maxAttempts/sample=");
        self.sys.printU64(measurement.kernel_ipc_max_attempts_per_sample);
        self.sys.write(" quiescenceWaitTicks=");
        self.sys.printU64(self.stats.kernel_ipc_quiescence_wait_ticks);
        self.sys.write(" quietMs=");
        self.sys.printU64(measurement.kernel_ipc_quiet_period_ms);
        self.sys.write(" quiescence=");
        self.sys.write(if (self.stats.kernel_ipc_quiescence_reached) "reached" else "failed");
        self.sys.println("");
        var caller_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var queue_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var run_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var e2e_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var index: usize = 0;
        while (index < self.stats.kernel_ipc_sample_count) : (index += 1) {
            const sample = self.stats.kernel_ipc_samples[index];
            caller_costs[index] = sample.caller_ns_per_request;
            queue_costs[index] = sample.handler_queue_ns_per_request;
            run_costs[index] = sample.handler_run_ns_per_request;
            e2e_costs[index] = sample.handler_e2e_ns_per_request;
            self.sys.write("  Kernel IPC sample=");
            self.sys.printU64(sample.repetition);
            self.sys.write(" attempt=");
            self.sys.printU64(sample.attempt);
            self.sys.write(" requests=");
            self.sys.printU64(sample.requests);
            self.sys.write(" callerNs/request=");
            self.sys.printU64(sample.caller_ns_per_request);
            self.sys.write(" queueNs/request=");
            self.sys.printU64(sample.handler_queue_ns_per_request);
            self.sys.write(" runNs/request=");
            self.sys.printU64(sample.handler_run_ns_per_request);
            self.sys.write(" e2eNs/request=");
            self.sys.printU64(sample.handler_e2e_ns_per_request);
            self.sys.write(" requestB=");
            self.sys.printU64(sample.request_bytes);
            self.sys.write(" responseB=");
            self.sys.printU64(sample.response_bytes);
            self.sys.write(" copyB=");
            self.sys.printU64(sample.payload_copy_bytes);
            self.sys.write(" clearB=");
            self.sys.printU64(sample.payload_clear_bytes);
            self.sys.write(" qFull=");
            self.sys.printU64(sample.queue_full);
            self.sys.write(" waits=");
            self.sys.printU64(sample.handler_waits);
            self.sys.write(" timeouts=");
            self.sys.printU64(sample.handler_wait_timeouts + sample.admission_timeouts);
            self.sys.write(" searchSlots=");
            self.sys.printU64(sample.response_search_slots);
            self.sys.write(" stale=");
            self.sys.printU64(sample.stale_drops);
            self.sys.println("");
        }
        self.printKernelIpcDistribution("caller", caller_costs[0..self.stats.kernel_ipc_sample_count]);
        self.printKernelIpcDistribution("handler-queue", queue_costs[0..self.stats.kernel_ipc_sample_count]);
        self.printKernelIpcDistribution("handler-run", run_costs[0..self.stats.kernel_ipc_sample_count]);
        self.printKernelIpcDistribution("handler-e2e", e2e_costs[0..self.stats.kernel_ipc_sample_count]);
    }

    fn printKernelIpcDistribution(self: *App, name: []const u8, values: []const u64) void {
        const distribution = measurement.summarize(values);
        self.sys.write("  Kernel IPC distribution metric=");
        self.sys.write(name);
        self.sys.write(" unit=ns/request n=");
        self.sys.printU64(distribution.count);
        self.sys.write(" min=");
        self.sys.printU64(distribution.minimum);
        self.sys.write(" p50=");
        self.sys.printU64(distribution.p50);
        self.sys.write(" p95=");
        self.sys.printU64(distribution.p95);
        self.sys.write(" p99=");
        self.sys.printU64(distribution.p99);
        self.sys.write(" max=");
        self.sys.printU64(distribution.maximum);
        self.sys.write(" mean=");
        self.sys.printU64(distribution.mean);
        self.sys.println("");
    }

    fn probeDriverWork(self: *App) bool {
        if (!self.dev.hasFn("performance_driver_work")) return false;
        prepareDriverWorkPcm();

        var repetition: u8 = 0;
        while (repetition < self.config.repetitions) : (repetition += 1) {
            const aggregate_before = self.dev.performanceDriverWork(0) orelse return false;
            if (!driverWorkSnapshotContractOk(aggregate_before)) return false;

            var owner_before: [measurement.driver_work_owner_capacity]r4os.abi.ProgramDriverWorkPerformanceInfo =
                .{r4os.abi.ProgramDriverWorkPerformanceInfo{}} ** measurement.driver_work_owner_capacity;
            var owner_index: usize = 0;
            while (owner_index < owner_before.len) : (owner_index += 1) {
                owner_before[owner_index] = self.dev.performanceDriverWork(@intCast(owner_index + 1)) orelse return false;
                if (!driverWorkSnapshotContractOk(owner_before[owner_index])) return false;
            }

            var audio_writes: u64 = 0;
            var audio_bytes: u64 = 0;
            if (!self.runDriverWorkAudioLoad(&audio_writes, &audio_bytes)) return false;

            const aggregate_after = self.dev.performanceDriverWork(0) orelse return false;
            if (!driverWorkSnapshotContractOk(aggregate_after)) return false;

            var selected_owner: u32 = 0;
            var selected_deadline_delta: u64 = 0;
            var selected_before: r4os.abi.ProgramDriverWorkPerformanceInfo = .{};
            var selected_after: r4os.abi.ProgramDriverWorkPerformanceInfo = .{};
            owner_index = 0;
            while (owner_index < owner_before.len) : (owner_index += 1) {
                const owner: u32 = @intCast(owner_index + 1);
                const after = self.dev.performanceDriverWork(owner) orelse return false;
                if (!driverWorkSnapshotContractOk(after)) return false;
                const deadline_delta = counterDelta(owner_before[owner_index].deadline_submitted, after.deadline_submitted);
                if (deadline_delta > selected_deadline_delta) {
                    selected_deadline_delta = deadline_delta;
                    selected_owner = owner;
                    selected_before = owner_before[owner_index];
                    selected_after = after;
                }
            }
            if (selected_owner == 0 or selected_deadline_delta == 0) return false;

            const before = selected_before.metrics;
            const after = selected_after.metrics;
            const started = counterDelta(before.started, after.started);
            const completed = counterDelta(before.completed, after.completed);
            const queue_total_ns = counterDelta(before.queue_total_ns, after.queue_total_ns);
            const run_total_ns = counterDelta(before.run_total_ns, after.run_total_ns);
            const e2e_total_ns = counterDelta(before.e2e_total_ns, after.e2e_total_ns);
            const sample = DriverWorkSample{
                .repetition = repetition + 1,
                .owner = selected_owner,
                .audio_writes = audio_writes,
                .audio_bytes = audio_bytes,
                .submitted = counterDelta(before.submitted, after.submitted),
                .submitted_actual_irq = counterDelta(before.submitted_actual_irq, after.submitted_actual_irq),
                .submitted_actual_task = counterDelta(before.submitted_actual_task, after.submitted_actual_task),
                .submitted_irq_class = counterDelta(before.submitted_irq_class, after.submitted_irq_class),
                .submitted_task_class = counterDelta(before.submitted_task_class, after.submitted_task_class),
                .started = started,
                .completed = completed,
                .failed = counterDelta(before.failed, after.failed),
                .cancelled = counterDelta(before.cancelled, after.cancelled),
                .dropped = counterDelta(before.dropped, after.dropped),
                .full_rejections = counterDelta(before.full_rejections, after.full_rejections),
                .retained_full_rejections = counterDelta(before.retained_full_rejections, after.retained_full_rejections),
                .releases = counterDelta(before.releases, after.releases),
                .release_busy = counterDelta(before.release_busy, after.release_busy),
                .release_wakes = counterDelta(before.release_wakes, after.release_wakes),
                .publication_pending_releases = counterDelta(before.publication_pending_releases, after.publication_pending_releases),
                .waiter_blocked_releases = counterDelta(before.waiter_blocked_releases, after.waiter_blocked_releases),
                .claimed_releases = counterDelta(before.claimed_releases, after.claimed_releases),
                .invalid_handles = counterDelta(before.invalid_handles, after.invalid_handles),
                .stale_handles = counterDelta(before.stale_handles, after.stale_handles),
                .wait_timeouts = counterDelta(before.wait_timeouts, after.wait_timeouts),
                .wait_failed = counterDelta(before.wait_failed, after.wait_failed),
                .wake_publications = counterDelta(before.wake_publications, after.wake_publications),
                .wake_waiters = counterDelta(before.wake_waiters, after.wake_waiters),
                .wake_misses = counterDelta(before.wake_misses, after.wake_misses),
                .selection_irq = counterDelta(before.selection_irq, after.selection_irq),
                .selection_task = counterDelta(before.selection_task, after.selection_task),
                .selection_irq_preferred = counterDelta(before.selection_irq_preferred, after.selection_irq_preferred),
                .selection_task_fairness = counterDelta(before.selection_task_fairness, after.selection_task_fairness),
                .deadline_submitted = selected_deadline_delta,
                .deadline_started = counterDelta(selected_before.deadline_started, selected_after.deadline_started),
                .deadline_completed = counterDelta(selected_before.deadline_completed, selected_after.deadline_completed),
                .deadline_misses = counterDelta(selected_before.deadline_misses, selected_after.deadline_misses),
                .deadline_budget_overruns = counterDelta(selected_before.deadline_budget_overruns, selected_after.deadline_budget_overruns),
                .deadline_queue_rejections = counterDelta(selected_before.deadline_queue_rejections, selected_after.deadline_queue_rejections),
                .deadline_queue_total_ticks = counterDelta(selected_before.deadline_queue_total_ticks, selected_after.deadline_queue_total_ticks),
                .deadline_queue_max_ticks_after = selected_after.deadline_queue_max_ticks,
                .deadline_lateness_total_ticks = counterDelta(selected_before.deadline_lateness_total_ticks, selected_after.deadline_lateness_total_ticks),
                .deadline_lateness_max_ticks_after = selected_after.deadline_lateness_max_ticks,
                .queue_total_ns = queue_total_ns,
                .queue_ns_per_started = if (started == 0) 0 else queue_total_ns / started,
                .queue_max_before_ns = before.queue_max_ns,
                .queue_max_after_ns = after.queue_max_ns,
                .run_total_ns = run_total_ns,
                .run_ns_per_completed = if (completed == 0) 0 else run_total_ns / completed,
                .run_max_before_ns = before.run_max_ns,
                .run_max_after_ns = after.run_max_ns,
                .e2e_total_ns = e2e_total_ns,
                .e2e_ns_per_completed = if (completed == 0) 0 else e2e_total_ns / completed,
                .e2e_max_before_ns = before.e2e_max_ns,
                .e2e_max_after_ns = after.e2e_max_ns,
                .timing_unavailable = counterDelta(before.timing_unavailable, after.timing_unavailable),
                .completion_age_current_ns_after = after.completion_age_current_ns,
                .completion_age_max_ns_after = after.completion_age_max_ns,
                .scan_passes = counterDelta(aggregate_before.metrics.scan_passes, aggregate_after.metrics.scan_passes),
                .scan_slots = counterDelta(aggregate_before.metrics.scan_slots, aggregate_after.metrics.scan_slots),
                .critical_sections = counterDelta(before.critical_sections, after.critical_sections),
                .critical_from_irq = counterDelta(before.critical_from_irq, after.critical_from_irq),
                .critical_total_ns = counterDelta(before.critical_total_ns, after.critical_total_ns),
                .critical_max_before_ns = before.critical_max_ns,
                .critical_max_after_ns = after.critical_max_ns,
                .critical_timing_samples = counterDelta(before.critical_timing_samples, after.critical_timing_samples),
                .critical_timing_unavailable = counterDelta(before.critical_timing_unavailable, after.critical_timing_unavailable),
                .waiter_enrollments = counterDelta(before.waiter_enrollments, after.waiter_enrollments),
                .waiter_wake_returns = counterDelta(before.waiter_wake_returns, after.waiter_wake_returns),
                .long_callbacks = counterDelta(before.long_callbacks, after.long_callbacks),
                .cleanup_calls = counterDelta(before.cleanup_calls, after.cleanup_calls),
                .cleanup_quiesced = counterDelta(before.cleanup_quiesced, after.cleanup_quiesced),
                .cleanup_failed_context = counterDelta(before.cleanup_failed_context, after.cleanup_failed_context),
                .cleanup_queued_cancelled = counterDelta(before.cleanup_queued_cancelled, after.cleanup_queued_cancelled),
                .cleanup_waits = counterDelta(before.cleanup_waits, after.cleanup_waits),
                .cleanup_wait_timeouts = counterDelta(before.cleanup_wait_timeouts, after.cleanup_wait_timeouts),
                .cleanup_wait_failures = counterDelta(before.cleanup_wait_failures, after.cleanup_wait_failures),
                .cleanup_released = counterDelta(before.cleanup_released, after.cleanup_released),
                .cleanup_late_finishes = counterDelta(before.cleanup_late_finishes, after.cleanup_late_finishes),
                .cleanup_scan_passes = counterDelta(before.cleanup_scan_passes, after.cleanup_scan_passes),
                .cleanup_scan_slots = counterDelta(before.cleanup_scan_slots, after.cleanup_scan_slots),
                .free_slots_after = aggregate_after.free_slots,
                .used_slots_after = aggregate_after.used_slots,
                .queued_slots_after = aggregate_after.queued_slots,
                .running_slots_after = aggregate_after.running_slots,
                .completed_slots_after = aggregate_after.completed_slots,
                .cancelled_slots_after = aggregate_after.cancelled_slots,
                .queue_high_water_after = aggregate_after.queue_high_water,
                .used_high_water_after = aggregate_after.used_high_water,
                .retained_high_water_after = aggregate_after.retained_high_water,
                .waiters_current_after = aggregate_after.waiters_current,
                .waiters_max_after = aggregate_after.waiters_max,
                .owner_used_slots_after = selected_after.owner_used_slots,
                .owner_used_high_water_after = selected_after.owner_used_high_water,
                .owner_retained_high_water_after = selected_after.owner_retained_high_water,
                .owner_waiters_current_after = selected_after.owner_waiters_current,
                .owner_waiters_max_after = selected_after.owner_waiters_max,
            };
            self.stats.driver_work_samples[self.stats.driver_work_sample_count] = sample;
            self.stats.driver_work_sample_count += 1;

            const terminal = sample.completed +% sample.cancelled;
            const sample_ok =
                audio_writes == measurement.driver_work_audio_writes_per_sample and
                audio_bytes == measurement.driver_work_audio_writes_per_sample * measurement.driver_work_audio_bytes_per_write and
                sample.submitted > 0 and
                sample.submitted == sample.submitted_actual_irq +% sample.submitted_actual_task and
                sample.submitted == sample.submitted_irq_class and
                sample.submitted_task_class == 0 and
                sample.deadline_submitted == sample.submitted and
                sample.started > 0 and
                sample.started <= sample.submitted and
                sample.completed > 0 and
                sample.completed <= sample.started and
                sample.deadline_started == sample.started and
                sample.deadline_completed == sample.completed and
                terminal <= sample.submitted and
                sample.wake_publications == terminal and
                sample.selection_irq +% sample.selection_task +% sample.deadline_started == sample.started and
                sample.deadline_misses == 0 and
                sample.deadline_budget_overruns == 0 and
                sample.deadline_queue_rejections == 0 and
                sample.failed == 0 and
                sample.dropped == 0 and
                sample.full_rejections == 0 and
                sample.retained_full_rejections == 0 and
                measurement.driverWorkReleaseAccountingOk(
                    terminal,
                    sample.releases,
                    sample.claimed_releases,
                    sample.release_busy,
                    sample.publication_pending_releases,
                    sample.waiter_blocked_releases,
                ) and
                sample.invalid_handles == 0 and
                sample.stale_handles == 0 and
                sample.wait_timeouts == 0 and
                sample.wait_failed == 0 and
                sample.timing_unavailable == 0 and
                sample.queue_total_ns > 0 and
                sample.run_total_ns > 0 and
                sample.e2e_total_ns >= sample.run_total_ns and
                sample.scan_passes == 0 and
                sample.scan_slots == 0 and
                sample.critical_sections > 0 and
                sample.critical_from_irq > 0 and
                sample.critical_timing_samples == sample.critical_sections and
                sample.critical_timing_unavailable == 0 and
                sample.cleanup_calls == 0 and
                sample.cleanup_wait_timeouts == 0 and
                sample.cleanup_wait_failures == 0 and
                sample.waiters_current_after == 0 and
                sample.owner_waiters_current_after == 0 and
                sample.owner_used_slots_after == 0 and
                driverWorkSlotAccountingOk(aggregate_after);
            if (!sample_ok) return false;
        }
        return self.stats.driver_work_sample_count == self.config.repetitions;
    }

    fn runDriverWorkAudioLoad(self: *App, out_writes: *u64, out_bytes: *u64) bool {
        out_writes.* = 0;
        out_bytes.* = 0;
        const stream = self.audio.audioOpenStream(48_000, 2, .s16le);
        if (stream < 0) return false;
        const stream_id: u32 = @intCast(stream);
        const spacing_ticks = @max(
            measurement.ticksForMilliseconds(self.eventHz(), measurement.driver_work_audio_write_spacing_ms),
            1,
        );
        var write_index: u64 = 0;
        while (write_index < measurement.driver_work_audio_writes_per_sample) : (write_index += 1) {
            const written = self.audio.audioWrite(stream_id, driver_work_bench_pcm[0..]);
            if (written != @as(i32, @intCast(driver_work_bench_pcm.len))) {
                _ = self.audio.audioClose(stream_id);
                return false;
            }
            out_writes.* +%= 1;
            out_bytes.* +%= @intCast(driver_work_bench_pcm.len);
            self.sys.sleepTicks(spacing_ticks);
        }
        if (self.audio.audioClose(stream_id) != 0) return false;
        self.sys.sleepTicks(1);
        return true;
    }

    fn printDriverWorkResults(self: *App) void {
        if (self.stats.driver_work_sample_count == 0) return;
        var queue_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var run_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var e2e_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var index: usize = 0;
        while (index < self.stats.driver_work_sample_count) : (index += 1) {
            const sample = self.stats.driver_work_samples[index];
            queue_costs[index] = sample.queue_ns_per_started;
            run_costs[index] = sample.run_ns_per_completed;
            e2e_costs[index] = sample.e2e_ns_per_completed;
            self.sys.write("  Driver work sample=");
            self.sys.printU64(sample.repetition);
            self.sys.write(" owner=");
            self.sys.printU64(sample.owner);
            self.sys.write(" audio=");
            self.sys.printU64(sample.audio_writes);
            self.sys.write("/");
            self.sys.printU64(sample.audio_bytes);
            self.sys.write(" submit/start/done=");
            self.sys.printU64(sample.submitted);
            self.sys.write("/");
            self.sys.printU64(sample.started);
            self.sys.write("/");
            self.sys.printU64(sample.completed);
            self.sys.write(" deadline/miss/overrun=");
            self.sys.printU64(sample.deadline_completed);
            self.sys.write("/");
            self.sys.printU64(sample.deadline_misses);
            self.sys.write("/");
            self.sys.printU64(sample.deadline_budget_overruns);
            self.sys.write(" queueNs/work=");
            self.sys.printU64(sample.queue_ns_per_started);
            self.sys.write(" runNs/work=");
            self.sys.printU64(sample.run_ns_per_completed);
            self.sys.write(" e2eNs/work=");
            self.sys.printU64(sample.e2e_ns_per_completed);
            self.sys.write(" max=");
            self.sys.printU64(sample.queue_max_after_ns);
            self.sys.write("/");
            self.sys.printU64(sample.run_max_after_ns);
            self.sys.write("/");
            self.sys.printU64(sample.e2e_max_after_ns);
            self.sys.write(" slots=");
            self.sys.printU64(sample.free_slots_after);
            self.sys.write("/");
            self.sys.printU64(sample.used_slots_after);
            self.sys.write(" scan=");
            self.sys.printU64(sample.scan_passes);
            self.sys.write("/");
            self.sys.printU64(sample.scan_slots);
            self.sys.write(" irqOffMaxNs=");
            self.sys.printU64(sample.critical_max_after_ns);
            self.sys.write(" errors=");
            self.sys.printU64(sample.failed +% sample.dropped +% sample.full_rejections +% sample.invalid_handles +% sample.stale_handles);
            self.sys.println("");
        }
        self.printDriverWorkDistribution("queue", queue_costs[0..self.stats.driver_work_sample_count]);
        self.printDriverWorkDistribution("run", run_costs[0..self.stats.driver_work_sample_count]);
        self.printDriverWorkDistribution("e2e", e2e_costs[0..self.stats.driver_work_sample_count]);
    }

    fn printDriverWorkDistribution(self: *App, name: []const u8, values: []const u64) void {
        const distribution = measurement.summarize(values);
        self.sys.write("  Driver work distribution metric=");
        self.sys.write(name);
        self.sys.write(" unit=ns/work n=");
        self.sys.printU64(distribution.count);
        self.sys.write(" min=");
        self.sys.printU64(distribution.minimum);
        self.sys.write(" p50=");
        self.sys.printU64(distribution.p50);
        self.sys.write(" p95=");
        self.sys.printU64(distribution.p95);
        self.sys.write(" p99=");
        self.sys.printU64(distribution.p99);
        self.sys.write(" max=");
        self.sys.printU64(distribution.maximum);
        self.sys.write(" mean=");
        self.sys.printU64(distribution.mean);
        self.sys.println("");
    }

    fn probePciInventory(self: *App) bool {
        if (!self.dev.hasFn("performance_pci_inventory") or
            !self.dev.hasFn("device_inventory_summary") or
            !self.dev.hasFn("device_inventory_record") or
            !self.monotonic_clock_available) return false;

        self.stats.pci_inventory_sample_count = 0;
        var benchmark_ok = true;
        var expected_total: ?u64 = null;
        var repetition: u8 = 0;
        while (repetition < self.config.repetitions) : (repetition += 1) {
            const before = self.dev.performancePciInventory() orelse return false;
            if (!pciInventorySnapshotContractOk(before)) return false;

            var clock_start: r4os.abi.MonotonicClockInfo = .{};
            if (!self.queryMonotonicClock(&clock_start)) return false;
            var summaries: u64 = 0;
            var records: u64 = 0;
            var api_errors: u64 = 0;
            var checksum: u64 = 0xcbf29ce484222325;
            var iteration: u64 = 0;
            while (iteration < measurement.pci_inventory_iterations_per_sample) : (iteration += 1) {
                var summary: r4os.abi.DeviceInventorySummary = .{};
                if (self.dev.deviceInventorySummary(&summary) <= 0) {
                    api_errors +%= 1;
                    continue;
                }
                summaries +%= 1;
                const total: u64 = summary.total;
                if (expected_total) |expected| {
                    if (total != expected) api_errors +%= 1;
                } else {
                    expected_total = total;
                }
                mixServiceRegistryValue(&checksum, total);
                mixServiceRegistryValue(&checksum, summary.with_driver);
                mixServiceRegistryValue(&checksum, summary.without_driver);
                mixServiceRegistryValue(&checksum, summary.unknown);
                mixServiceRegistryValue(&checksum, summary.truncated);

                var index: u32 = 0;
                while (index < summary.total) : (index += 1) {
                    var record: r4os.abi.DeviceInventoryRecord = .{};
                    if (self.dev.deviceInventoryRecord(index, &record) <= 0) {
                        api_errors +%= 1;
                        break;
                    }
                    records +%= 1;
                    mixPciInventoryRecord(&checksum, record);
                }
            }
            var clock_end: r4os.abi.MonotonicClockInfo = .{};
            if (!self.queryMonotonicClock(&clock_end) or
                clock_end.generation != clock_start.generation or
                clock_end.instant_ns <= clock_start.instant_ns) return false;
            const after = self.dev.performancePciInventory() orelse return false;
            if (!pciInventorySnapshotContractOk(after)) return false;

            const elapsed_ns = clock_end.instant_ns - clock_start.instant_ns;
            const sample = PciInventorySample{
                .repetition = repetition + 1,
                .iterations = measurement.pci_inventory_iterations_per_sample,
                .summaries = summaries,
                .records = records,
                .api_errors = api_errors,
                .elapsed_ns = elapsed_ns,
                .ns_per_inventory = elapsed_ns / measurement.pci_inventory_iterations_per_sample,
                .ecam_read_delta = counterDelta(before.ecam_config_reads, after.ecam_config_reads),
                .ecam_write_delta = counterDelta(before.ecam_config_writes, after.ecam_config_writes),
                .legacy_read_delta = counterDelta(before.legacy_config_reads, after.legacy_config_reads),
                .legacy_write_delta = counterDelta(before.legacy_config_writes, after.legacy_config_writes),
                .mapping_check_delta = counterDelta(before.mapping_checks, after.mapping_checks),
                .mapping_miss_delta = counterDelta(before.mapping_misses, after.mapping_misses),
                .mapping_fast_delta = counterDelta(before.mapping_fast_accesses, after.mapping_fast_accesses),
                .invalid_access_delta = counterDelta(before.invalid_accesses, after.invalid_accesses),
                .class_find_delta = counterDelta(before.class_find_calls, after.class_find_calls),
                .detail_materialization_delta = counterDelta(before.detail_materializations, after.detail_materializations),
                .interrupt_read_delta = counterDelta(before.interrupt_dword_reads, after.interrupt_dword_reads),
                .command_read_delta = counterDelta(before.command_reads, after.command_reads),
                .bar_read_delta = counterDelta(before.bar_reads, after.bar_reads),
                .flags = after.flags,
                .generation = after.generation,
                .capacity = after.capacity,
                .found = after.found,
                .stored = after.stored,
                .dropped = after.dropped,
                .ecam_stored = after.ecam_stored,
                .legacy_stored = after.legacy_stored,
                .vendor_probes_ecam = after.vendor_probes_ecam,
                .vendor_probes_legacy = after.vendor_probes_legacy,
                .class_reads = after.class_reads,
                .header_reads = after.header_reads,
                .enumeration_config_reads = after.enumeration_config_reads,
                .function_pages = after.function_pages,
                .early_stops = after.early_stops,
                .ecam_config_reads = after.ecam_config_reads,
                .ecam_config_writes = after.ecam_config_writes,
                .legacy_config_reads = after.legacy_config_reads,
                .legacy_config_writes = after.legacy_config_writes,
                .mapping_checks = after.mapping_checks,
                .mapping_hits = after.mapping_hits,
                .mapping_misses = after.mapping_misses,
                .mapping_fast_accesses = after.mapping_fast_accesses,
                .invalid_accesses = after.invalid_accesses,
                .class_find_calls = after.class_find_calls,
                .class_candidates = after.class_candidates,
                .detail_materializations = after.detail_materializations,
                .interrupt_dword_reads = after.interrupt_dword_reads,
                .command_reads = after.command_reads,
                .bar_reads = after.bar_reads,
                .enumeration_total_ns = after.enumeration_total_ns,
                .ecam_enumeration_ns = after.ecam_enumeration_ns,
                .legacy_enumeration_ns = after.legacy_enumeration_ns,
                .timing_unavailable = after.timing_unavailable,
                .checksum = checksum,
            };
            self.stats.pci_inventory_samples[self.stats.pci_inventory_sample_count] = sample;
            self.stats.pci_inventory_sample_count += 1;
            pci_inventory_benchmark_sink +%= checksum;

            const expected_records = (expected_total orelse 0) * sample.summaries;
            const sample_ok = before.generation == after.generation and
                before.flags == after.flags and
                sample.summaries == sample.iterations and
                sample.records == expected_records and
                sample.api_errors == 0 and
                sample.ecam_read_delta == 0 and sample.ecam_write_delta == 0 and
                sample.legacy_read_delta == 0 and sample.legacy_write_delta == 0 and
                sample.mapping_check_delta == 0 and sample.mapping_miss_delta == 0 and
                sample.mapping_fast_delta == 0 and sample.invalid_access_delta == 0 and
                sample.class_find_delta == 0 and sample.detail_materialization_delta == 0 and
                sample.interrupt_read_delta == 0 and sample.command_read_delta == 0 and
                sample.bar_read_delta == 0;
            benchmark_ok = sample_ok and benchmark_ok;
        }
        return benchmark_ok and self.stats.pci_inventory_sample_count == self.config.repetitions;
    }

    fn printPciInventoryResults(self: *App) void {
        if (self.stats.pci_inventory_sample_count == 0) return;
        var costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var index: usize = 0;
        while (index < self.stats.pci_inventory_sample_count) : (index += 1) {
            const sample = self.stats.pci_inventory_samples[index];
            costs[index] = sample.ns_per_inventory;
            self.sys.write("  PCI inventory sample=");
            self.sys.printU64(sample.repetition);
            self.sys.write(" inventory/records=");
            self.sys.printU64(sample.summaries);
            self.sys.write("/");
            self.sys.printU64(sample.records);
            self.sys.write(" ns/inventory=");
            self.sys.printU64(sample.ns_per_inventory);
            self.sys.write(" found/stored/dropped=");
            self.sys.printU64(sample.found);
            self.sys.write("/");
            self.sys.printU64(sample.stored);
            self.sys.write("/");
            self.sys.printU64(sample.dropped);
            self.sys.write(" probes(ecam/legacy)=");
            self.sys.printU64(sample.vendor_probes_ecam);
            self.sys.write("/");
            self.sys.printU64(sample.vendor_probes_legacy);
            self.sys.write(" configDelta=");
            self.sys.printU64(sample.ecam_read_delta +% sample.legacy_read_delta);
            self.sys.write(" mapDelta=");
            self.sys.printU64(sample.mapping_check_delta);
            self.sys.write(" errors=");
            self.sys.printU64(sample.api_errors);
            self.sys.println("");
        }
        const distribution = measurement.summarize(costs[0..self.stats.pci_inventory_sample_count]);
        self.sys.write("  PCI inventory distribution ns/inventory: n=");
        self.sys.printU64(distribution.count);
        self.sys.write(" min=");
        self.sys.printU64(distribution.minimum);
        self.sys.write(" p50=");
        self.sys.printU64(distribution.p50);
        self.sys.write(" p95=");
        self.sys.printU64(distribution.p95);
        self.sys.write(" p99=");
        self.sys.printU64(distribution.p99);
        self.sys.write(" max=");
        self.sys.printU64(distribution.maximum);
        self.sys.write(" mean=");
        self.sys.printU64(distribution.mean);
        self.sys.println("");
    }

    fn probeMemoryMetadata(self: *App) bool {
        if (!self.monotonic_clock_available or
            !self.sys.hasFn("vm_reserve") or
            !self.sys.hasFn("vm_commit") or
            !self.sys.hasFn("vm_release") or
            !self.dev.hasFn("performance_summary") or
            !self.dev.hasFn("memory_backing_store_probe") or
            !self.dev.hasFn("memory_backing_store_slot_probe") or
            !self.dev.hasFn("memory_vm_page_state_probe") or
            !self.dev.hasFn("memory_reclaim_probe")) return self.memoryMetadataBenchmarkFailure("required-api");

        if (!self.writeBackingStoreFile(memory_metadata_backing_store_path, memory_metadata_backing_store_bytes)) return self.memoryMetadataBenchmarkFailure("backing-write");
        const backing = self.dev.memoryBackingStoreProbe(memory_metadata_backing_store_path, memory_metadata_backing_store_bytes, 0) orelse return self.memoryMetadataBenchmarkFailure("backing-probe");
        if (backing.version != r4os.abi.memory_backing_store_probe_version or
            backing.size < @sizeOf(r4os.abi.ProgramMemoryBackingStoreProbe) or
            backing.status != r4os.abi.memory_backing_store_status_ready or
            backing.blockers != 0 or
            !backingStoreReadyFlagsOk(backing.flags) or
            backing.available_bytes < memory_metadata_backing_store_bytes) return self.memoryMetadataBenchmarkFailure("backing-contract");
        const slots = self.dev.memoryBackingStoreSlotProbe(
            memory_metadata_backing_store_path,
            memory_metadata_backing_store_bytes,
            r4os.abi.memory_backing_store_slot_operation_probe,
            0,
            0,
            r4os.abi.memory_backing_store_slot_owner_kind_diagnostic,
            backing_store_slot_owner,
            0,
            0,
        ) orelse return self.memoryMetadataBenchmarkFailure("backing-slots-probe");
        if (slots.status != r4os.abi.memory_backing_store_slot_status_ready or
            slots.blockers != 0 or
            slots.capacity_slots < measurement.memory_metadata_pages_per_sample or
            slots.reserved_slots != 0)
        {
            return self.memoryMetadataBenchmarkFailure("backing-slots-contract");
        }

        self.stats.memory_metadata_sample_count = 0;
        var benchmark_ok = true;
        var repetition: u8 = 0;
        while (repetition < self.config.repetitions) : (repetition += 1) {
            const sample = self.probeMemoryMetadataSample(repetition + 1) orelse return false;
            self.stats.memory_metadata_samples[self.stats.memory_metadata_sample_count] = sample;
            self.stats.memory_metadata_sample_count += 1;
            benchmark_ok = memoryMetadataSampleOk(sample) and benchmark_ok;
        }
        return benchmark_ok and self.stats.memory_metadata_sample_count == self.config.repetitions;
    }

    fn probeMemoryMetadataSample(self: *App, repetition: u8) ?MemoryMetadataSample {
        const pages = measurement.memory_metadata_pages_per_sample;
        const bytes = pages * 4096;
        const before = self.captureSummary() orelse return self.memoryMetadataSampleFailure(repetition, "summary-before");
        if (!memoryMetadataSummaryContractOk(before)) return self.memoryMetadataSampleFailure(repetition, "summary-before-contract");

        var reserve_start: r4os.abi.MonotonicClockInfo = .{};
        if (!self.queryMonotonicClock(&reserve_start)) return self.memoryMetadataSampleFailure(repetition, "reserve-clock-start");
        const region = self.sys.vmReserve(bytes, 4096, r4os.abi.vm_region_flags_default) orelse return self.memoryMetadataSampleFailure(repetition, "reserve");
        var release_needed = true;
        defer {
            if (release_needed) _ = self.sys.vmRelease(region.id);
        }
        if (self.sys.vmCommit(region.id, 0, bytes) != r4os.abi.vm_ok) return self.memoryMetadataSampleFailure(repetition, "commit");
        var reserve_end: r4os.abi.MonotonicClockInfo = .{};
        if (!self.queryMonotonicClock(&reserve_end) or !sameClockInterval(reserve_start, reserve_end)) return self.memoryMetadataSampleFailure(repetition, "reserve-clock-end");

        var fault_start: r4os.abi.MonotonicClockInfo = .{};
        if (!self.queryMonotonicClock(&fault_start)) return self.memoryMetadataSampleFailure(repetition, "fault-clock-start");
        const ptr: [*]volatile u8 = @ptrFromInt(region.base);
        var page_index: u64 = 0;
        while (page_index < pages) : (page_index += 1) {
            ptr[page_index * 4096] = @truncate(@as(u64, repetition) *% 29 +% page_index *% 17 +% 0x41);
        }
        var fault_end: r4os.abi.MonotonicClockInfo = .{};
        if (!self.queryMonotonicClock(&fault_end) or !sameClockInterval(fault_start, fault_end)) return self.memoryMetadataSampleFailure(repetition, "fault-clock-end");

        var state_start: r4os.abi.MonotonicClockInfo = .{};
        if (!self.queryMonotonicClock(&state_start)) return self.memoryMetadataSampleFailure(repetition, "page-state-clock-start");
        const clean_state = self.dev.memoryVmPageStateProbe(
            region.id,
            0,
            pages,
            r4os.abi.memory_vm_page_state_operation_mark_clean,
            0,
            0,
            0,
            0,
        ) orelse return self.memoryMetadataSampleFailure(repetition, "page-state-probe");
        var state_end: r4os.abi.MonotonicClockInfo = .{};
        if (!self.queryMonotonicClock(&state_end) or !sameClockInterval(state_start, state_end)) return self.memoryMetadataSampleFailure(repetition, "page-state-clock-end");
        if (clean_state.status != r4os.abi.memory_vm_page_state_status_ready or
            clean_state.committed_pages != pages or clean_state.resident_pages != pages or
            clean_state.clean_pages != pages or clean_state.dirty_pages != 0)
        {
            self.printMemoryMetadataPageStateFailure("page-state-clean", clean_state);
            return self.memoryMetadataSampleFailure(repetition, "page-state-clean");
        }

        const frame_bytes: u64 = if (before.fs_cache_payload_frame_bytes == 0) 4096 else before.fs_cache_payload_frame_bytes;
        var remaining_fs_frames = before.fs_cache_pmm_reclaimable_bytes / frame_bytes;
        var requested_frames: u32 = @intCast(@min(remaining_fs_frames + pages, @as(u64, 1024)));
        if (requested_frames == 0) requested_frames = 1;

        var reclaim_start: r4os.abi.MonotonicClockInfo = .{};
        if (!self.queryMonotonicClock(&reclaim_start)) return self.memoryMetadataSampleFailure(repetition, "reclaim-clock-start");
        var reclaim_attempts: u32 = 0;
        var reclaim_requested_frames: u64 = 0;
        var reclaim_returned_frames: u64 = 0;
        var reclaim_fs_returned_frames: u64 = 0;
        var reclaim_vm_returned_frames: u64 = 0;
        var reclaim_vm_page_outs: u64 = 0;
        var reclaim_vm_failures: u64 = 0;
        while (reclaim_attempts < measurement.memory_metadata_reclaim_max_attempts and
            reclaim_vm_returned_frames < pages) : (reclaim_attempts += 1)
        {
            const current = self.dev.memoryReclaimProbe(requested_frames) orelse return self.memoryMetadataSampleFailure(repetition, "reclaim-probe");
            reclaim_requested_frames +%= current.requested_frames;
            reclaim_returned_frames +%= current.returned_frames;
            reclaim_fs_returned_frames +%= current.fs_returned_frames;
            reclaim_vm_returned_frames +%= current.vm_returned_frames;
            reclaim_vm_page_outs +%= current.vm_page_outs;
            reclaim_vm_failures +%= current.vm_failures;

            const returned_fs_frames: u64 = current.fs_returned_frames;
            remaining_fs_frames = if (returned_fs_frames >= remaining_fs_frames)
                0
            else
                remaining_fs_frames - returned_fs_frames;
            const missing_vm_frames = pages -| reclaim_vm_returned_frames;
            requested_frames = @intCast(@min(remaining_fs_frames + @max(missing_vm_frames, 1), @as(u64, 1024)));
            if (requested_frames == 0) requested_frames = 1;
        }
        const attempts_made = reclaim_attempts;
        var reclaim_end: r4os.abi.MonotonicClockInfo = .{};
        if (!self.queryMonotonicClock(&reclaim_end) or !sameClockInterval(reclaim_start, reclaim_end)) return self.memoryMetadataSampleFailure(repetition, "reclaim-clock-end");

        const final_state = self.dev.memoryVmPageStateProbe(
            region.id,
            0,
            pages,
            r4os.abi.memory_vm_page_state_operation_query,
            0,
            0,
            0,
            0,
        ) orelse return self.memoryMetadataSampleFailure(repetition, "page-state-final-probe");
        if (final_state.status != r4os.abi.memory_vm_page_state_status_ready) {
            self.printMemoryMetadataPageStateFailure("page-state-final", final_state);
            return self.memoryMetadataSampleFailure(repetition, "page-state-final");
        }
        const after = self.captureSummary() orelse return self.memoryMetadataSampleFailure(repetition, "summary-after");
        if (!memoryMetadataSummaryContractOk(after)) return self.memoryMetadataSampleFailure(repetition, "summary-after-contract");

        const reserve_commit_elapsed_ns = reserve_end.instant_ns - reserve_start.instant_ns;
        const fault_elapsed_ns = fault_end.instant_ns - fault_start.instant_ns;
        const page_state_elapsed_ns = state_end.instant_ns - state_start.instant_ns;
        const reclaim_elapsed_ns = reclaim_end.instant_ns - reclaim_start.instant_ns;
        const sample = MemoryMetadataSample{
            .repetition = repetition,
            .pages = pages,
            .reserve_commit_elapsed_ns = reserve_commit_elapsed_ns,
            .reserve_commit_ns_per_page = perUnitCost(reserve_commit_elapsed_ns, pages),
            .fault_elapsed_ns = fault_elapsed_ns,
            .fault_ns_per_page = perUnitCost(fault_elapsed_ns, pages),
            .page_state_elapsed_ns = page_state_elapsed_ns,
            .page_state_ns_per_page = perUnitCost(page_state_elapsed_ns, pages),
            .reclaim_elapsed_ns = reclaim_elapsed_ns,
            .reclaim_ns_per_vm_frame = perUnitCost(reclaim_elapsed_ns, reclaim_vm_returned_frames),
            .reclaim_attempts = attempts_made,
            .reclaim_requested_frames = reclaim_requested_frames,
            .reclaim_returned_frames = reclaim_returned_frames,
            .reclaim_fs_returned_frames = reclaim_fs_returned_frames,
            .reclaim_vm_returned_frames = reclaim_vm_returned_frames,
            .reclaim_vm_page_outs = reclaim_vm_page_outs,
            .reclaim_vm_failures = reclaim_vm_failures,
            .target_committed_pages = final_state.committed_pages,
            .target_resident_pages = final_state.resident_pages,
            .target_nonresident_pages = final_state.nonresident_pages,
            .target_clean_pages = final_state.clean_pages,
            .target_slot_bound_pages = final_state.slot_bound_pages,
            .block_physical_index_entries = after.hot_path_memory_block_physical_index_entries,
            .block_physical_step_max = after.hot_path_memory_block_physical_step_max,
            .block_id_index_entries = after.hot_path_memory_block_id_index_entries,
            .block_id_step_max = after.hot_path_memory_block_id_step_max,
            .block_free_slot_word_step_max = after.hot_path_memory_block_free_slot_word_step_max,
            .range_address_entries = after.hot_path_memory_vm_range_address_entries,
            .range_address_probe_max = after.hot_path_memory_vm_range_address_probe_max,
            .commit_span_active = after.hot_path_memory_vm_commit_span_active,
            .commit_span_step_max = after.hot_path_memory_vm_commit_span_step_max,
            .page_state_span_active = after.hot_path_memory_vm_page_state_span_active,
            .page_state_span_step_max = after.hot_path_memory_vm_page_state_span_step_max,
            .block_physical_lookups = counterDelta(before.hot_path_memory_block_physical_lookups, after.hot_path_memory_block_physical_lookups),
            .block_physical_steps = counterDelta(before.hot_path_memory_block_physical_steps, after.hot_path_memory_block_physical_steps),
            .block_physical_mutations = counterDelta(before.hot_path_memory_block_physical_mutations, after.hot_path_memory_block_physical_mutations),
            .block_physical_rebuilds = counterDelta(before.hot_path_memory_block_physical_rebuilds, after.hot_path_memory_block_physical_rebuilds),
            .block_id_lookups = counterDelta(before.hot_path_memory_block_id_lookups, after.hot_path_memory_block_id_lookups),
            .block_id_steps = counterDelta(before.hot_path_memory_block_id_steps, after.hot_path_memory_block_id_steps),
            .block_free_slot_lookups = counterDelta(before.hot_path_memory_block_free_slot_lookups, after.hot_path_memory_block_free_slot_lookups),
            .block_free_slot_word_steps = counterDelta(before.hot_path_memory_block_free_slot_word_steps, after.hot_path_memory_block_free_slot_word_steps),
            .block_claim_transactions = counterDelta(before.hot_path_memory_block_claim_transactions, after.hot_path_memory_block_claim_transactions),
            .block_claim_rollbacks = counterDelta(before.hot_path_memory_block_claim_rollbacks, after.hot_path_memory_block_claim_rollbacks),
            .range_address_lookups = counterDelta(before.hot_path_memory_vm_range_address_lookups, after.hot_path_memory_vm_range_address_lookups),
            .range_address_probes = counterDelta(before.hot_path_memory_vm_range_address_probe_total, after.hot_path_memory_vm_range_address_probe_total),
            .commit_span_lookups = counterDelta(before.hot_path_memory_vm_commit_span_lookups, after.hot_path_memory_vm_commit_span_lookups),
            .commit_span_steps = counterDelta(before.hot_path_memory_vm_commit_span_steps, after.hot_path_memory_vm_commit_span_steps),
            .page_state_span_lookups = counterDelta(before.hot_path_memory_vm_page_state_span_lookups, after.hot_path_memory_vm_page_state_span_lookups),
            .page_state_span_steps = counterDelta(before.hot_path_memory_vm_page_state_span_steps, after.hot_path_memory_vm_page_state_span_steps),
            .reclaim_range_steps = counterDelta(before.hot_path_memory_vm_reclaim_range_steps, after.hot_path_memory_vm_reclaim_range_steps),
            .reclaim_span_steps = counterDelta(before.hot_path_memory_vm_reclaim_span_steps, after.hot_path_memory_vm_reclaim_span_steps),
            .reclaim_page_steps = counterDelta(before.hot_path_memory_vm_reclaim_page_steps, after.hot_path_memory_vm_reclaim_page_steps),
            .reclaim_wraps = counterDelta(before.hot_path_memory_vm_reclaim_wraps, after.hot_path_memory_vm_reclaim_wraps),
        };
        if (self.sys.vmRelease(region.id) != r4os.abi.vm_ok) return self.memoryMetadataSampleFailure(repetition, "release");
        release_needed = false;
        return sample;
    }

    fn memoryMetadataBenchmarkFailure(self: *App, stage: []const u8) bool {
        self.sys.write("  Memory metadata benchmark failure: stage=");
        self.sys.println(stage);
        return false;
    }

    fn memoryMetadataSampleFailure(self: *App, repetition: u8, stage: []const u8) ?MemoryMetadataSample {
        self.sys.write("  Memory metadata sample failure: repetition=");
        self.sys.printU64(repetition);
        self.sys.write(" stage=");
        self.sys.println(stage);
        return null;
    }

    fn printMemoryMetadataPageStateFailure(self: *App, stage: []const u8, state: r4os.abi.ProgramMemoryVmPageStateProbe) void {
        self.sys.write("  Memory metadata page-state failure: stage=");
        self.sys.write(stage);
        self.sys.write(" status=");
        self.sys.printU64(state.status);
        self.sys.write(" blockers=");
        self.sys.printU64(state.blockers);
        self.sys.write(" committed=");
        self.sys.printU64(state.committed_pages);
        self.sys.write(" resident=");
        self.sys.printU64(state.resident_pages);
        self.sys.write(" clean=");
        self.sys.printU64(state.clean_pages);
        self.sys.write(" dirty=");
        self.sys.printU64(state.dirty_pages);
        self.sys.write(" spans=");
        self.sys.printU64(state.span_count);
        self.sys.println("");
    }

    fn printMemoryMetadataResults(self: *App) void {
        if (self.stats.memory_metadata_sample_count == 0) return;
        var reserve_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var fault_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var state_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var reclaim_costs: [measurement.max_repetitions]u64 = .{0} ** measurement.max_repetitions;
        var index: usize = 0;
        while (index < self.stats.memory_metadata_sample_count) : (index += 1) {
            const sample = self.stats.memory_metadata_samples[index];
            reserve_costs[index] = sample.reserve_commit_ns_per_page;
            fault_costs[index] = sample.fault_ns_per_page;
            state_costs[index] = sample.page_state_ns_per_page;
            reclaim_costs[index] = sample.reclaim_ns_per_vm_frame;
            self.sys.write("  Memory metadata sample=");
            self.sys.printU64(sample.repetition);
            self.sys.write(" ns/page(reserve+commit/fault/state)=");
            self.sys.printU64(sample.reserve_commit_ns_per_page);
            self.sys.write("/");
            self.sys.printU64(sample.fault_ns_per_page);
            self.sys.write("/");
            self.sys.printU64(sample.page_state_ns_per_page);
            self.sys.write(" reclaimNs/frame=");
            self.sys.printU64(sample.reclaim_ns_per_vm_frame);
            self.sys.write(" vmFrames/pageOut=");
            self.sys.printU64(sample.reclaim_vm_returned_frames);
            self.sys.write("/");
            self.sys.printU64(sample.reclaim_vm_page_outs);
            self.sys.write(" indexMax(block/range/commit/state)=");
            self.sys.printU64(sample.block_physical_step_max);
            self.sys.write("/");
            self.sys.printU64(sample.range_address_probe_max);
            self.sys.write("/");
            self.sys.printU64(sample.commit_span_step_max);
            self.sys.write("/");
            self.sys.printU64(sample.page_state_span_step_max);
            self.sys.write(" reclaimSteps(range/span/page)=");
            self.sys.printU64(sample.reclaim_range_steps);
            self.sys.write("/");
            self.sys.printU64(sample.reclaim_span_steps);
            self.sys.write("/");
            self.sys.printU64(sample.reclaim_page_steps);
            self.sys.println("");
        }
        self.printMemoryMetadataHumanDistribution("reserve+commit", reserve_costs[0..self.stats.memory_metadata_sample_count], "ns/page");
        self.printMemoryMetadataHumanDistribution("fault", fault_costs[0..self.stats.memory_metadata_sample_count], "ns/page");
        self.printMemoryMetadataHumanDistribution("page-state", state_costs[0..self.stats.memory_metadata_sample_count], "ns/page");
        self.printMemoryMetadataHumanDistribution("reclaim", reclaim_costs[0..self.stats.memory_metadata_sample_count], "ns/frame");
    }

    fn printMemoryMetadataHumanDistribution(self: *App, metric: []const u8, values: []const u64, unit: []const u8) void {
        const distribution = measurement.summarize(values);
        self.sys.write("  Memory metadata ");
        self.sys.write(metric);
        self.sys.write(" distribution ");
        self.sys.write(unit);
        self.sys.write(": n=");
        self.sys.printU64(distribution.count);
        self.sys.write(" min=");
        self.sys.printU64(distribution.minimum);
        self.sys.write(" p50=");
        self.sys.printU64(distribution.p50);
        self.sys.write(" p95=");
        self.sys.printU64(distribution.p95);
        self.sys.write(" p99=");
        self.sys.printU64(distribution.p99);
        self.sys.write(" max=");
        self.sys.printU64(distribution.maximum);
        self.sys.write(" mean=");
        self.sys.printU64(distribution.mean);
        self.sys.println("");
    }

    fn probeAudioLatency(self: *App) bool {
        if (!self.dev.hasFn("performance_summary")) {
            self.printCheck("Audio write conformance", false);
            return false;
        }
        const before = self.captureSummary() orelse {
            self.printCheck("Audio write conformance", false);
            return false;
        };
        var pcm: [4096]u8 = undefined;
        var frame: usize = 0;
        while (frame < pcm.len / 4) : (frame += 1) {
            const sample: i16 = if (((frame / 32) & 1) == 0) 2200 else -2200;
            const bits: u16 = @bitCast(sample);
            const offset = frame * 4;
            pcm[offset] = @intCast(bits & 0xFF);
            pcm[offset + 1] = @intCast(bits >> 8);
            pcm[offset + 2] = pcm[offset];
            pcm[offset + 3] = pcm[offset + 1];
        }

        const stream = self.audio.audioOpenStream(48_000, 2, .s16le);
        if (stream < 0) {
            self.printCheck("Audio write conformance", false);
            return false;
        }
        const stream_id: u32 = @intCast(stream);
        const written = self.audio.audioWrite(stream_id, pcm[0..]);
        const closed = self.audio.audioClose(stream_id);
        const after = self.captureSummary() orelse {
            self.printCheck("Audio write conformance", false);
            return false;
        };
        const ok = written == @as(i32, @intCast(pcm.len)) and
            closed == 0 and
            after.audio_stream_writes > before.audio_stream_writes and
            after.audio_stream_high_water_bytes >= before.audio_stream_high_water_bytes and
            after.audio_stream_write_total_ticks >= before.audio_stream_write_total_ticks and
            after.audio_stream_write_max_ticks >= after.audio_stream_write_last_ticks and
            after.audio_backend_write_total_ticks >= before.audio_backend_write_total_ticks and
            after.audio_backend_write_max_ticks >= after.audio_backend_write_last_ticks and
            after.audio_stream_dropped_bytes == before.audio_stream_dropped_bytes;
        self.printCheck("Audio write conformance", ok);
        if (!ok) {
            self.sys.write("  audio writes=");
            self.sys.printU64(before.audio_stream_writes);
            self.sys.write("->");
            self.sys.printU64(after.audio_stream_writes);
            self.sys.write(" high=");
            self.sys.printU64(after.audio_stream_high_water_bytes);
            self.sys.write(" ticks=");
            self.sys.printU64(after.audio_stream_write_last_ticks);
            self.sys.write("/");
            self.sys.printU64(after.audio_stream_write_max_ticks);
            self.sys.write(" backend=");
            self.sys.printU64(after.audio_backend_write_last_ticks);
            self.sys.write("/");
            self.sys.printU64(after.audio_backend_write_max_ticks);
            self.sys.write(" rc=");
            self.sys.printI32(written);
            self.sys.write("/");
            self.sys.printI32(closed);
            self.sys.println("");
        }
        return ok;
    }

    fn testFpuState(self: *App, summary: r4os.abi.ProgramPerformanceSummary) bool {
        const backend_ok = summary.fpu_state_backend == r4os.abi.performance_fpu_backend_fxsave or
            summary.fpu_state_backend == r4os.abi.performance_fpu_backend_xsave;
        const xcr0_ok = summary.fpu_state_backend == r4os.abi.performance_fpu_backend_fxsave or
            (summary.fpu_xcr0_mask & 0x3) == 0x3;
        const task_bytes_min = @as(u64, summary.fpu_task_state_count) * @as(u64, summary.fpu_state_bytes);
        const ok = summary.fpu_state_supported == 1 and
            summary.fpu_state_enabled == 1 and
            backend_ok and
            summary.fpu_state_bytes >= 512 and
            summary.fpu_state_storage_bytes >= summary.fpu_state_bytes and
            summary.fpu_task_state_count > 0 and
            summary.fpu_task_init_count >= summary.fpu_task_state_count and
            summary.fpu_task_state_bytes >= task_bytes_min and
            summary.fpu_save_count > 0 and
            summary.fpu_restore_count > 0 and
            xcr0_ok;
        self.printCheck("FPU/SSE task state", ok);
        if (!ok) {
            self.sys.write("  fpu supported=");
            self.sys.printU64(summary.fpu_state_supported);
            self.sys.write(" enabled=");
            self.sys.printU64(summary.fpu_state_enabled);
            self.sys.write(" backend=");
            self.sys.printU64(summary.fpu_state_backend);
            self.sys.write(" bytes=");
            self.sys.printU64(summary.fpu_state_bytes);
            self.sys.write("/");
            self.sys.printU64(summary.fpu_state_storage_bytes);
            self.sys.write(" tasks=");
            self.sys.printU64(summary.fpu_task_state_count);
            self.sys.write(" init=");
            self.sys.printU64(summary.fpu_task_init_count);
            self.sys.write(" save=");
            self.sys.printU64(summary.fpu_save_count);
            self.sys.write(" restore=");
            self.sys.printU64(summary.fpu_restore_count);
            self.sys.write(" xcr0=");
            self.sys.printU64(summary.fpu_xcr0_mask);
            self.sys.println("");
        }
        return ok;
    }

    fn testAvxState(self: *App, summary: r4os.abi.ProgramPerformanceSummary) bool {
        const ok = (summary.flags & r4os.abi.performance_flag_avx_state_ready) != 0 and
            summary.fpu_state_backend == r4os.abi.performance_fpu_backend_xsave and
            summary.fpu_avx_supported == 1 and
            summary.fpu_avx_enabled == 1 and
            summary.fpu_avx2_supported == 1 and
            summary.fpu_avx2_enabled == 1 and
            summary.fpu_simd_abi == r4os.abi.performance_simd_abi_avx2 and
            summary.fpu_xsave_required_bytes == summary.fpu_state_bytes and
            summary.fpu_state_bytes >= 832 and
            summary.fpu_state_storage_bytes >= summary.fpu_state_bytes and
            (summary.fpu_xcr0_mask & 0x7) == 0x7;
        self.printCheck("AVX/AVX2 SIMD ABI", ok);
        if (!ok) self.printAvxFailure("summary", summary, 0, 0, avx_worker_results[0], avx_worker_results[1]);
        return ok;
    }

    fn testDriverWork(self: *App, summary: r4os.abi.ProgramPerformanceSummary) bool {
        const compact = self.dev.performanceDriverWork(0) orelse {
            self.printCheck("Driver workqueue completion", false);
            return false;
        };
        const submitted_by_source = summary.driver_work_submitted_from_irq +% summary.driver_work_submitted_from_task;
        const terminal_items = summary.driver_work_completed +% summary.driver_work_cancelled;
        const compact_ok = driverWorkSnapshotContractOk(compact) and
            compact.metrics.failed == summary.driver_work_failed and
            compact.metrics.dropped == summary.driver_work_dropped and
            compact.metrics.wait_timeouts == summary.driver_work_wait_timeouts and
            compact.metrics.invalid_handles +% compact.metrics.stale_handles == summary.driver_work_invalid_handles and
            compact.deadline_started <= compact.deadline_submitted and
            compact.deadline_completed <= compact.deadline_started and
            compact.deadline_budget_overruns == 0 and
            compact.deadline_queue_rejections == 0;
        const ok = (summary.flags & r4os.abi.performance_flag_driver_workqueue_ready) != 0 and
            compact_ok and
            summary.driver_work_worker_started != 0 and
            summary.driver_work_capacity >= r4os.abi.driver_work_queue_capacity and
            summary.driver_work_depth <= summary.driver_work_capacity and
            summary.driver_work_high_water <= summary.driver_work_capacity and
            summary.driver_work_submitted == submitted_by_source and
            summary.driver_work_started <= summary.driver_work_submitted and
            terminal_items <= summary.driver_work_started and
            summary.driver_work_failed == 0 and
            summary.driver_work_dropped == 0 and
            summary.driver_work_wait_timeouts == 0 and
            summary.driver_work_wait_denied_irq == 0 and
            summary.driver_work_invalid_handles == 0;
        self.printCheck("Driver workqueue completion", ok);
        if (!ok) {
            self.sys.write("  driver-work cap=");
            self.sys.printU64(summary.driver_work_capacity);
            self.sys.write(" high=");
            self.sys.printU64(summary.driver_work_high_water);
            self.sys.write(" irq=");
            self.sys.printU64(summary.driver_work_submitted_from_irq);
            self.sys.write(" task=");
            self.sys.printU64(summary.driver_work_submitted_from_task);
            self.sys.write(" started=");
            self.sys.printU64(summary.driver_work_started);
            self.sys.write(" done=");
            self.sys.printU64(summary.driver_work_completed);
            self.sys.write(" fail=");
            self.sys.printU64(summary.driver_work_failed);
            self.sys.write(" waits=");
            self.sys.printU64(summary.driver_work_waits);
            self.sys.write(" timeouts=");
            self.sys.printU64(summary.driver_work_wait_timeouts);
            self.sys.write(" dropped=");
            self.sys.printU64(summary.driver_work_dropped);
            self.sys.write(" used/retained=");
            self.sys.printU64(compact.used_slots);
            self.sys.write("/");
            self.sys.printU64(compact.completed_slots + compact.cancelled_slots);
            self.sys.write(" scan=");
            self.sys.printU64(compact.metrics.scan_passes);
            self.sys.write(" irqOffMaxNs=");
            self.sys.printU64(compact.metrics.critical_max_ns);
            self.sys.write(" deadline/miss/overrun/reject=");
            self.sys.printU64(compact.deadline_completed);
            self.sys.write("/");
            self.sys.printU64(compact.deadline_misses);
            self.sys.write("/");
            self.sys.printU64(compact.deadline_budget_overruns);
            self.sys.write("/");
            self.sys.printU64(compact.deadline_queue_rejections);
            self.sys.println("");
        }
        return ok;
    }

    fn testTasks(self: *App, summary: r4os.abi.ProgramPerformanceSummary) bool {
        var seen_running = false;
        var stack_ok = true;
        var i: u32 = 0;
        while (i < summary.task_count) : (i += 1) {
            const info = self.dev.performanceTask(i) orelse return self.failBool("Task performance entry unavailable");
            if (info.state == task_state_running) seen_running = true;
            const active = info.state == task_state_ready or
                info.state == task_state_running or
                info.state == task_state_blocked;
            if (!active) {
                if (info.state != task_state_unused and info.state != task_state_dead) stack_ok = false;
                if (i < 3) self.printTask(info);
                continue;
            }
            if (info.stack_bytes == 0 or info.stack_top <= info.stack_base) stack_ok = false;
            if (info.max_ready_latency_ticks < info.last_ready_latency_ticks or
                info.max_wait_ticks < info.last_wait_ticks or
                info.max_preemption_deferred_ticks > summary.scheduler_preemption_deferred_max_ticks)
            {
                stack_ok = false;
            }
            if (i < 3) self.printTask(info);
        }
        const ok = seen_running and stack_ok;
        self.printCheck("Task runtime baseline", ok);
        return ok;
    }

    fn testStorage(self: *App, summary: r4os.abi.ProgramPerformanceSummary) bool {
        var checked: u32 = 0;
        var active: u32 = 0;
        var ok = true;
        const worker_ok = (summary.flags & r4os.abi.performance_flag_storage_driver_completion_ready) != 0 and
            summary.storage_worker_started != 0 and
            summary.storage_worker_runtime_requests > 0 and
            summary.storage_worker_runtime_completions > 0 and
            summary.storage_completion_signals > 0 and
            summary.storage_boot_inline_requests > 0;
        var i: u32 = 0;
        while (i < summary.storage_device_count and i < 4) : (i += 1) {
            const info = self.dev.performanceStorage(i) orelse return self.failBool("Storage performance entry unavailable");
            checked += 1;
            if (storagePerformanceActive(info)) active += 1;
            if (!storagePerformanceOk(info)) ok = false;
            self.printStorage(info);
        }
        ok = ok and checked > 0 and active > 0 and worker_ok;
        self.printCheck("Storage driver completion", worker_ok);
        self.printCheck("Storage counter conformance", ok);
        return ok;
    }

    fn testBootPhases(self: *App, summary: r4os.abi.ProgramPerformanceSummary) bool {
        var saw_runtime = false;
        var checked: u32 = 0;
        var clock_available: u32 = 0;
        var clock_unavailable: u32 = 0;
        var shape_ok = true;
        var i: u32 = 0;
        while (i < summary.boot_phase_count) : (i += 1) {
            const phase = self.dev.performanceBootPhase(i) orelse return self.failBool("Boot phase performance entry unavailable");
            const clock = self.dev.performanceBootPhaseClock(i) orelse return self.failBool("Boot phase clock entry unavailable");
            checked += 1;
            if (phase.phase == 13) saw_runtime = true;
            const valid = (clock.clock_flags & r4os.abi.monotonic_clock_flag_valid) != 0;
            if (valid) {
                clock_available += 1;
                shape_ok = shape_ok and clock.last_ns >= clock.first_ns;
            } else {
                clock_unavailable += 1;
                shape_ok = shape_ok and clock.unavailable_spans > 0;
            }
            shape_ok = shape_ok and
                clock.version == 1 and
                clock.size >= @sizeOf(r4os.abi.ProgramBootPhaseClockInfo) and
                clock.index == i and
                clock.phase == phase.phase and
                clock.transitions == phase.transitions;
            if (i < 12) {
                self.printBootPhase(phase);
                self.printBootPhaseClock(clock);
            }
        }
        const ok = checked > 0 and saw_runtime and shape_ok and
            clock_available + clock_unavailable == checked and
            clock_available > 0;
        self.printCheck("Boot phase conformance", ok);
        return ok;
    }

    fn testIrqTiming(self: *App) bool {
        const required_coverage = r4os.abi.performance_irq_coverage_dispatch |
            r4os.abi.performance_irq_coverage_external_handler |
            r4os.abi.performance_irq_coverage_delivery_unavailable;
        var checked: u32 = 0;
        var registered: u32 = 0;
        var measured: u32 = 0;
        var ok = true;
        var irq: u32 = 0;
        while (irq < 32) : (irq += 1) {
            const info = self.dev.performanceIrqTiming(irq) orelse return self.failBool("IRQ timing entry unavailable");
            checked += 1;
            ok = ok and
                info.version == 1 and
                info.size >= @sizeOf(r4os.abi.ProgramIrqTimingInfo) and
                info.irq == irq and
                (info.coverage_flags & required_coverage) == required_coverage and
                info.delivery_samples == 0 and
                info.dispatch_max_ns >= info.dispatch_last_ns and
                info.dispatch_total_ns >= info.dispatch_last_ns and
                info.handler_max_ns >= info.handler_last_ns and
                info.handler_total_ns >= info.handler_last_ns;
            if (info.registered != 0) {
                registered += 1;
                if (info.dispatch_samples > 0) measured += 1;
                const minimum_reads = 2 *% (info.dispatch_samples +% info.handler_samples);
                ok = ok and info.observer_reads >= minimum_reads;
            }
            const high_resolution = (info.clock_flags & r4os.abi.monotonic_clock_flag_high_resolution) != 0;
            if (high_resolution) {
                ok = ok and (info.coverage_flags & r4os.abi.performance_irq_coverage_irq_safe_clock) != 0;
            }
        }
        ok = ok and checked == 32 and registered > 0 and measured > 0;
        self.printCheck("IRQ high-resolution timing coverage", ok);
        if (!ok) {
            self.sys.write("  IRQ timing checked/registered/measured=");
            self.sys.printU64(checked);
            self.sys.write("/");
            self.sys.printU64(registered);
            self.sys.write("/");
            self.sys.printU64(measured);
            self.sys.println("");
        }
        return ok;
    }

    fn printBaseline(self: *App, summary: r4os.abi.ProgramPerformanceSummary) void {
        self.sys.write("  Clock: source=");
        self.sys.write(clockSourceName(summary.monotonic_clock_source));
        self.sys.write(" generation=");
        self.sys.printU64(summary.monotonic_clock_generation);
        self.sys.write(" resolutionNs=");
        self.sys.printU64(summary.monotonic_clock_resolution_ns);
        self.sys.write(" event=");
        self.sys.write(timeBackendName(summary.monotonic_event_backend));
        self.sys.write(" rate=");
        self.sys.printU64(summary.monotonic_event_frequency_numerator);
        self.sys.write("/");
        self.sys.printU64(summary.monotonic_event_frequency_denominator);
        self.sys.println("");

        self.sys.write("  Boot/loader ns: boot=");
        self.sys.printU64(summary.boot_total_ns);
        self.sys.write(" valid/unavailable/dropped=");
        self.sys.printU64(summary.boot_timing_valid);
        self.sys.write("/");
        self.sys.printU64(summary.boot_timing_unavailable_spans);
        self.sys.write("/");
        self.sys.printU64(summary.boot_timing_dropped_spans);
        self.sys.write(" loader=");
        self.sys.printU64(summary.loader_total_ns);
        self.sys.write(" spans=");
        self.sys.printU64(summary.loader_timing_valid_spans);
        self.sys.write("/");
        self.sys.printU64(summary.loader_timing_unavailable_spans);
        self.sys.println("");

        self.sys.write("  Scheduler: ticks=");
        self.sys.printU64(summary.ticks);
        self.sys.write(" hz=");
        self.sys.printU64(summary.tick_hz);
        self.sys.write(" yields=");
        self.sys.printU64(summary.scheduler_yields);
        self.sys.write(" sleeps=");
        self.sys.printU64(summary.scheduler_sleeps);
        self.sys.write(" wakes=");
        self.sys.printU64(summary.scheduler_wakes);
        self.sys.write(" idle=");
        self.sys.printU64(summary.scheduler_idle_waits);
        self.sys.println("");

        self.sys.write("  Scheduler latency: readySamples=");
        self.sys.printU64(summary.scheduler_ready_latency_samples);
        self.sys.write(" readyMax=");
        self.sys.printU64(summary.scheduler_ready_latency_max_ticks);
        self.sys.write(" readyWaitMax=");
        self.sys.printU64(summary.scheduler_ready_waiting_max_ticks);
        self.sys.write(" runMax=");
        self.sys.printU64(summary.scheduler_run_without_switch_max_ticks);
        self.sys.write(" overrun=");
        self.sys.printU64(summary.scheduler_quantum_overrun_count);
        self.sys.write("/");
        self.sys.printU64(summary.scheduler_quantum_overrun_max_ticks);
        self.sys.write(" deferMax=");
        self.sys.printU64(summary.scheduler_preemption_deferred_max_ticks);
        self.sys.write(" waitObj=");
        self.sys.printU64(summary.wait_object_total_ticks);
        self.sys.write("/");
        self.sys.printU64(summary.wait_object_max_ticks);
        self.sys.write(" waitQ=");
        self.sys.printU64(summary.wait_queue_total_ticks);
        self.sys.write("/");
        self.sys.printU64(summary.wait_queue_max_ticks);
        self.sys.write(" warnAt=");
        self.sys.printU64(summary.scheduler_long_running_warn_ticks);
        self.sys.write("/");
        self.sys.printU64(summary.scheduler_starvation_warn_ticks);
        self.sys.println("");

        self.sys.write("  Driver workqueue: cap=");
        self.sys.printU64(summary.driver_work_capacity);
        self.sys.write(" depth=");
        self.sys.printU64(summary.driver_work_depth);
        self.sys.write(" high=");
        self.sys.printU64(summary.driver_work_high_water);
        self.sys.write(" irq=");
        self.sys.printU64(summary.driver_work_submitted_from_irq);
        self.sys.write(" task=");
        self.sys.printU64(summary.driver_work_submitted_from_task);
        self.sys.write(" done=");
        self.sys.printU64(summary.driver_work_completed);
        self.sys.write(" waits=");
        self.sys.printU64(summary.driver_work_waits);
        self.sys.write(" timeouts=");
        self.sys.printU64(summary.driver_work_wait_timeouts);
        self.sys.write(" qmax=");
        self.sys.printU64(summary.driver_work_queue_max_ticks);
        self.sys.write(" runmax=");
        self.sys.printU64(summary.driver_work_run_max_ticks);
        self.sys.write(" waitmax=");
        self.sys.printU64(summary.driver_work_wait_max_ticks);
        self.sys.println("");

        if (self.dev.performanceDriverWork(0)) |driver_work| {
            self.sys.write("  Audio deadline work: queued/running/high=");
            self.sys.printU64(driver_work.deadline_queued_slots);
            self.sys.write("/");
            self.sys.printU64(driver_work.deadline_running_slots);
            self.sys.write("/");
            self.sys.printU64(driver_work.deadline_queue_high_water);
            self.sys.write(" submitted/done=");
            self.sys.printU64(driver_work.deadline_submitted);
            self.sys.write("/");
            self.sys.printU64(driver_work.deadline_completed);
            self.sys.write(" miss/overrun/reject=");
            self.sys.printU64(driver_work.deadline_misses);
            self.sys.write("/");
            self.sys.printU64(driver_work.deadline_budget_overruns);
            self.sys.write("/");
            self.sys.printU64(driver_work.deadline_queue_rejections);
            self.sys.println("");
        }

        self.sys.write("  Storage worker: started=");
        self.sys.printU64(summary.storage_worker_started);
        self.sys.write(" task=");
        self.sys.printU64(summary.storage_worker_task_id);
        self.sys.write(" wake=");
        self.sys.printU64(summary.storage_worker_wakeups);
        self.sys.write(" runs=");
        self.sys.printU64(summary.storage_worker_runs);
        self.sys.write(" req=");
        self.sys.printU64(summary.storage_worker_runtime_requests);
        self.sys.write(" done=");
        self.sys.printU64(summary.storage_worker_runtime_completions);
        self.sys.write(" signals=");
        self.sys.printU64(summary.storage_completion_signals);
        self.sys.write(" bootInline=");
        self.sys.printU64(summary.storage_boot_inline_requests);
        self.sys.println("");

        self.sys.write("  Preemption: supported=");
        self.sys.printU64(summary.preemption_supported);
        self.sys.write(" enabled=");
        self.sys.printU64(summary.preemption_enabled);
        self.sys.write(" test=");
        self.sys.printU64(summary.preemption_test_mode);
        self.sys.write(" gates=");
        self.sys.printU64(summary.preemption_gate_mask);
        self.sys.write(" sim=");
        self.sys.printU64(summary.preemption_simulation_ticks);
        self.sys.write(" eligible=");
        self.sys.printU64(summary.preemption_eligible_ticks);
        self.sys.write(" quantum=");
        self.sys.printU64(summary.preemption_quantum_ticks);
        self.sys.write(" disabled=");
        self.sys.printU64(summary.preemption_deferred_disabled);
        self.sys.write(" critical=");
        self.sys.printU64(summary.preemption_deferred_critical);
        self.sys.write(" noReady=");
        self.sys.printU64(summary.preemption_deferred_no_ready);
        self.sys.write(" qdef=");
        self.sys.printU64(summary.preemption_deferred_quantum);
        self.sys.write(" kernelIp=");
        self.sys.printU64(summary.preemption_deferred_kernel_ip);
        self.sys.write(" qexp=");
        self.sys.printU64(summary.preemption_quantum_expired);
        self.sys.write(" app=");
        self.sys.printU64(summary.preemption_app_code_ticks);
        self.sys.write(" switches=");
        self.sys.printU64(summary.preemption_switch_ticks);
        self.sys.write(" depth=");
        self.sys.printU64(summary.preempt_disable_depth);
        self.sys.write("/");
        self.sys.printU64(summary.preempt_disable_max_depth);
        self.sys.write(" warn=");
        self.sys.printU64(summary.long_running_task_warnings);
        self.sys.write("/");
        self.sys.printU64(summary.starvation_warnings);
        self.sys.println("");

        self.sys.write("  FPU/SSE: supported=");
        self.sys.printU64(summary.fpu_state_supported);
        self.sys.write(" enabled=");
        self.sys.printU64(summary.fpu_state_enabled);
        self.sys.write(" backend=");
        self.sys.printU64(summary.fpu_state_backend);
        self.sys.write(" bytes=");
        self.sys.printU64(summary.fpu_state_bytes);
        self.sys.write("/");
        self.sys.printU64(summary.fpu_state_storage_bytes);
        self.sys.write(" tasks=");
        self.sys.printU64(summary.fpu_task_state_count);
        self.sys.write(" abi=");
        self.sys.printU64(summary.fpu_simd_abi);
        self.sys.write(" avx=");
        self.sys.printU64(summary.fpu_avx_supported);
        self.sys.write("/");
        self.sys.printU64(summary.fpu_avx_enabled);
        self.sys.write(" avx2=");
        self.sys.printU64(summary.fpu_avx2_supported);
        self.sys.write("/");
        self.sys.printU64(summary.fpu_avx2_enabled);
        self.sys.write(" save=");
        self.sys.printU64(summary.fpu_save_count);
        self.sys.write(" restore=");
        self.sys.printU64(summary.fpu_restore_count);
        self.sys.write(" req=");
        self.sys.printU64(summary.fpu_xsave_required_bytes);
        self.sys.write(" xcr0=");
        self.sys.printU64(summary.fpu_xcr0_mask);
        self.sys.println("");

        self.sys.write("  Tasks: total=");
        self.sys.printU64(summary.task_count);
        self.sys.write(" ready=");
        self.sys.printU64(summary.task_ready);
        self.sys.write(" running=");
        self.sys.printU64(summary.task_running);
        self.sys.write(" blocked=");
        self.sys.printU64(summary.task_blocked);
        self.sys.write(" dead=");
        self.sys.printU64(summary.task_dead);
        self.sys.write(" workers=");
        self.sys.printU64(summary.task_workers);
        self.sys.println("");

        self.sys.write("  Storage: devices=");
        self.sys.printU64(summary.storage_device_count);
        self.sys.write(" read=");
        self.sys.printU64(summary.storage_read_ops);
        self.sys.write(" write=");
        self.sys.printU64(summary.storage_write_ops);
        self.sys.write(" flush=");
        self.sys.printU64(summary.storage_flush_ops);
        self.sys.write(" busy=");
        self.sys.printU64(summary.storage_busy_rejections);
        self.sys.write(" timeouts=");
        self.sys.printU64(summary.storage_timeout_failures);
        self.sys.write(" qUsed=");
        self.sys.printU64(summary.storage_queue_used_total);
        self.sys.write(" qHigh=");
        self.sys.printU64(summary.storage_queue_high_water_total);
        self.sys.write(" queued=");
        self.sys.printU64(summary.storage_queued_requests);
        self.sys.write(" done=");
        self.sys.printU64(summary.storage_dequeued_requests);
        self.sys.write(" cwait=");
        self.sys.printU64(summary.storage_completion_waits);
        self.sys.write(" ctimeout=");
        self.sys.printU64(summary.storage_completion_timeouts);
        self.sys.write(" cmax=");
        self.sys.printU64(summary.storage_completion_max_ticks);
        self.sys.println("");

        self.sys.write("  Loader: total=");
        self.sys.printU64(summary.loader_total_ticks);
        self.sys.write(" r4pRuntime=");
        self.sys.printU64(summary.loader_r4p_runtime_total_ticks);
        self.sys.write(" service=");
        self.sys.printU64(summary.loader_service_boot_ticks);
        self.sys.write(" cfg=");
        self.sys.printU64(summary.loader_config_bytes);
        self.sys.write(" r4l=");
        self.sys.printU64(summary.loader_r4l_loaded);
        self.sys.write("/");
        self.sys.printU64(summary.loader_r4l_candidates);
        self.sys.write(" r4d=");
        self.sys.printU64(summary.loader_r4d_discovered);
        self.sys.write("/");
        self.sys.printU64(summary.loader_r4d_candidates);
        self.sys.write(" r4p=");
        self.sys.printU64(summary.loader_r4p_active);
        self.sys.write("/");
        self.sys.printU64(summary.loader_r4p_candidates);
        self.sys.write(" lazy=");
        self.sys.printU64(summary.loader_lazy_candidate_count);
        self.sys.println("");

        self.sys.write("  LoaderMemory: active=");
        self.sys.printU64(summary.loader_file_active_buffers);
        self.sys.write(" reserved=");
        self.sys.printU64(summary.loader_file_reserved_bytes);
        self.sys.write(" committed=");
        self.sys.printU64(summary.loader_file_committed_bytes);
        self.sys.write(" peak=");
        self.sys.printU64(summary.loader_file_peak_reserved_bytes);
        self.sys.write("/");
        self.sys.printU64(summary.loader_file_peak_committed_bytes);
        self.sys.write(" reads=");
        self.sys.printU64(summary.loader_file_full_reads);
        self.sys.write("/");
        self.sys.printU64(summary.loader_file_range_reads);
        self.sys.write(" bytes=");
        self.sys.printU64(summary.loader_file_range_read_bytes);
        self.sys.write(" metadata=");
        self.sys.printU64(summary.loader_metadata_logical_reads);
        self.sys.write("/");
        self.sys.printU64(summary.loader_metadata_window_hits);
        self.sys.write("/");
        self.sys.printU64(summary.loader_metadata_window_fills);
        self.sys.write(" capacity=");
        self.sys.printU64(summary.loader_metadata_window_capacity_bytes);
        self.sys.write(" pressure=");
        self.sys.printU64(summary.loader_file_pressure_reclaim_attempts);
        self.sys.write("/");
        self.sys.printU64(summary.loader_file_pressure_reclaimed_frames);
        self.sys.write(" failures=");
        self.sys.printU64(summary.loader_file_reserve_failures +% summary.loader_file_commit_failures +% summary.loader_file_read_failures +% summary.loader_file_short_reads +% summary.loader_file_release_failures +% summary.loader_file_pressure_failures);
        self.sys.println("");

        self.sys.write("  HotPath: vmIndex=");
        self.sys.printU64(summary.hot_path_vm_range_index_entries);
        self.sys.write("/");
        self.sys.printU64(summary.hot_path_vm_range_index_capacity);
        self.sys.write(" lookups=");
        self.sys.printU64(summary.hot_path_vm_range_index_lookups);
        self.sys.write(" hits=");
        self.sys.printU64(summary.hot_path_vm_range_index_hits);
        self.sys.write(" misses=");
        self.sys.printU64(summary.hot_path_vm_range_index_misses);
        self.sys.write(" probeMax=");
        self.sys.printU64(summary.hot_path_vm_range_index_probe_max);
        self.sys.write(" freeSlot=");
        self.sys.printU64(summary.hot_path_vm_range_free_slot_lookups);
        self.sys.write("/");
        self.sys.printU64(summary.hot_path_vm_range_free_slot_probe_max);
        self.sys.write(" bounds=");
        self.sys.printU64(summary.hot_path_bounded_block_device_scan_max);
        self.sys.write("/");
        self.sys.printU64(summary.hot_path_bounded_tcp_connection_scan_max);
        self.sys.println("");

        self.sys.write("  FS requests: total=");
        self.sys.printU64(summary.fs_requests);
        self.sys.write(" read=");
        self.sys.printU64(summary.fs_read_requests);
        self.sys.write(" write=");
        self.sys.printU64(summary.fs_write_requests);
        self.sys.write(" meta=");
        self.sys.printU64(summary.fs_metadata_requests);
        self.sys.write(" stream=");
        self.sys.printU64(summary.fs_stream_requests);
        self.sys.write(" lock=");
        self.sys.printU64(summary.fs_lock_acquires);
        self.sys.write(" contended=");
        self.sys.printU64(summary.fs_lock_contention_waits);
        self.sys.write(" timeout=");
        self.sys.printU64(summary.fs_lock_timeouts);
        self.sys.write(" max=");
        self.sys.printU64(summary.fs_max_ticks);
        self.sys.println("");

        self.sys.write("  FS cache: entries=");
        self.sys.printU64(summary.fs_cache_entries_used);
        self.sys.write("/");
        self.sys.printU64(summary.fs_cache_capacity);
        self.sys.write(" sector=");
        self.sys.printU64(summary.fs_cache_sector_bytes);
        self.sys.write(" reads=");
        self.sys.printU64(summary.fs_cache_reads);
        self.sys.write(" hits=");
        self.sys.printU64(summary.fs_cache_hits);
        self.sys.write(" misses=");
        self.sys.printU64(summary.fs_cache_misses);
        self.sys.write(" fills=");
        self.sys.printU64(summary.fs_cache_fills);
        self.sys.write(" evict=");
        self.sys.printU64(summary.fs_cache_evictions);
        self.sys.write(" writeThrough=");
        self.sys.printU64(summary.fs_cache_write_through_requests);
        self.sys.write("/");
        self.sys.printU64(summary.fs_cache_write_through_updates);
        self.sys.write(" deferred=");
        self.sys.printU64(summary.fs_cache_deferred_write_requests);
        self.sys.write(" updates=");
        self.sys.printU64(summary.fs_cache_dirty_sector_updates);
        self.sys.write(" dirty=");
        self.sys.printU64(summary.fs_cache_dirty_entries);
        self.sys.write(" dirtyBytes=");
        self.sys.printU64(summary.fs_cache_dirty_bytes);
        self.sys.write(" q=");
        self.sys.printU64(summary.fs_cache_writeback_queue_depth);
        self.sys.write("/");
        self.sys.printU64(summary.fs_cache_writeback_queue_high_water);
        self.sys.write(" wbWait=");
        self.sys.printU64(summary.fs_cache_writeback_waits);
        self.sys.write(" wbDrain=");
        self.sys.printU64(summary.fs_cache_writeback_drains);
        self.sys.write(" wbSectors=");
        self.sys.printU64(summary.fs_cache_writeback_sectors);
        self.sys.write(" wbFlush=");
        self.sys.printU64(summary.fs_cache_writeback_flush_drains);
        self.sys.write(" wbPressure=");
        self.sys.printU64(summary.fs_cache_writeback_pressure_drains);
        self.sys.write(" wbTicks=");
        self.sys.printU64(summary.fs_cache_writeback_last_ticks);
        self.sys.write("/");
        self.sys.printU64(summary.fs_cache_writeback_max_ticks);
        self.sys.write(" wbErr=");
        self.sys.printU64(summary.fs_cache_writeback_errors);
        self.sys.write(" bulk=");
        self.sys.printU64(summary.fs_cache_bulk_write_requests);
        self.sys.write("/");
        self.sys.printU64(summary.fs_cache_bulk_write_sectors);
        self.sys.write(" selective=");
        self.sys.printU64(summary.fs_cache_selective_flushes);
        self.sys.write("/");
        self.sys.printU64(summary.fs_cache_selective_writeback_sectors);
        self.sys.write(" foreignSkip=");
        self.sys.printU64(summary.fs_cache_selective_foreign_dirty_sectors_skipped);
        self.sys.write(" policy=");
        self.sys.printU64(summary.fs_cache_policy_version);
        self.sys.write(" water=");
        self.sys.printU64(summary.fs_cache_policy_dirty_low_pages);
        self.sys.write("/");
        self.sys.printU64(summary.fs_cache_policy_dirty_high_pages);
        self.sys.write(" bg=");
        self.sys.printU64(summary.fs_cache_policy_background_drains);
        self.sys.write("/");
        self.sys.printU64(summary.fs_cache_policy_background_sectors);
        self.sys.write(" ra=");
        self.sys.printU64(summary.fs_cache_read_ahead_issued);
        self.sys.write("/");
        self.sys.printU64(summary.fs_cache_read_ahead_hits);
        self.sys.write(" raWindow=");
        self.sys.printU64(summary.fs_cache_read_ahead_window_pages);
        self.sys.write("/");
        self.sys.printU64(summary.fs_cache_read_ahead_window_max_pages);
        self.sys.write(" cap=");
        self.sys.printU64(summary.fs_cache_capacity_min_pages);
        self.sys.write("/");
        self.sys.printU64(summary.fs_cache_capacity_active_limit_pages);
        self.sys.write("/");
        self.sys.printU64(summary.fs_cache_capacity_ram_limit_pages);
        self.sys.write("/");
        self.sys.printU64(summary.fs_cache_capacity_max_pages);
        self.sys.write(" pressure=");
        self.sys.printU64(summary.fs_cache_capacity_pressure_level);
        self.sys.write(" fill=");
        self.sys.printU64(summary.fs_cache_fill_run_requests);
        self.sys.write("/");
        self.sys.printU64(summary.fs_cache_fill_run_backend_requests);
        self.sys.write("/");
        self.sys.printU64(summary.fs_cache_fill_run_pages);
        self.sys.write(" sectors=");
        self.sys.printU64(summary.fs_cache_fill_run_sectors);
        self.sys.write(" bytes=");
        self.sys.printU64(summary.fs_cache_fill_run_bytes);
        self.sys.write(" fillErr=");
        self.sys.printU64(summary.fs_cache_fill_run_failures);
        self.sys.write(" retry=");
        self.sys.printU64(summary.fs_cache_fill_run_retries);
        self.sys.write(" maxRun=");
        self.sys.printU64(summary.fs_cache_fill_run_max_pages);
        self.sys.write(" copy=");
        self.sys.printU64(summary.fs_cache_fill_scatter_copy_bytes);
        self.sys.write("/");
        self.sys.printU64(summary.fs_cache_read_staging_copy_bytes);
        self.sys.write("/");
        self.sys.printU64(summary.fs_cache_read_caller_copy_bytes);
        self.sys.write(" locks=");
        self.sys.printU64(summary.fs_cache_fill_lock_drops);
        self.sys.write("/");
        self.sys.printU64(summary.fs_cache_read_publish_lock_drops);
        self.sys.write(" trim=");
        self.sys.printU64(summary.fs_cache_capacity_reductions);
        self.sys.write("/");
        self.sys.printU64(summary.fs_cache_capacity_trimmed_pages);
        self.sys.write(" raPages=");
        self.sys.printU64(summary.fs_cache_read_ahead_pages_scheduled);
        self.sys.write("/");
        self.sys.printU64(summary.fs_cache_read_ahead_pages_issued);
        self.sys.write(" randomReset=");
        self.sys.printU64(summary.fs_cache_read_ahead_random_resets);
        self.sys.write(" reclaimClean=");
        self.sys.printU64(summary.fs_cache_clean_reclaimable_bytes);
        self.sys.write(" reclaimDirty=");
        self.sys.printU64(summary.fs_cache_dirty_non_reclaimable_bytes);
        self.sys.write(" pmmReclaim=");
        self.sys.printU64(summary.fs_cache_pmm_reclaimable_bytes);
        self.sys.write(" payloadFrames=");
        self.sys.printU64(summary.fs_cache_payload_frames);
        self.sys.write(" payloadAlloc=");
        self.sys.printU64(summary.fs_cache_payload_allocations);
        self.sys.write("/");
        self.sys.printU64(summary.fs_cache_payload_releases);
        self.sys.write(" reclaimScan=");
        self.sys.printU64(summary.fs_cache_reclaim_scans);
        self.sys.write(" reclaimDrop=");
        self.sys.printU64(summary.fs_cache_reclaim_clean_entries);
        self.sys.write(" reclaimDirtyDrain=");
        self.sys.printU64(summary.fs_cache_reclaim_dirty_drains);
        self.sys.write(" pagefileReady=");
        self.sys.printU64(summary.fs_cache_pagefile_ready);
        self.sys.write(" pagefileBlockers=");
        self.sys.printU64(summary.fs_cache_pagefile_blockers);
        self.sys.println("");

        self.sys.write("  NTFS metadata cache: v=");
        self.sys.printU64(summary.ntfs_metadata_cache_version);
        self.sys.write(" volumes=");
        self.sys.printU64(summary.ntfs_metadata_cache_active_volumes);
        self.sys.write(" bytes/volume=");
        self.sys.printU64(summary.ntfs_metadata_cache_bytes_per_volume);
        self.sys.write(" entries(record/attr/index/path)=");
        self.sys.printU64(summary.ntfs_metadata_record_entries);
        self.sys.write("/");
        self.sys.printU64(summary.ntfs_metadata_attribute_entries);
        self.sys.write("/");
        self.sys.printU64(summary.ntfs_metadata_index_entries);
        self.sys.write("/");
        self.sys.printU64(summary.ntfs_metadata_path_entries);
        self.sys.write(" hits(record/attr/index/path+/path-)=");
        self.sys.printU64(summary.ntfs_metadata_record_hits);
        self.sys.write("/");
        self.sys.printU64(summary.ntfs_metadata_attribute_hits);
        self.sys.write("/");
        self.sys.printU64(summary.ntfs_metadata_index_hits);
        self.sys.write("/");
        self.sys.printU64(summary.ntfs_metadata_path_positive_hits);
        self.sys.write("/");
        self.sys.printU64(summary.ntfs_metadata_path_negative_hits);
        self.sys.write(" walks=");
        self.sys.printU64(summary.ntfs_metadata_lookup_tree_walks);
        self.sys.write(" invalidations=");
        self.sys.printU64(summary.ntfs_metadata_mount_invalidations);
        self.sys.write("/");
        self.sys.printU64(summary.ntfs_metadata_mutation_invalidations);
        self.sys.write("/");
        self.sys.printU64(summary.ntfs_metadata_external_invalidations);
        self.sys.write(" retained(payload/system)=");
        self.sys.printU64(summary.ntfs_metadata_payload_write_retentions);
        self.sys.write("/");
        self.sys.printU64(summary.ntfs_metadata_system_write_retentions);
        self.sys.write(" targeted(record/attr/dir)=");
        self.sys.printU64(summary.ntfs_metadata_targeted_record_invalidations);
        self.sys.write("/");
        self.sys.printU64(summary.ntfs_metadata_targeted_attribute_invalidations);
        self.sys.write("/");
        self.sys.printU64(summary.ntfs_metadata_targeted_directory_invalidations);
        self.sys.write(" global/recovery=");
        self.sys.printU64(summary.ntfs_metadata_global_mutation_invalidations);
        self.sys.write("/");
        self.sys.printU64(summary.ntfs_metadata_recovery_invalidations);
        self.sys.write(" reclaim=");
        self.sys.printU64(summary.ntfs_metadata_reclaim_scans);
        self.sys.write("/");
        self.sys.printU64(summary.ntfs_metadata_reclaimed_entries);
        self.sys.write(" generation=");
        self.sys.printU64(summary.ntfs_metadata_mount_generation);
        self.sys.write("/");
        self.sys.printU64(summary.ntfs_metadata_content_generation);
        self.sys.println("");

        self.sys.write("  Global reclaim: attempts=");
        self.sys.printU64(summary.global_reclaim_attempts);
        self.sys.write(" success=");
        self.sys.printU64(summary.global_reclaim_successes);
        self.sys.write(" fail=");
        self.sys.printU64(summary.global_reclaim_failures);
        self.sys.write(" frames=");
        self.sys.printU64(summary.global_reclaim_returned_frames);
        self.sys.write(" bytes=");
        self.sys.printU64(summary.global_reclaim_returned_bytes);
        self.sys.write(" last=");
        self.sys.printU64(summary.global_reclaim_last_reason);
        self.sys.write("/");
        self.sys.printU64(summary.global_reclaim_last_requested_frames);
        self.sys.write("/");
        self.sys.printU64(summary.global_reclaim_last_returned_frames);
        self.sys.write(" ticks=");
        self.sys.printU64(summary.global_reclaim_last_ticks);
        self.sys.write("/");
        self.sys.printU64(summary.global_reclaim_max_ticks);
        self.sys.println("");

        self.sys.write("  Backing store: status=");
        self.sys.printU64(summary.memory_backing_store_status);
        self.sys.write(" bytes=");
        self.sys.printU64(summary.memory_backing_store_available_bytes);
        self.sys.write("/");
        self.sys.printU64(summary.memory_backing_store_requested_bytes);
        self.sys.write(" file=");
        self.sys.printU64(summary.memory_backing_store_file_size);
        self.sys.write(" cluster=");
        self.sys.printU64(summary.memory_backing_store_cluster_bytes);
        self.sys.write(" first=");
        self.sys.printU64(summary.memory_backing_store_first_cluster);
        self.sys.write(" probes=");
        self.sys.printU64(summary.memory_backing_store_probe_count);
        self.sys.write(" ready=");
        self.sys.printU64(summary.memory_backing_store_ready_count);
        self.sys.write(" fail=");
        self.sys.printU64(summary.memory_backing_store_failure_count);
        self.sys.write(" pager=");
        self.sys.printU64(summary.memory_backing_store_pager_enabled);
        self.sys.write("/");
        self.sys.printU64(summary.memory_backing_store_anonymous_paging_enabled);
        self.sys.println("");

        self.sys.write("  Backing slots: status=");
        self.sys.printU64(summary.memory_backing_store_slot_status);
        self.sys.write(" op=");
        self.sys.printU64(summary.memory_backing_store_slot_operation);
        self.sys.write(" cap=");
        self.sys.printU64(summary.memory_backing_store_slot_capacity);
        self.sys.write(" free=");
        self.sys.printU64(summary.memory_backing_store_slot_free);
        self.sys.write(" reserved=");
        self.sys.printU64(summary.memory_backing_store_slot_reserved);
        self.sys.write(" errors=");
        self.sys.printU64(summary.memory_backing_store_slot_error);
        self.sys.write(" ranges=");
        self.sys.printU64(summary.memory_backing_store_slot_range_count);
        self.sys.write("/");
        self.sys.printU64(summary.memory_backing_store_slot_max_ranges);
        self.sys.write(" owner=");
        self.sys.printU64(summary.memory_backing_store_slot_last_owner_kind);
        self.sys.write("/");
        self.sys.printU64(summary.memory_backing_store_slot_last_region_id);
        self.sys.write(" ops=");
        self.sys.printU64(summary.memory_backing_store_slot_probe_count);
        self.sys.write("/");
        self.sys.printU64(summary.memory_backing_store_slot_reserve_count);
        self.sys.write("/");
        self.sys.printU64(summary.memory_backing_store_slot_release_count);
        self.sys.write("/");
        self.sys.printU64(summary.memory_backing_store_slot_error_mark_count);
        self.sys.write("/");
        self.sys.printU64(summary.memory_backing_store_slot_recovery_count);
        self.sys.write(" pager=");
        self.sys.printU64(summary.memory_backing_store_slot_pager_enabled);
        self.sys.write("/");
        self.sys.printU64(summary.memory_backing_store_slot_eviction_enabled);
        self.sys.write(" lifecycle=");
        self.sys.printU64(summary.memory_backing_store_slot_lifecycle_cleanup_count);
        self.sys.write("/");
        self.sys.printU64(summary.memory_backing_store_slot_lifecycle_released_ranges);
        self.sys.write("/");
        self.sys.printU64(summary.memory_backing_store_slot_lifecycle_released_slots);
        self.sys.println("");

        self.sys.write("  Pager gates: status=");
        self.sys.printU64(summary.memory_pager_gate_status);
        self.sys.write(" region=");
        self.sys.printU64(summary.memory_pager_gate_region_id);
        self.sys.write(" commit=");
        self.sys.printU64(summary.memory_pager_gate_committed_bytes);
        self.sys.write(" resident=");
        self.sys.printU64(summary.memory_pager_gate_resident_bytes);
        self.sys.write(" slots=");
        self.sys.printU64(summary.memory_pager_gate_prepared_slots);
        self.sys.write("/");
        self.sys.printU64(summary.memory_pager_gate_capacity_slots);
        self.sys.write(" rollback=");
        self.sys.printU64(summary.memory_pager_gate_rollback_completed);
        self.sys.write(" probes=");
        self.sys.printU64(summary.memory_pager_gate_probe_count);
        self.sys.write("/");
        self.sys.printU64(summary.memory_pager_gate_failure_count);
        self.sys.write(" pageIO=");
        self.sys.printU64(summary.memory_pager_gate_page_in_enabled);
        self.sys.write("/");
        self.sys.printU64(summary.memory_pager_gate_page_out_enabled);
        self.sys.println("");

        self.sys.write("  Services: used=");
        self.sys.printU64(summary.services_used);
        self.sys.write(" running=");
        self.sys.printU64(summary.services_running);
        self.sys.write(" endpoints=");
        self.sys.printU64(summary.service_endpoints);
        self.sys.write(" qDepth=");
        self.sys.printU64(summary.service_queue_depth_total);
        self.sys.write(" qUsed=");
        self.sys.printU64(summary.service_queue_used_total);
        self.sys.write(" qHigh=");
        self.sys.printU64(summary.service_queue_high_water_total);
        self.sys.write(" workers=");
        self.sys.printU64(summary.service_active_workers);
        self.sys.write("/");
        self.sys.printU64(summary.service_max_active_workers);
        self.sys.write(" open=");
        self.sys.printU64(summary.service_open_handles);
        self.sys.write(" req=");
        self.sys.printU64(summary.service_requests);
        self.sys.write(" resp=");
        self.sys.printU64(summary.service_responses);
        self.sys.write(" drops=");
        self.sys.printU64(summary.service_drops);
        self.sys.write(" busy=");
        self.sys.printU64(summary.service_busy_rejections);
        self.sys.write(" timeout=");
        self.sys.printU64(summary.service_timeouts);
        self.sys.write(" cancel=");
        self.sys.printU64(summary.service_cancellations);
        self.sys.write(" cwait=");
        self.sys.printU64(summary.service_completion_waits);
        self.sys.write(" ctimeout=");
        self.sys.printU64(summary.service_completion_timeouts);
        self.sys.write(" cround=");
        self.sys.printU64(summary.service_completion_wait_rounds);
        self.sys.write(" rwake=");
        self.sys.printU64(summary.service_targeted_response_wakes);
        self.sys.write(" rmiss=");
        self.sys.printU64(summary.service_targeted_response_wake_misses);
        self.sys.write(" await=");
        self.sys.printU64(summary.service_admission_waits);
        self.sys.write(" atimeout=");
        self.sys.printU64(summary.service_admission_timeouts);
        self.sys.write(" copyB=");
        self.sys.printU64(summary.service_payload_copy_bytes);
        self.sys.write(" clearB=");
        self.sys.printU64(summary.service_payload_clear_bytes);
        self.sys.write(" sreset=");
        self.sys.printU64(summary.service_slot_metadata_resets);
        self.sys.write(" ereset=");
        self.sys.printU64(summary.service_endpoint_metadata_resets);
        self.sys.write(" erclearB=");
        self.sys.printU64(summary.service_endpoint_payload_reset_bytes);
        self.sys.println("");

        self.sys.write("  ServiceScan: passes=");
        self.sys.printU64(summary.service_queue_scan_passes);
        self.sys.write(" slots=");
        self.sys.printU64(summary.service_queue_scan_slots);
        self.sys.write(" revalidations=");
        self.sys.printU64(summary.service_endpoint_revalidations);
        self.sys.write(" stale=");
        self.sys.printU64(summary.service_endpoint_stale_rejections);
        self.sys.write(" families=");
        self.sys.printU64(summary.service_lock_family_count);
        self.sys.write(" stride=");
        self.sys.printU64(summary.service_lock_timing_stride);
        self.sys.println("");
        var service_lock_family: usize = 0;
        while (service_lock_family < summary.service_lock_acquisitions.len) : (service_lock_family += 1) {
            self.sys.write("  ServiceLock: family=");
            self.sys.printU64(@intCast(service_lock_family));
            self.sys.write(" acq=");
            self.sys.printU64(summary.service_lock_acquisitions[service_lock_family]);
            self.sys.write(" contention=");
            self.sys.printU64(summary.service_lock_contentions[service_lock_family]);
            self.sys.write(" samples=");
            self.sys.printU64(summary.service_lock_timing_samples[service_lock_family]);
            self.sys.write(" waitNs=");
            self.sys.printU64(summary.service_lock_wait_ns[service_lock_family]);
            self.sys.write(" waitMaxNs=");
            self.sys.printU64(summary.service_lock_wait_max_ns[service_lock_family]);
            self.sys.write(" holdNs=");
            self.sys.printU64(summary.service_lock_hold_ns[service_lock_family]);
            self.sys.write(" holdMaxNs=");
            self.sys.printU64(summary.service_lock_hold_max_ns[service_lock_family]);
            self.sys.write(" unavailable=");
            self.sys.printU64(summary.service_lock_timing_unavailable[service_lock_family]);
            self.sys.println("");
        }

        self.sys.write("  TCP: active=");
        self.sys.printU64(summary.tcp_active_connections);
        self.sys.write(" listeners=");
        self.sys.printU64(summary.tcp_active_listeners);
        self.sys.write(" tx=");
        self.sys.printU64(summary.tcp_data_tx);
        self.sys.write(" rx=");
        self.sys.printU64(summary.tcp_data_rx);
        self.sys.write(" retrans=");
        self.sys.printU64(summary.tcp_retransmits);
        self.sys.write(" drops=");
        self.sys.printU64(summary.tcp_rx_drops);
        self.sys.println("");

        self.sys.write("  Display: presents=");
        self.sys.printU64(summary.display_present_count);
        self.sys.write(" bytes=");
        self.sys.printU64(summary.display_present_bytes_total);
        self.sys.write(" last=");
        self.sys.printU64(summary.display_last_present_bytes);
        self.sys.write(" ticks=");
        self.sys.printU64(summary.display_present_last_ticks);
        self.sys.write("/");
        self.sys.printU64(summary.display_present_max_ticks);
        self.sys.write(" totalTicks=");
        self.sys.printU64(summary.display_present_total_ticks);
        self.sys.write(" slow=");
        self.sys.printU64(summary.display_present_slow_count);
        self.sys.println("");

        self.sys.write("  Audio: streams=");
        self.sys.printU64(summary.audio_open_streams);
        self.sys.write(" backends=");
        self.sys.printU64(summary.audio_registered_backends);
        self.sys.write(" ok=");
        self.sys.printU64(summary.audio_backend_ok);
        self.sys.write(" fail=");
        self.sys.printU64(summary.audio_backend_fail);
        self.sys.write(" underruns=");
        self.sys.printU64(summary.audio_backend_underruns);
        self.sys.write(" high=");
        self.sys.printU64(summary.audio_stream_high_water_bytes);
        self.sys.write(" drop=");
        self.sys.printU64(summary.audio_stream_dropped_bytes);
        self.sys.write(" writeTicks=");
        self.sys.printU64(summary.audio_stream_write_last_ticks);
        self.sys.write("/");
        self.sys.printU64(summary.audio_stream_write_max_ticks);
        self.sys.write(" backendTicks=");
        self.sys.printU64(summary.audio_backend_write_last_ticks);
        self.sys.write("/");
        self.sys.printU64(summary.audio_backend_write_max_ticks);
        self.sys.write(" refills=");
        self.sys.printU64(summary.audio_backend_refills);
        self.sys.write("/");
        self.sys.printU64(summary.audio_backend_silence_refills);
        self.sys.println("");

        self.sys.write("  Wait objects: waits=");
        self.sys.printU64(summary.wait_object_waits);
        self.sys.write(" wakes=");
        self.sys.printU64(summary.wait_object_wakes);
        self.sys.write(" timeouts=");
        self.sys.printU64(summary.wait_object_timeouts);
        self.sys.write(" cancels=");
        self.sys.printU64(summary.wait_object_cancellations);
        self.sys.println("");

        self.sys.write("  Wait queues: waits=");
        self.sys.printU64(summary.wait_queue_waits);
        self.sys.write(" one=");
        self.sys.printU64(summary.wait_queue_wake_one);
        self.sys.write(" all=");
        self.sys.printU64(summary.wait_queue_wake_all);
        self.sys.write(" timeouts=");
        self.sys.printU64(summary.wait_queue_timeouts);
        self.sys.write(" drops=");
        self.sys.printU64(summary.wait_queue_drops);
        self.sys.println("");

        self.sys.write("  Locks: acquire=");
        self.sys.printU64(summary.lock_acquires);
        self.sys.write(" release=");
        self.sys.printU64(summary.lock_releases);
        self.sys.write(" contended=");
        self.sys.printU64(summary.lock_contention_waits);
        self.sys.write(" orderBad=");
        self.sys.printU64(summary.lock_order_violations);
        self.sys.write(" sleepBad=");
        self.sys.printU64(summary.lock_sleep_under_no_sleep_lock);
        self.sys.write(" held=");
        self.sys.printU64(summary.lock_held_slots_used);
        self.sys.write(" maxDepth=");
        self.sys.printU64(summary.lock_max_depth);
        self.sys.println("");

        self.sys.write("  FPU lazy: saves=");
        self.sys.printU64(summary.fpu_lazy_saves);
        self.sys.write(" skips=");
        self.sys.printU64(summary.fpu_lazy_skips);
        self.sys.println("");

        self.printMissing(summary.missing_flags);
    }

    fn printTask(self: *App, info: r4os.abi.ProgramTaskPerformanceInfo) void {
        self.sys.write("  Task #");
        self.sys.printU64(info.id);
        self.sys.write(" ");
        self.sys.write(spanZ(info.name[0..]));
        self.sys.write(" state=");
        self.sys.printU64(info.state);
        self.sys.write(" run=");
        self.sys.printU64(info.run_ticks);
        self.sys.write(" yieldAgo=");
        self.sys.printU64(info.ticks_since_yield);
        self.sys.write(" scheduledAgo=");
        self.sys.printU64(info.ticks_since_scheduled);
        self.sys.write(" preempt=");
        self.sys.printU64(info.preempt_disable_depth);
        self.sys.write("/");
        self.sys.printU64(info.preempt_disable_max_depth);
        self.sys.write(" probe=");
        self.sys.printU64(info.preemption_probe_hits);
        self.sys.write("/");
        self.sys.printU64(info.preemption_deferred_ticks);
        self.sys.write(" warn=");
        self.sys.printU64(info.long_run_warnings);
        self.sys.write("/");
        self.sys.printU64(info.starvation_warnings);
        self.sys.write(" wait=");
        self.sys.write(spanZ(info.wait_reason[0..]));
        self.sys.write(" object=");
        self.sys.printU64(info.blocked_object);
        self.sys.write(" result=");
        self.sys.printU64(info.wait_result);
        self.sys.write(" readyLat=");
        self.sys.printU64(info.last_ready_latency_ticks);
        self.sys.write("/");
        self.sys.printU64(info.max_ready_latency_ticks);
        self.sys.write(" waitLat=");
        self.sys.printU64(info.last_wait_ticks);
        self.sys.write("/");
        self.sys.printU64(info.max_wait_ticks);
        self.sys.write(" runMax=");
        self.sys.printU64(info.max_run_without_switch_ticks);
        self.sys.write(" deferMax=");
        self.sys.printU64(info.max_preemption_deferred_ticks);
        self.sys.println("");
    }

    fn printStorage(self: *App, info: r4os.abi.ProgramStoragePerformanceInfo) void {
        self.sys.write("  Storage #");
        self.sys.printU64(info.index);
        self.sys.write(" ");
        self.sys.write(spanZ(info.name[0..]));
        self.sys.write(" q=");
        self.sys.printU64(info.queue_depth);
        self.sys.write(" used=");
        self.sys.printU64(info.queue_used);
        self.sys.write(" high=");
        self.sys.printU64(info.queue_high_water);
        self.sys.write(" queued=");
        self.sys.printU64(info.queued_requests);
        self.sys.write(" done=");
        self.sys.printU64(info.dequeued_requests);
        self.sys.write(" cwait=");
        self.sys.printU64(info.completion_waits);
        self.sys.write(" ctimeout=");
        self.sys.printU64(info.completion_timeouts);
        self.sys.write(" cmax=");
        self.sys.printU64(info.completion_max_ticks);
        self.sys.write(" sig=");
        self.sys.printU64(info.completion_signals);
        self.sys.write(" work=");
        self.sys.printU64(info.worker_requests);
        self.sys.write("/");
        self.sys.printU64(info.worker_completions);
        self.sys.write(" boot=");
        self.sys.printU64(info.boot_inline_requests);
        self.sys.write(" read=");
        self.sys.printU64(info.read_ops);
        self.sys.write(" write=");
        self.sys.printU64(info.write_ops);
        self.sys.write(" flush=");
        self.sys.printU64(info.flush_ops);
        self.sys.write(" err=");
        self.sys.printU64(info.last_error);
        self.sys.println("");
    }

    fn printBootPhase(self: *App, phase: r4os.abi.ProgramBootPhasePerformanceInfo) void {
        self.sys.write("  Boot ");
        self.sys.write(spanZ(phase.name[0..]));
        self.sys.write(" ticks=");
        self.sys.printU64(phase.total_ticks);
        self.sys.write(" transitions=");
        self.sys.printU64(phase.transitions);
        self.sys.println("");
    }

    fn printBootPhaseClock(self: *App, phase: r4os.abi.ProgramBootPhaseClockInfo) void {
        self.sys.write("    clockNs=");
        if ((phase.clock_flags & r4os.abi.monotonic_clock_flag_valid) != 0) {
            self.sys.printU64(phase.total_ns);
            self.sys.write(" first/last=");
            self.sys.printU64(phase.first_ns);
            self.sys.write("/");
            self.sys.printU64(phase.last_ns);
        } else {
            self.sys.write("unavailable spans=");
            self.sys.printU64(phase.unavailable_spans);
        }
        self.sys.println("");
    }

    fn printMissing(self: *App, flags: u32) void {
        self.sys.write("  Missing measurement classes:");
        if (flags == 0) {
            self.sys.println(" none");
            return;
        }
        self.printMissingFlag(flags, r4os.abi.performance_missing_blocked_object, " blocked-object");
        self.printMissingFlag(flags, r4os.abi.performance_missing_wait_latency_histogram, " wait-latency");
        self.printMissingFlag(flags, r4os.abi.performance_missing_fs_latency_histogram, " fs-latency");
        self.printMissingFlag(flags, r4os.abi.performance_missing_service_latency_histogram, " service-latency");
        self.printMissingFlag(flags, r4os.abi.performance_missing_tcp_latency_histogram, " tcp-latency");
        self.printMissingFlag(flags, r4os.abi.performance_missing_display_latency_histogram, " display-latency");
        self.printMissingFlag(flags, r4os.abi.performance_missing_preemption_latency_histogram, " preemption-latency");
        self.sys.println("");
    }

    fn printMissingFlag(self: *App, flags: u32, bit: u32, label: []const u8) void {
        if ((flags & bit) != 0) self.sys.write(label);
    }

    fn printCheck(self: *App, label: []const u8, ok: bool) void {
        self.recordCheck(label, ok);
        self.sys.write("  ");
        self.sys.write(label);
        self.sys.write(": ");
        self.sys.println(if (ok) "OK" else "FAILED");
    }

    fn probeFsPageCache(self: *App) bool {
        if (!self.dev.hasFn("performance_summary")) {
            self.printCheck("FS page cache read-through", false);
            return false;
        }
        const before = self.captureSummary() orelse {
            self.printCheck("FS page cache read-through", false);
            return false;
        };
        var first: [128]u8 = undefined;
        var second: [128]u8 = undefined;
        const a = self.sys.fileReadAt("C:\\R4OS\\CONFIG\\VERSION.R4S", 0, first[0..]);
        const b = self.sys.fileReadAt("C:\\R4OS\\CONFIG\\VERSION.R4S", 0, second[0..]);
        const after = self.captureSummary() orelse {
            self.printCheck("FS page cache read-through", false);
            return false;
        };
        const hit_delta = if (after.fs_cache_hits >= before.fs_cache_hits) after.fs_cache_hits - before.fs_cache_hits else 0;
        const read_delta = if (after.fs_cache_reads >= before.fs_cache_reads) after.fs_cache_reads - before.fs_cache_reads else 0;
        const len_ok = a > 0 and b == a;
        const bytes_ok = len_ok and bytesEq(first[0..@intCast(a)], second[0..@intCast(b)]);
        const ok = len_ok and
            bytes_ok and
            read_delta >= 2 and
            hit_delta >= 1 and
            after.fs_cache_capacity > 0 and
            after.fs_cache_sector_bytes == 512 and
            after.fs_cache_entries_used > 0 and
            after.fs_cache_dirty_entries == 0 and
            after.fs_cache_read_errors == 0 and
            after.fs_cache_write_errors == 0 and
            after.fs_cache_writeback_errors == 0;
        self.printCheck("FS page cache read-through", ok);
        if (!ok) {
            self.sys.write("  read=");
            self.sys.printI32(a);
            self.sys.write("/");
            self.sys.printI32(b);
            self.sys.write(" delta=");
            self.sys.printU64(read_delta);
            self.sys.write(" hitDelta=");
            self.sys.printU64(hit_delta);
            self.sys.write(" entries=");
            self.sys.printU64(after.fs_cache_entries_used);
            self.sys.write("/");
            self.sys.printU64(after.fs_cache_capacity);
            self.sys.write(" dirty=");
            self.sys.printU64(after.fs_cache_dirty_entries);
            self.sys.write(" err=");
            self.sys.printU64(after.fs_cache_read_errors +% after.fs_cache_write_errors +% after.fs_cache_writeback_errors);
            self.sys.println("");
        }
        return ok;
    }

    fn probeFsWriteback(self: *App) bool {
        if (!self.dev.hasFn("performance_summary")) {
            self.printCheck("FS page cache writeback", false);
            return false;
        }
        const before = self.captureSummary() orelse {
            self.printCheck("FS page cache writeback", false);
            return false;
        };
        const payload = "perfdiag-writeback-v119";
        const written = self.sys.fileWrite("C:\\TEMP\\PERFWB.TXT", payload);
        var verify: [64]u8 = undefined;
        const read = self.sys.fileReadAt("C:\\TEMP\\PERFWB.TXT", 0, verify[0..]);
        const after = self.captureSummary() orelse {
            self.printCheck("FS page cache writeback", false);
            return false;
        };
        const deferred_delta = delta(after.fs_cache_deferred_write_requests, before.fs_cache_deferred_write_requests);
        const writeback_delta = delta(after.fs_cache_writeback_sectors, before.fs_cache_writeback_sectors);
        const drain_delta = delta(after.fs_cache_writeback_drains, before.fs_cache_writeback_drains);
        const flush_delta = delta(after.fs_cache_writeback_flush_drains, before.fs_cache_writeback_flush_drains);
        const expected_len: i32 = @intCast(payload.len);
        const len_ok = written == expected_len and read == expected_len;
        const bytes_ok = len_ok and bytesEq(verify[0..payload.len], payload);
        const ok = len_ok and
            bytes_ok and
            deferred_delta > 0 and
            writeback_delta > 0 and
            drain_delta > 0 and
            flush_delta > 0 and
            after.fs_cache_dirty_entries == 0 and
            after.fs_cache_dirty_bytes == 0 and
            after.fs_cache_writeback_queue_depth == 0 and
            after.fs_cache_writeback_queue_high_water > 0 and
            after.fs_cache_writeback_errors == 0 and
            after.fs_cache_write_errors == 0;
        self.printCheck("FS page cache writeback", ok);
        if (!ok) {
            self.sys.write("  written=");
            self.sys.printI32(written);
            self.sys.write(" read=");
            self.sys.printI32(read);
            self.sys.write(" deferredDelta=");
            self.sys.printU64(deferred_delta);
            self.sys.write(" wbDelta=");
            self.sys.printU64(writeback_delta);
            self.sys.write(" drainDelta=");
            self.sys.printU64(drain_delta);
            self.sys.write(" flushDelta=");
            self.sys.printU64(flush_delta);
            self.sys.write(" dirty=");
            self.sys.printU64(after.fs_cache_dirty_entries);
            self.sys.write(" q=");
            self.sys.printU64(after.fs_cache_writeback_queue_depth);
            self.sys.write("/");
            self.sys.printU64(after.fs_cache_writeback_queue_high_water);
            self.sys.write(" err=");
            self.sys.printU64(after.fs_cache_write_errors +% after.fs_cache_writeback_errors);
            self.sys.println("");
        }
        return ok;
    }

    fn probeGlobalReclaim(self: *App) bool {
        if (!self.dev.hasFn("memory_reclaim_probe")) {
            self.printCheck("Global reclaim probe", false);
            return false;
        }
        const before = self.captureSummary() orelse {
            self.printCheck("Global reclaim probe", false);
            return false;
        };
        const probe = self.dev.memoryReclaimProbe(1) orelse {
            self.printCheck("Global reclaim probe", false);
            return false;
        };
        const after = self.captureSummary() orelse {
            self.printCheck("Global reclaim probe", false);
            return false;
        };
        const expected_bytes = @as(u64, probe.returned_frames) * @as(u64, before.fs_cache_payload_frame_bytes);
        const ok = probe.version == r4os.abi.memory_reclaim_probe_version and
            probe.size >= @sizeOf(r4os.abi.ProgramMemoryReclaimProbe) and
            probe.reason == r4os.abi.memory_reclaim_reason_diagnostic and
            probe.requested_frames == 1 and
            probe.returned_frames > 0 and
            probe.returned_bytes >= expected_bytes and
            probe.failed_drains == 0 and
            after.global_reclaim_attempts >= before.global_reclaim_attempts + 1 and
            after.global_reclaim_successes >= before.global_reclaim_successes + 1 and
            after.global_reclaim_returned_frames >= before.global_reclaim_returned_frames + probe.returned_frames and
            after.global_reclaim_last_reason == r4os.abi.memory_reclaim_reason_diagnostic and
            after.global_reclaim_last_requested_frames == 1 and
            after.global_reclaim_last_returned_frames == probe.returned_frames;
        self.printCheck("Global reclaim probe", ok);
        if (!ok) {
            self.sys.write("  returned=");
            self.sys.printU64(probe.returned_frames);
            self.sys.write("/");
            self.sys.printU64(probe.returned_bytes);
            self.sys.write(" attempts=");
            self.sys.printU64(before.global_reclaim_attempts);
            self.sys.write("->");
            self.sys.printU64(after.global_reclaim_attempts);
            self.sys.write(" pmm=");
            self.sys.printU64(before.fs_cache_pmm_reclaimable_bytes);
            self.sys.write("->");
            self.sys.printU64(after.fs_cache_pmm_reclaimable_bytes);
            self.sys.println("");
        }
        return ok;
    }

    fn probeBackingStore(self: *App) bool {
        if (!self.dev.hasFn("memory_backing_store_probe")) {
            self.printCheck("Backing store probe", false);
            return false;
        }

        const missing = self.dev.memoryBackingStoreProbe(missing_backing_store_path, backing_store_bytes, 0) orelse {
            self.printCheck("Backing store missing", false);
            return false;
        };
        const missing_ok = missing.version == r4os.abi.memory_backing_store_probe_version and
            missing.size >= @sizeOf(r4os.abi.ProgramMemoryBackingStoreProbe) and
            missing.status == r4os.abi.memory_backing_store_status_missing_file and
            (missing.blockers & r4os.abi.memory_backing_store_blocker_missing_file) != 0 and
            missing.pager_enabled == 0 and
            missing.anonymous_paging_enabled == 0;
        self.printCheck("Backing store missing", missing_ok);
        if (!missing_ok) return false;

        if (!self.writeBackingStoreFile(backing_store_path, backing_store_bytes)) {
            self.printCheck("Backing store create", false);
            return false;
        }
        const ready = self.dev.memoryBackingStoreProbe(backing_store_path, backing_store_bytes, 0) orelse {
            self.printCheck("Backing store probe", false);
            return false;
        };
        const ok = ready.version == r4os.abi.memory_backing_store_probe_version and
            ready.size >= @sizeOf(r4os.abi.ProgramMemoryBackingStoreProbe) and
            ready.status == r4os.abi.memory_backing_store_status_ready and
            ready.blockers == 0 and
            backingStoreReadyFlagsOk(ready.flags) and
            ready.requested_bytes == backing_store_bytes and
            ready.available_bytes >= backing_store_bytes and
            ready.file_size >= backing_store_bytes and
            ready.cluster_bytes >= 512 and
            ready.first_cluster != 0 and
            ready.pager_enabled == 0 and
            ready.anonymous_paging_enabled == 0 and
            ready.total_probes >= missing.total_probes + 1 and
            ready.total_ready > 0 and
            ready.total_failures >= missing.total_failures;
        self.printCheck("Backing store probe", ok);
        self.sys.write("  Backing store: status=");
        self.sys.printU64(ready.status);
        self.sys.write(" bytes=");
        self.sys.printU64(ready.available_bytes);
        self.sys.write("/");
        self.sys.printU64(ready.requested_bytes);
        self.sys.write(" cluster=");
        self.sys.printU64(ready.cluster_bytes);
        self.sys.write(" first=");
        self.sys.printU64(ready.first_cluster);
        self.sys.write(" probes=");
        self.sys.printU64(ready.total_probes);
        self.sys.write(" ready=");
        self.sys.printU64(ready.total_ready);
        self.sys.write(" fail=");
        self.sys.printU64(ready.total_failures);
        self.sys.write(" pager=");
        self.sys.printU64(ready.pager_enabled);
        self.sys.println("");
        return ok;
    }

    fn probeBackingStoreSlots(self: *App) bool {
        if (!self.dev.hasFn("memory_backing_store_slot_probe")) {
            self.printCheck("Backing slots probe", false);
            return false;
        }

        const missing = self.dev.memoryBackingStoreSlotProbe(missing_backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_probe, 0, 0, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, 0, 0) orelse {
            self.printCheck("Backing slots missing", false);
            return false;
        };
        const missing_ok = missing.version == r4os.abi.memory_backing_store_slot_probe_version and
            missing.size >= @sizeOf(r4os.abi.ProgramMemoryBackingStoreSlotProbe) and
            missing.status == r4os.abi.memory_backing_store_slot_status_backing_unavailable and
            (missing.blockers & r4os.abi.memory_backing_store_slot_blocker_backing_not_ready) != 0 and
            missing.pager_enabled == 0 and
            missing.eviction_enabled == 1 and
            missing.page_in_enabled == 1 and
            missing.page_out_enabled == 1;
        self.printCheck("Backing slots missing", missing_ok);
        if (!missing_ok) return false;

        if (!self.writeBackingStoreFile(backing_store_path, backing_store_bytes)) {
            self.printCheck("Backing slots create", false);
            return false;
        }

        const capacity = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_probe, 0, 0, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, 0, 0) orelse {
            self.printCheck("Backing slots capacity", false);
            return false;
        };
        const capacity_ok = capacity.status == r4os.abi.memory_backing_store_slot_status_ready and
            capacity.blockers == 0 and
            backingStoreSlotFlagsOk(capacity.flags) and
            capacity.slot_bytes == 4096 and
            capacity.capacity_slots >= backing_store_slot_count and
            capacity.reserved_slots == 0 and
            capacity.free_slots == capacity.capacity_slots and
            capacity.range_count == 0 and
            capacity.max_ranges >= 16 and
            capacity.pager_enabled == 0 and
            capacity.eviction_enabled == 1 and
            capacity.page_in_enabled == 1 and
            capacity.page_out_enabled == 1;
        self.printCheck("Backing slots capacity", capacity_ok);
        if (!capacity_ok) return false;

        const over_capacity = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_reserve, capacity.capacity_slots + 1, 0, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, 0, 0) orelse {
            self.printCheck("Backing slots over capacity", false);
            return false;
        };
        const over_capacity_ok = over_capacity.status == r4os.abi.memory_backing_store_slot_status_insufficient_capacity and
            (over_capacity.blockers & r4os.abi.memory_backing_store_slot_blocker_insufficient_capacity) != 0 and
            over_capacity.reserved_slots == 0;
        self.printCheck("Backing slots over capacity", over_capacity_ok);
        if (!over_capacity_ok) return false;

        const reserved = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_reserve, backing_store_slot_reserve, 0, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, 0, 0) orelse {
            self.printCheck("Backing slots reserve", false);
            return false;
        };
        const reserve_ok = reserved.status == r4os.abi.memory_backing_store_slot_status_reserved and
            reserved.reservation_id != 0 and
            reserved.owner_kind == r4os.abi.memory_backing_store_slot_owner_kind_diagnostic and
            reserved.owner_id == backing_store_slot_owner and
            reserved.region_id == 0 and
            reserved.slot_count == backing_store_slot_reserve and
            reserved.reserved_slots == backing_store_slot_reserve and
            reserved.free_slots + reserved.reserved_slots == reserved.capacity_slots and
            reserved.range_count == 1 and
            reserved.error_slots == 0;
        self.printCheck("Backing slots reserve", reserve_ok);
        if (!reserve_ok) return false;

        const marked = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_mark_error, 0, reserved.reservation_id, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, 0, 0) orelse {
            self.printCheck("Backing slots mark error", false);
            return false;
        };
        const marked_ok = marked.status == r4os.abi.memory_backing_store_slot_status_error_marked and
            marked.error_slots == backing_store_slot_reserve and
            marked.reserved_slots == backing_store_slot_reserve and
            marked.total_error_marks > 0;
        self.printCheck("Backing slots mark error", marked_ok);
        if (!marked_ok) return false;

        const recovered = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_recover, 0, reserved.reservation_id, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, 0, 0) orelse {
            self.printCheck("Backing slots recover", false);
            return false;
        };
        const recovered_ok = recovered.status == r4os.abi.memory_backing_store_slot_status_recovered and
            recovered.error_slots == 0 and
            recovered.reserved_slots == backing_store_slot_reserve and
            recovered.total_recoveries > 0;
        self.printCheck("Backing slots recover", recovered_ok);
        if (!recovered_ok) return false;

        const released = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_release, 0, reserved.reservation_id, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, 0, 0) orelse {
            self.printCheck("Backing slots release", false);
            return false;
        };
        const release_ok = released.status == r4os.abi.memory_backing_store_slot_status_released and
            released.reserved_slots == 0 and
            released.free_slots == released.capacity_slots and
            released.range_count == 0 and
            released.total_releases > 0;
        self.printCheck("Backing slots release", release_ok);
        if (!release_ok) return false;

        const final = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_probe, 0, 0, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, 0, 0) orelse {
            self.printCheck("Backing slots final", false);
            return false;
        };
        const final_ok = final.status == r4os.abi.memory_backing_store_slot_status_ready and
            final.reserved_slots == 0 and
            final.free_slots == final.capacity_slots and
            final.error_slots == 0 and
            final.owner_kind == r4os.abi.memory_backing_store_slot_owner_kind_diagnostic and
            final.region_id == 0 and
            final.total_reserves > 0 and
            final.total_releases > 0 and
            final.total_error_marks > 0 and
            final.total_recoveries > 0 and
            final.total_failures > 0;
        self.printCheck("Backing slots final", final_ok);
        self.sys.write("  Backing slots: status=");
        self.sys.printU64(final.status);
        self.sys.write(" cap=");
        self.sys.printU64(final.capacity_slots);
        self.sys.write(" free=");
        self.sys.printU64(final.free_slots);
        self.sys.write(" reserveOps=");
        self.sys.printU64(final.total_reserves);
        self.sys.write(" releaseOps=");
        self.sys.printU64(final.total_releases);
        self.sys.write(" errOps=");
        self.sys.printU64(final.total_error_marks);
        self.sys.write(" recoverOps=");
        self.sys.printU64(final.total_recoveries);
        self.sys.write(" fail=");
        self.sys.printU64(final.total_failures);
        self.sys.write(" pager=");
        self.sys.printU64(final.pager_enabled);
        self.sys.write("/");
        self.sys.printU64(final.eviction_enabled);
        self.sys.println("");
        return final_ok;
    }

    fn probeBackingStoreLifecycle(self: *App) bool {
        if (!self.dev.hasFn("memory_backing_store_slot_probe")) {
            self.printCheck("Backing slots lifecycle", false);
            return false;
        }

        if (!self.writeBackingStoreFile(backing_store_path, backing_store_bytes)) {
            self.printCheck("Backing slots lifecycle backing", false);
            return false;
        }

        const diagnostic = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_reserve, 1, 0, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, 0, 0) orelse {
            self.printCheck("Backing slots lifecycle diagnostic", false);
            return false;
        };
        var diagnostic_release_needed = true;
        defer {
            if (diagnostic_release_needed) _ = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_release, 0, diagnostic.reservation_id, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, 0, 0);
        }
        const diagnostic_ok = diagnostic.status == r4os.abi.memory_backing_store_slot_status_reserved and
            diagnostic.owner_kind == r4os.abi.memory_backing_store_slot_owner_kind_diagnostic and
            diagnostic.owner_id == backing_store_slot_owner and
            diagnostic.region_id == 0 and
            diagnostic.slot_count == 1;
        self.printCheck("Backing slots lifecycle diagnostic", diagnostic_ok);
        if (!diagnostic_ok) return false;

        const region = self.sys.vmReserve(backing_store_lifecycle_region_bytes, 4096, r4os.abi.vm_region_flags_default) orelse {
            self.printCheck("Backing slots lifecycle VM reserve", false);
            return false;
        };
        var region_release_needed = true;
        defer {
            if (region_release_needed) _ = self.sys.vmRelease(region.id);
        }
        const region_info = self.sys.vmQuery(region.id) orelse {
            self.printCheck("Backing slots lifecycle VM query", false);
            return false;
        };
        if (region_info.owner_id > 0xFFFF_FFFF) {
            self.printCheck("Backing slots lifecycle owner", false);
            return false;
        }
        const owner_id: u32 = @intCast(region_info.owner_id);

        const vm_slot = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_reserve, backing_store_lifecycle_vm_slots, 0, r4os.abi.memory_backing_store_slot_owner_kind_vm_region, owner_id, region.id, 0) orelse {
            self.printCheck("Backing slots lifecycle VM slot", false);
            return false;
        };
        const vm_slot_ok = vm_slot.status == r4os.abi.memory_backing_store_slot_status_reserved and
            vm_slot.owner_kind == r4os.abi.memory_backing_store_slot_owner_kind_vm_region and
            vm_slot.owner_id == owner_id and
            vm_slot.region_id == region.id and
            vm_slot.slot_count == backing_store_lifecycle_vm_slots;
        self.printCheck("Backing slots lifecycle VM slot", vm_slot_ok);
        if (!vm_slot_ok) return false;

        const bound_instance = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_reserve, 1, 0, r4os.abi.memory_backing_store_slot_owner_kind_r4x_instance, owner_id, region.id, 0) orelse {
            self.printCheck("Backing slots lifecycle bound instance", false);
            return false;
        };
        const bound_instance_ok = bound_instance.status == r4os.abi.memory_backing_store_slot_status_reserved and
            bound_instance.owner_kind == r4os.abi.memory_backing_store_slot_owner_kind_r4x_instance and
            bound_instance.owner_id == owner_id and
            bound_instance.region_id == region.id and
            bound_instance.slot_count == 1;
        self.printCheck("Backing slots lifecycle bound instance", bound_instance_ok);
        if (!bound_instance_ok) return false;

        const unbound_instance = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_reserve, 1, 0, r4os.abi.memory_backing_store_slot_owner_kind_r4x_instance, owner_id, 0, 0) orelse {
            self.printCheck("Backing slots lifecycle unbound instance", false);
            return false;
        };
        var unbound_release_needed = true;
        defer {
            if (unbound_release_needed) _ = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_release, 0, unbound_instance.reservation_id, r4os.abi.memory_backing_store_slot_owner_kind_r4x_instance, owner_id, 0, 0);
        }
        const unbound_instance_ok = unbound_instance.status == r4os.abi.memory_backing_store_slot_status_reserved and
            unbound_instance.owner_kind == r4os.abi.memory_backing_store_slot_owner_kind_r4x_instance and
            unbound_instance.owner_id == owner_id and
            unbound_instance.region_id == 0 and
            unbound_instance.slot_count == 1;
        self.printCheck("Backing slots lifecycle unbound instance", unbound_instance_ok);
        if (!unbound_instance_ok) return false;

        const before_cleanup = self.captureSummary() orelse {
            self.printCheck("Backing slots lifecycle counters", false);
            return false;
        };
        if (self.sys.vmRelease(region.id) != r4os.abi.vm_ok) {
            self.printCheck("Backing slots lifecycle VM release", false);
            return false;
        }
        region_release_needed = false;
        const after_cleanup = self.captureSummary() orelse {
            self.printCheck("Backing slots lifecycle counters", false);
            return false;
        };

        const after_release = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_probe, 0, 0, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, 0, 0) orelse {
            self.printCheck("Backing slots lifecycle cleanup", false);
            return false;
        };
        const cleaned_vm_slot = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_release, 0, vm_slot.reservation_id, r4os.abi.memory_backing_store_slot_owner_kind_vm_region, owner_id, region.id, 0) orelse {
            self.printCheck("Backing slots lifecycle cleanup", false);
            return false;
        };
        const cleanup_ok = after_release.status == r4os.abi.memory_backing_store_slot_status_ready and
            after_release.reserved_slots == diagnostic.slot_count + unbound_instance.slot_count and
            after_release.range_count == 2 and
            cleaned_vm_slot.status == r4os.abi.memory_backing_store_slot_status_reservation_not_found and
            after_cleanup.memory_backing_store_slot_lifecycle_cleanup_count > before_cleanup.memory_backing_store_slot_lifecycle_cleanup_count and
            after_cleanup.memory_backing_store_slot_lifecycle_released_ranges >= before_cleanup.memory_backing_store_slot_lifecycle_released_ranges + 2 and
            after_cleanup.memory_backing_store_slot_lifecycle_released_slots >= before_cleanup.memory_backing_store_slot_lifecycle_released_slots + backing_store_lifecycle_vm_slots + 1;
        self.printCheck("Backing slots lifecycle cleanup", cleanup_ok);
        if (!cleanup_ok) return false;

        const diagnostic_release = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_release, 0, diagnostic.reservation_id, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, 0, 0) orelse {
            self.printCheck("Backing slots lifecycle release", false);
            return false;
        };
        diagnostic_release_needed = false;
        const unbound_release = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_release, 0, unbound_instance.reservation_id, r4os.abi.memory_backing_store_slot_owner_kind_r4x_instance, owner_id, 0, 0) orelse {
            self.printCheck("Backing slots lifecycle release", false);
            return false;
        };
        unbound_release_needed = false;
        const final = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_probe, 0, 0, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, 0, 0) orelse {
            self.printCheck("Backing slots lifecycle final", false);
            return false;
        };
        const final_ok = diagnostic_release.status == r4os.abi.memory_backing_store_slot_status_released and
            unbound_release.status == r4os.abi.memory_backing_store_slot_status_released and
            final.status == r4os.abi.memory_backing_store_slot_status_ready and
            final.reserved_slots == 0 and
            final.range_count == 0 and
            final.lifecycle_cleanup_count >= after_cleanup.memory_backing_store_slot_lifecycle_cleanup_count and
            final.lifecycle_released_ranges >= after_cleanup.memory_backing_store_slot_lifecycle_released_ranges and
            final.lifecycle_released_slots >= after_cleanup.memory_backing_store_slot_lifecycle_released_slots;
        self.printCheck("Backing slots lifecycle final", final_ok);
        self.sys.write("  Backing lifecycle: owner=");
        self.sys.printU64(owner_id);
        self.sys.write(" cleaned=");
        self.sys.printU64(after_cleanup.memory_backing_store_slot_lifecycle_cleanup_count);
        self.sys.write("/");
        self.sys.printU64(after_cleanup.memory_backing_store_slot_lifecycle_released_ranges);
        self.sys.write("/");
        self.sys.printU64(after_cleanup.memory_backing_store_slot_lifecycle_released_slots);
        self.sys.println("");
        return final_ok;
    }

    fn probePagerGates(self: *App) bool {
        if (!self.dev.hasFn("memory_pager_gate_probe")) {
            self.printCheck("Pager gates probe", false);
            return false;
        }

        if (!self.writeBackingStoreFile(backing_store_path, backing_store_bytes)) {
            self.printCheck("Pager gates backing file", false);
            return false;
        }

        const missing_region = self.dev.memoryPagerGateProbe(backing_store_path, backing_store_bytes, 0xFFFF_FFFE, backing_store_gate_bytes, 0) orelse {
            self.printCheck("Pager gates missing region", false);
            return false;
        };
        const missing_region_ok = missing_region.status == r4os.abi.memory_pager_gate_status_vm_region_missing and
            (missing_region.blockers & r4os.abi.memory_pager_gate_blocker_vm_region_missing) != 0 and
            missing_region.pager_enabled == 0 and
            missing_region.page_in_enabled == 0 and
            missing_region.page_out_enabled == 0;
        self.printCheck("Pager gates missing region", missing_region_ok);
        if (!missing_region_ok) return false;

        const reserved = self.sys.vmReserve(backing_store_gate_bytes * 2, 4096, r4os.abi.vm_region_flags_default) orelse {
            self.printCheck("Pager gates VM reserve", false);
            return false;
        };
        var release_needed = true;
        defer {
            if (release_needed) _ = self.sys.vmRelease(reserved.id);
        }

        const empty_region = self.dev.memoryPagerGateProbe(backing_store_path, backing_store_bytes, reserved.id, 0, 0) orelse {
            self.printCheck("Pager gates empty region", false);
            return false;
        };
        const empty_ok = empty_region.status == r4os.abi.memory_pager_gate_status_no_nonresident_commit and
            (empty_region.blockers & r4os.abi.memory_pager_gate_blocker_no_nonresident_commit) != 0 and
            empty_region.committed_bytes == 0 and
            empty_region.nonresident_bytes == 0;
        self.printCheck("Pager gates empty region", empty_ok);
        if (!empty_ok) return false;

        if (self.sys.vmCommit(reserved.id, 0, backing_store_gate_bytes) != r4os.abi.vm_ok) {
            self.printCheck("Pager gates VM commit", false);
            return false;
        }
        const committed = self.sys.vmQuery(reserved.id) orelse {
            self.printCheck("Pager gates VM query", false);
            return false;
        };
        const committed_ok = committed.committed_bytes == backing_store_gate_bytes and committed.resident_bytes == 0;
        self.printCheck("Pager gates VM commit", committed_ok);
        if (!committed_ok) return false;

        const missing_backing = self.dev.memoryPagerGateProbe(missing_backing_store_path, backing_store_bytes, reserved.id, 0, 0) orelse {
            self.printCheck("Pager gates missing backing", false);
            return false;
        };
        const missing_backing_ok = missing_backing.status == r4os.abi.memory_pager_gate_status_backing_unavailable and
            (missing_backing.blockers & r4os.abi.memory_pager_gate_blocker_backing_not_ready) != 0;
        self.printCheck("Pager gates missing backing", missing_backing_ok);
        if (!missing_backing_ok) return false;

        const over_capacity = self.dev.memoryPagerGateProbe(backing_store_path, backing_store_bytes, reserved.id, backing_store_bytes + 4096, 0) orelse {
            self.printCheck("Pager gates over capacity", false);
            return false;
        };
        const over_capacity_ok = over_capacity.status == r4os.abi.memory_pager_gate_status_insufficient_capacity and
            (over_capacity.blockers & r4os.abi.memory_pager_gate_blocker_insufficient_capacity) != 0 and
            over_capacity.reserved_after_slots == 0;
        self.printCheck("Pager gates over capacity", over_capacity_ok);
        if (!over_capacity_ok) return false;

        const ready = self.dev.memoryPagerGateProbe(backing_store_path, backing_store_bytes, reserved.id, 0, 0) orelse {
            self.printCheck("Pager gates ready", false);
            return false;
        };
        const ready_ok = ready.version == r4os.abi.memory_pager_gate_probe_version and
            ready.size >= @sizeOf(r4os.abi.ProgramMemoryPagerGateProbe) and
            ready.status == r4os.abi.memory_pager_gate_status_ready and
            pagerGateFlagsOk(ready.flags) and
            ready.blockers == 0 and
            ready.region_id == reserved.id and
            ready.slot_bytes == 4096 and
            ready.requested_bytes == backing_store_gate_bytes and
            ready.committed_bytes == backing_store_gate_bytes and
            ready.resident_bytes == 0 and
            ready.nonresident_bytes == backing_store_gate_bytes and
            ready.requested_slots == backing_store_gate_bytes / 4096 and
            ready.prepared_slots == ready.requested_slots and
            ready.capacity_slots >= backing_store_slot_count and
            ready.free_before_slots == ready.capacity_slots and
            ready.free_after_slots == ready.capacity_slots and
            ready.reserved_before_slots == 0 and
            ready.reserved_after_slots == 0 and
            ready.rollback_completed == 1 and
            ready.commit_gate_enabled == 1 and
            ready.fault_gate_enabled == 1 and
            ready.pager_enabled == 0 and
            ready.eviction_enabled == 1 and
            ready.page_in_enabled == 0 and
            ready.page_out_enabled == 0 and
            ready.total_ready > 0 and
            ready.total_rollbacks > 0 and
            ready.total_failures > 0;
        self.printCheck("Pager gates ready", ready_ok);
        self.sys.write("  Pager gates: status=");
        self.sys.printU64(ready.status);
        self.sys.write(" region=");
        self.sys.printU64(ready.region_id);
        self.sys.write(" commit=");
        self.sys.printU64(ready.committed_bytes);
        self.sys.write(" resident=");
        self.sys.printU64(ready.resident_bytes);
        self.sys.write(" slots=");
        self.sys.printU64(ready.prepared_slots);
        self.sys.write("/");
        self.sys.printU64(ready.capacity_slots);
        self.sys.write(" rollback=");
        self.sys.printU64(ready.rollback_completed);
        self.sys.write(" pageIO=");
        self.sys.printU64(ready.page_in_enabled);
        self.sys.write("/");
        self.sys.printU64(ready.page_out_enabled);
        self.sys.println("");

        if (self.sys.vmRelease(reserved.id) != r4os.abi.vm_ok) {
            self.printCheck("Pager gates VM release", false);
            return false;
        }
        release_needed = false;
        return ready_ok;
    }

    fn probePageIo(self: *App) bool {
        if (!self.dev.hasFn("memory_page_io_probe")) {
            self.printCheck("Page I/O API", false);
            return false;
        }

        if (!self.writeBackingStoreFile(backing_store_path, backing_store_bytes)) {
            self.printCheck("Page I/O backing file", false);
            return false;
        }

        const page_io_bytes: u64 = 8192;
        const page_io_count: u64 = 2;
        const region = self.sys.vmReserve(page_io_bytes, 4096, r4os.abi.vm_region_flags_default) orelse {
            self.printCheck("Page I/O VM reserve", false);
            return false;
        };
        var region_release_needed = true;
        defer {
            if (region_release_needed) _ = self.sys.vmRelease(region.id);
        }
        if (self.sys.vmCommit(region.id, 0, page_io_bytes) != r4os.abi.vm_ok) {
            self.printCheck("Page I/O VM commit", false);
            return false;
        }

        const slot = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_reserve, page_io_count, 0, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, 0, 0) orelse {
            self.printCheck("Page I/O slot reserve", false);
            return false;
        };
        var slot_release_needed = true;
        defer {
            if (slot_release_needed) _ = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_release, 0, slot.reservation_id, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, 0, 0);
        }

        var page: [8192]u8 = undefined;
        var expected: [8192]u8 = undefined;
        var i: usize = 0;
        while (i < page.len) : (i += 1) {
            const value: u8 = @truncate(i *% 13 +% 0x31);
            page[i] = value;
            expected[i] = value;
        }

        const invalid_in = self.dev.memoryPageIoProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_page_io_operation_page_in, region.id, 0, slot.reservation_id, 0, page_io_count, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, slot.generation, page[0..], 0) orelse {
            self.printCheck("Page I/O invalid in", false);
            return false;
        };
        const invalid_ok = invalid_in.status == r4os.abi.memory_page_io_status_slot_not_valid and
            (invalid_in.blockers & r4os.abi.memory_page_io_blocker_slot_not_valid) != 0;
        self.printCheck("Page I/O invalid in", invalid_ok);
        if (!invalid_ok) return false;

        const stale = self.dev.memoryPageIoProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_page_io_operation_page_out, region.id, 0, slot.reservation_id, 0, page_io_count, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, slot.generation + 1, page[0..], 0) orelse {
            self.printCheck("Page I/O stale generation", false);
            return false;
        };
        const stale_ok = stale.status == r4os.abi.memory_page_io_status_stale_generation and
            (stale.blockers & r4os.abi.memory_page_io_blocker_stale_generation) != 0;
        self.printCheck("Page I/O stale generation", stale_ok);
        if (!stale_ok) return false;

        const transient = self.dev.memoryPageIoProbe(missing_backing_store_path, backing_store_bytes, r4os.abi.memory_page_io_operation_page_out, region.id, 0, slot.reservation_id, 0, page_io_count, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, slot.generation, page[0..], r4os.abi.memory_page_io_flag_retry_request) orelse {
            self.printCheck("Page I/O retryable failure", false);
            return false;
        };
        const transient_ok = transient.status == r4os.abi.memory_page_io_status_backing_unavailable and
            (transient.blockers & r4os.abi.memory_page_io_blocker_backing_not_ready) != 0 and
            (transient.flags & r4os.abi.memory_page_io_flag_retry_request) != 0 and
            (transient.flags & r4os.abi.memory_page_io_flag_retryable_failure) != 0 and
            (transient.flags & r4os.abi.memory_page_io_flag_data_preserved) != 0 and
            transient.total_data_lost_pages == 0;
        self.printCheck("Page I/O retryable failure", transient_ok);
        if (!transient_ok) return false;

        const page_out = self.dev.memoryPageIoProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_page_io_operation_page_out, region.id, 0, slot.reservation_id, 0, page_io_count, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, slot.generation, page[0..], 0) orelse {
            self.printCheck("Page I/O page out", false);
            return false;
        };
        const out_ok = page_out.status == r4os.abi.memory_page_io_status_page_out_ok and
            pageIoFlagsOk(page_out.flags, r4os.abi.memory_page_io_operation_page_out) and
            page_out.blockers == 0 and
            (page_out.flags & r4os.abi.memory_page_io_flag_multi_page) != 0 and
            page_out.owner_kind == r4os.abi.memory_backing_store_slot_owner_kind_diagnostic and
            page_out.owner_id == backing_store_slot_owner and
            page_out.page_count == page_io_count and
            page_out.transfer_bytes == page_io_bytes and
            @as(u64, page_out.io_bytes) == page_io_bytes and
            page_out.io_status == @as(i32, @intCast(page_io_bytes)) and
            page_out.valid_slots >= page_io_count and
            page_out.dirty_slots == 0 and
            page_out.error_slots == 0 and
            page_out.pager_enabled == 0 and
            page_out.eviction_enabled == 1 and
            page_out.backing_offset < backing_store_bytes;
        self.printCheck("Page I/O page out", out_ok);
        if (!out_ok) return false;

        const duplicate = self.dev.memoryPageIoProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_page_io_operation_page_out, region.id, 0, slot.reservation_id, 0, page_io_count, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, page_out.slot_generation, page[0..], r4os.abi.memory_page_io_flag_retry_request) orelse {
            self.printCheck("Page I/O duplicate out", false);
            return false;
        };
        const duplicate_ok = duplicate.status == r4os.abi.memory_page_io_status_slot_already_valid and
            (duplicate.blockers & r4os.abi.memory_page_io_blocker_slot_already_valid) != 0 and
            (duplicate.flags & r4os.abi.memory_page_io_flag_retry_request) != 0 and
            (duplicate.flags & r4os.abi.memory_page_io_flag_permanent_failure) != 0 and
            (duplicate.flags & r4os.abi.memory_page_io_flag_data_preserved) != 0 and
            duplicate.total_retry_limit_hits > 0;
        self.printCheck("Page I/O duplicate out", duplicate_ok);
        if (!duplicate_ok) return false;

        const marked = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_mark_error, 0, slot.reservation_id, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, 0, 0) orelse {
            self.printCheck("Page I/O mark error", false);
            return false;
        };
        const marked_ok = marked.status == r4os.abi.memory_backing_store_slot_status_error_marked and marked.error_slots >= page_io_count;
        self.printCheck("Page I/O mark error", marked_ok);
        if (!marked_ok) return false;

        const error_in = self.dev.memoryPageIoProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_page_io_operation_page_in, region.id, 0, slot.reservation_id, 0, page_io_count, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, marked.generation, page[0..], 0) orelse {
            self.printCheck("Page I/O error gate", false);
            return false;
        };
        const error_ok = error_in.status == r4os.abi.memory_page_io_status_slot_error and
            (error_in.blockers & r4os.abi.memory_page_io_blocker_slot_error) != 0;
        self.printCheck("Page I/O error gate", error_ok);
        if (!error_ok) return false;

        const recovered = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_recover, 0, slot.reservation_id, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, 0, 0) orelse {
            self.printCheck("Page I/O recover", false);
            return false;
        };
        const recovered_ok = recovered.status == r4os.abi.memory_backing_store_slot_status_recovered and
            recovered.error_slots == 0 and
            recovered.valid_slots == 0;
        self.printCheck("Page I/O recover", recovered_ok);
        if (!recovered_ok) return false;

        const recovered_in = self.dev.memoryPageIoProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_page_io_operation_page_in, region.id, 0, slot.reservation_id, 0, page_io_count, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, recovered.generation, page[0..], 0) orelse {
            self.printCheck("Page I/O recovered invalid", false);
            return false;
        };
        const recovered_in_ok = recovered_in.status == r4os.abi.memory_page_io_status_slot_not_valid and
            (recovered_in.blockers & r4os.abi.memory_page_io_blocker_slot_not_valid) != 0;
        self.printCheck("Page I/O recovered invalid", recovered_in_ok);
        if (!recovered_in_ok) return false;

        const page_out_recovered = self.dev.memoryPageIoProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_page_io_operation_page_out, region.id, 0, slot.reservation_id, 0, page_io_count, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, recovered.generation, expected[0..], r4os.abi.memory_page_io_flag_retry_request) orelse {
            self.printCheck("Page I/O page out retry", false);
            return false;
        };
        const out_retry_ok = page_out_recovered.status == r4os.abi.memory_page_io_status_page_out_ok and
            pageIoFlagsOk(page_out_recovered.flags, r4os.abi.memory_page_io_operation_page_out) and
            page_out_recovered.page_count == page_io_count and
            page_out_recovered.transfer_bytes == page_io_bytes and
            @as(u64, page_out_recovered.io_bytes) == page_io_bytes and
            page_out_recovered.io_status == @as(i32, @intCast(page_io_bytes)) and
            (page_out_recovered.flags & r4os.abi.memory_page_io_flag_retry_request) != 0 and
            page_out_recovered.total_retry_attempts > 0;
        self.printCheck("Page I/O page out retry", out_retry_ok);
        if (!out_retry_ok) return false;

        @memset(page[0..], 0);
        const page_in = self.dev.memoryPageIoProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_page_io_operation_page_in, region.id, 0, slot.reservation_id, 0, page_io_count, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, page_out_recovered.slot_generation, page[0..], 0) orelse {
            self.printCheck("Page I/O page in", false);
            return false;
        };
        const in_ok = page_in.status == r4os.abi.memory_page_io_status_page_in_ok and
            pageIoFlagsOk(page_in.flags, r4os.abi.memory_page_io_operation_page_in) and
            page_in.blockers == 0 and
            (page_in.flags & r4os.abi.memory_page_io_flag_multi_page) != 0 and
            page_in.owner_kind == r4os.abi.memory_backing_store_slot_owner_kind_diagnostic and
            page_in.owner_id == backing_store_slot_owner and
            page_in.page_count == page_io_count and
            page_in.transfer_bytes == page_io_bytes and
            page_in.expected_generation == page_out_recovered.slot_generation and
            @as(u64, page_in.io_bytes) == page_io_bytes and
            page_in.io_status == @as(i32, @intCast(page_io_bytes)) and
            page_in.valid_slots >= page_io_count and
            page_in.dirty_slots == 0 and
            page_in.error_slots == 0 and
            page_in.pager_enabled == 0 and
            page_in.eviction_enabled == 1 and
            bytesEqual(page[0..], expected[0..]);
        self.printCheck("Page I/O page in", in_ok);
        if (!in_ok) return false;

        const perf = self.captureSummary() orelse {
            self.printCheck("Page I/O performance", false);
            return false;
        };
        const perf_ok = (perf.flags & r4os.abi.performance_flag_memory_page_io_ready) != 0 and
            (perf.flags & r4os.abi.performance_flag_memory_pager_error_policy_ready) != 0 and
            perf.memory_page_io_status == r4os.abi.memory_page_io_status_page_in_ok and
            pageIoFlagsOk(perf.memory_page_io_flags, r4os.abi.memory_page_io_operation_page_in) and
            perf.memory_page_io_owner_kind == r4os.abi.memory_backing_store_slot_owner_kind_diagnostic and
            perf.memory_page_io_owner_id == backing_store_slot_owner and
            perf.memory_page_io_page_count == page_io_count and
            perf.memory_page_io_transfer_bytes == page_io_bytes and
            perf.memory_page_io_expected_generation == page_out_recovered.slot_generation and
            perf.memory_page_io_page_out_count > 0 and
            perf.memory_page_io_page_in_count > 0 and
            perf.memory_page_io_failure_count > 0 and
            perf.memory_page_io_retry_attempt_count > 0 and
            perf.memory_page_io_retryable_failure_count > 0 and
            perf.memory_page_io_permanent_failure_count > 0 and
            perf.memory_page_io_retry_limit_hit_count > 0 and
            perf.memory_page_io_failed_page_out_count > 0 and
            perf.memory_page_io_failed_page_in_count > 0 and
            perf.memory_page_io_data_preserved_pages >= page_io_count and
            perf.memory_page_io_data_lost_pages == 0 and
            perf.memory_page_io_pager_enabled == 0 and
            perf.memory_page_io_eviction_enabled == 1;
        self.printCheck("Page I/O performance", perf_ok);

        self.sys.write("  Page I/O: out=");
        self.sys.printU64(page_out.total_page_outs);
        self.sys.write(" in=");
        self.sys.printU64(page_in.total_page_ins);
        self.sys.write(" fail=");
        self.sys.printU64(page_in.total_failures);
        self.sys.write(" retry=");
        self.sys.printU64(page_in.total_retry_attempts);
        self.sys.write("/");
        self.sys.printU64(page_in.total_retryable_failures);
        self.sys.write("/");
        self.sys.printU64(page_in.total_permanent_failures);
        self.sys.write(" preserved/lost=");
        self.sys.printU64(page_in.total_data_preserved_pages);
        self.sys.write("/");
        self.sys.printU64(page_in.total_data_lost_pages);
        self.sys.write(" slot=");
        self.sys.printU64(page_in.backing_slot);
        self.sys.write(" offset=");
        self.sys.printU64(page_in.backing_offset);
        self.sys.write(" pages=");
        self.sys.printU64(page_in.page_count);
        self.sys.write(" eviction=");
        self.sys.printU64(page_in.eviction_enabled);
        self.sys.println("");

        const released = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_release, 0, slot.reservation_id, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, 0, 0) orelse {
            self.printCheck("Page I/O slot release", false);
            return false;
        };
        slot_release_needed = false;
        _ = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_probe, 0, 0, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, 0, 0);
        if (released.status != r4os.abi.memory_backing_store_slot_status_released) {
            self.printCheck("Page I/O slot release", false);
            return false;
        }

        if (self.sys.vmRelease(region.id) != r4os.abi.vm_ok) {
            self.printCheck("Page I/O VM release", false);
            return false;
        }
        region_release_needed = false;
        return perf_ok;
    }

    fn probeVmPageState(self: *App) bool {
        if (!self.dev.hasFn("memory_vm_page_state_probe")) {
            self.printCheck("VM page state API", false);
            return false;
        }

        if (!self.writeBackingStoreFile(backing_store_path, backing_store_bytes)) {
            self.printCheck("VM page state backing file", false);
            return false;
        }

        const state_pages: u64 = 4;
        const state_bytes: u64 = state_pages * 4096;
        const region = self.sys.vmReserve(state_bytes, 4096, r4os.abi.vm_region_flags_default) orelse {
            self.printCheck("VM page state reserve", false);
            return false;
        };
        var region_release_needed = true;
        defer {
            if (region_release_needed) _ = self.sys.vmRelease(region.id);
        }
        if (self.sys.vmCommit(region.id, 0, state_bytes) != r4os.abi.vm_ok) {
            self.printCheck("VM page state commit", false);
            return false;
        }

        const initial = self.dev.memoryVmPageStateProbe(region.id, 0, state_pages, r4os.abi.memory_vm_page_state_operation_query, 0, 0, 0, 0) orelse {
            self.printCheck("VM page state commit", false);
            return false;
        };
        const initial_ok = initial.status == r4os.abi.memory_vm_page_state_status_ready and
            initial.committed_pages == state_pages and
            initial.resident_pages == 0 and
            initial.nonresident_pages == state_pages and
            initial.dirty_pages == 0 and
            initial.clean_pages == state_pages and
            (initial.flags & r4os.abi.memory_vm_page_state_flag_committed) != 0 and
            (initial.flags & r4os.abi.memory_vm_page_state_flag_eviction_enabled) != 0 and
            (initial.flags & r4os.abi.memory_vm_page_state_flag_no_swap) != 0 and
            (initial.flags & r4os.abi.memory_vm_page_state_flag_fault_page_in) != 0 and
            (initial.flags & r4os.abi.memory_vm_page_state_flag_no_fault_io) == 0;
        self.printCheck("VM page state commit", initial_ok);
        if (!initial_ok) return false;

        const ptr: [*]u8 = @ptrFromInt(region.base);
        ptr[0] = 0xA5;
        ptr[4096] = 0x5A;
        const touched = self.dev.memoryVmPageStateProbe(region.id, 0, state_pages, r4os.abi.memory_vm_page_state_operation_query, 0, 0, 0, 0) orelse {
            self.printCheck("VM page state touch", false);
            return false;
        };
        const touched_ok = touched.status == r4os.abi.memory_vm_page_state_status_ready and
            touched.resident_pages >= 2 and
            touched.nonresident_pages <= state_pages - 2 and
            touched.dirty_pages >= 2 and
            (touched.flags & r4os.abi.memory_vm_page_state_flag_hardware_dirty_synced) != 0;
        self.printCheck("VM page state touch", touched_ok);
        if (!touched_ok) return false;

        const clean_one = self.dev.memoryVmPageStateProbe(region.id, 0, 1, r4os.abi.memory_vm_page_state_operation_mark_clean, 0, 0, 0, 0) orelse {
            self.printCheck("VM page state clean", false);
            return false;
        };
        _ = self.dev.memoryVmPageStateProbe(region.id, 8192, 1, r4os.abi.memory_vm_page_state_operation_mark_dirty, 0, 0, 0, 0) orelse {
            self.printCheck("VM page state dirty", false);
            return false;
        };
        const dirty_third = self.dev.memoryVmPageStateProbe(region.id, 0, state_pages, r4os.abi.memory_vm_page_state_operation_query, 0, 0, 0, 0) orelse {
            self.printCheck("VM page state dirty", false);
            return false;
        };
        const dirty_clean_ok = clean_one.status == r4os.abi.memory_vm_page_state_status_ready and
            dirty_third.status == r4os.abi.memory_vm_page_state_status_ready and
            dirty_third.dirty_pages >= 2 and
            dirty_third.clean_pages <= state_pages - 2;
        self.printCheck("VM page state dirty clean", dirty_clean_ok);
        if (!dirty_clean_ok) return false;

        _ = self.dev.memoryVmPageStateProbe(region.id, 0, 1, r4os.abi.memory_vm_page_state_operation_mark_pinned, 0, 0, 0, 0) orelse {
            self.printCheck("VM page state flags", false);
            return false;
        };
        _ = self.dev.memoryVmPageStateProbe(region.id, 4096, 1, r4os.abi.memory_vm_page_state_operation_mark_busy, 0, 0, 0, 0) orelse {
            self.printCheck("VM page state flags", false);
            return false;
        };
        _ = self.dev.memoryVmPageStateProbe(region.id, 4096, 1, r4os.abi.memory_vm_page_state_operation_mark_error, 0, 0, 0, 0) orelse {
            self.printCheck("VM page state flags", false);
            return false;
        };
        const marked_flags = self.dev.memoryVmPageStateProbe(region.id, 0, state_pages, r4os.abi.memory_vm_page_state_operation_query, 0, 0, 0, 0) orelse {
            self.printCheck("VM page state flags", false);
            return false;
        };
        const flags_marked_ok = marked_flags.pinned_pages == 1 and marked_flags.busy_pages == 1 and marked_flags.error_pages == 1;
        self.printCheck("VM page state flags", flags_marked_ok);
        if (!flags_marked_ok) return false;

        _ = self.dev.memoryVmPageStateProbe(region.id, 0, 1, r4os.abi.memory_vm_page_state_operation_clear_pinned, 0, 0, 0, 0) orelse {
            self.printCheck("VM page state clear flags", false);
            return false;
        };
        _ = self.dev.memoryVmPageStateProbe(region.id, 4096, 1, r4os.abi.memory_vm_page_state_operation_clear_busy, 0, 0, 0, 0) orelse {
            self.printCheck("VM page state clear flags", false);
            return false;
        };
        _ = self.dev.memoryVmPageStateProbe(region.id, 4096, 1, r4os.abi.memory_vm_page_state_operation_clear_error, 0, 0, 0, 0) orelse {
            self.printCheck("VM page state clear flags", false);
            return false;
        };
        const cleared_flags = self.dev.memoryVmPageStateProbe(region.id, 0, state_pages, r4os.abi.memory_vm_page_state_operation_query, 0, 0, 0, 0) orelse {
            self.printCheck("VM page state clear flags", false);
            return false;
        };
        const flags_cleared_ok = cleared_flags.pinned_pages == 0 and cleared_flags.busy_pages == 0 and cleared_flags.error_pages == 0;
        self.printCheck("VM page state clear flags", flags_cleared_ok);
        if (!flags_cleared_ok) return false;

        const region_info = self.sys.vmQuery(region.id) orelse {
            self.printCheck("VM page state owner", false);
            return false;
        };
        if (region_info.owner_id > 0xFFFF_FFFF) {
            self.printCheck("VM page state owner", false);
            return false;
        }
        const owner_id: u32 = @intCast(region_info.owner_id);
        const slot = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_reserve, 2, 0, r4os.abi.memory_backing_store_slot_owner_kind_vm_region, owner_id, region.id, 0) orelse {
            self.printCheck("VM page state slot", false);
            return false;
        };
        var slot_release_needed = true;
        defer {
            if (slot_release_needed) _ = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_release, 0, slot.reservation_id, r4os.abi.memory_backing_store_slot_owner_kind_vm_region, owner_id, region.id, 0);
        }
        const slot_ok = slot.status == r4os.abi.memory_backing_store_slot_status_reserved and
            slot.owner_kind == r4os.abi.memory_backing_store_slot_owner_kind_vm_region and
            slot.owner_id == owner_id and
            slot.region_id == region.id;
        self.printCheck("VM page state slot", slot_ok);
        if (!slot_ok) return false;

        var expected: [8192]u8 = undefined;
        var i: usize = 0;
        while (i < expected.len) : (i += 1) {
            expected[i] = @truncate(i *% 7 +% 0x21);
            ptr[i] = expected[i];
        }
        const before_error_policy = self.captureSummary() orelse {
            self.printCheck("VM pager error policy", false);
            return false;
        };
        const error_byte_before = ptr[17];
        const page_out_missing = self.dev.memoryPageIoProbe(missing_backing_store_path, backing_store_bytes, r4os.abi.memory_page_io_operation_page_out, region.id, 0, slot.reservation_id, 0, 1, r4os.abi.memory_backing_store_slot_owner_kind_vm_region, owner_id, slot.generation, ptr[0..4096], r4os.abi.memory_page_io_flag_retry_request) orelse {
            self.printCheck("VM pager error policy", false);
            return false;
        };
        const after_error_state = self.dev.memoryVmPageStateProbe(region.id, 0, state_pages, r4os.abi.memory_vm_page_state_operation_query, 0, 0, 0, 0) orelse {
            self.printCheck("VM pager error policy", false);
            return false;
        };
        const after_error_policy = self.captureSummary() orelse {
            self.printCheck("VM pager error policy", false);
            return false;
        };
        const vm_error_policy_ok = page_out_missing.status == r4os.abi.memory_page_io_status_backing_unavailable and
            (page_out_missing.flags & r4os.abi.memory_page_io_flag_retryable_failure) != 0 and
            (page_out_missing.flags & r4os.abi.memory_page_io_flag_data_preserved) != 0 and
            ptr[17] == error_byte_before and
            after_error_state.status == r4os.abi.memory_vm_page_state_status_ready and
            after_error_state.resident_pages >= 2 and
            after_error_state.dirty_pages >= 2 and
            after_error_policy.memory_page_io_retryable_failure_count > before_error_policy.memory_page_io_retryable_failure_count and
            after_error_policy.memory_page_io_failed_page_out_count > before_error_policy.memory_page_io_failed_page_out_count and
            after_error_policy.memory_page_io_data_preserved_pages > before_error_policy.memory_page_io_data_preserved_pages and
            after_error_policy.memory_page_io_data_lost_pages == 0 and
            after_error_policy.memory_vm_pager_failed_page_out_count > before_error_policy.memory_vm_pager_failed_page_out_count and
            after_error_policy.memory_vm_pager_data_preserved_pages > before_error_policy.memory_vm_pager_data_preserved_pages and
            after_error_policy.memory_vm_pager_dirty_preserved_pages > before_error_policy.memory_vm_pager_dirty_preserved_pages and
            after_error_policy.memory_vm_pager_data_lost_pages == 0;
        self.printCheck("VM pager error policy", vm_error_policy_ok);
        if (!vm_error_policy_ok) return false;

        const before_page_out_summary = self.captureSummary() orelse {
            self.printCheck("VM page state page out", false);
            return false;
        };
        const page_out = self.dev.memoryPageIoProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_page_io_operation_page_out, region.id, 0, slot.reservation_id, 0, 2, r4os.abi.memory_backing_store_slot_owner_kind_vm_region, owner_id, slot.generation, ptr[0..8192], 0) orelse {
            self.printCheck("VM page state page out", false);
            return false;
        };
        const after_page_out = self.dev.memoryVmPageStateProbe(region.id, 0, state_pages, r4os.abi.memory_vm_page_state_operation_query, 0, 0, 0, 0) orelse {
            self.printCheck("VM page state page out", false);
            return false;
        };
        const after_page_out_summary = self.captureSummary() orelse {
            self.printCheck("VM page state page out", false);
            return false;
        };
        const page_out_ok = page_out.status == r4os.abi.memory_page_io_status_page_out_ok and
            after_page_out.status == r4os.abi.memory_vm_page_state_status_ready and
            after_page_out.slot_bound_pages >= 2 and
            after_page_out.nonresident_pages >= 2 and
            after_page_out.slot_reservation_id == slot.reservation_id and
            after_page_out.slot_generation == page_out.slot_generation and
            after_page_out.dirty_pages <= dirty_third.dirty_pages and
            after_page_out_summary.memory_vm_page_state_page_out_nonresident_pages >= before_page_out_summary.memory_vm_page_state_page_out_nonresident_pages + 2;
        self.printCheck("VM page state page out", page_out_ok);
        if (!page_out_ok) return false;

        const before_fault = self.captureSummary() orelse {
            self.printCheck("VM page state fault page in", false);
            return false;
        };
        const fault_byte0 = ptr[0];
        const fault_byte1 = ptr[4096 + 17];
        const after_fault = self.dev.memoryVmPageStateProbe(region.id, 0, state_pages, r4os.abi.memory_vm_page_state_operation_query, 0, 0, 0, 0) orelse {
            self.printCheck("VM page state fault page in", false);
            return false;
        };
        const after_fault_summary = self.captureSummary() orelse {
            self.printCheck("VM page state fault page in", false);
            return false;
        };
        const fault_ok = fault_byte0 == expected[0] and
            fault_byte1 == expected[4096 + 17] and
            after_fault.status == r4os.abi.memory_vm_page_state_status_ready and
            after_fault.resident_pages >= 2 and
            after_fault.slot_bound_pages >= 2 and
            after_fault.slot_reservation_id == slot.reservation_id and
            after_fault.slot_generation == page_out.slot_generation and
            after_fault_summary.memory_vm_page_state_fault_page_in_count >= before_fault.memory_vm_page_state_fault_page_in_count + 2 and
            after_fault_summary.memory_page_io_page_in_count >= before_fault.memory_page_io_page_in_count + 2 and
            after_fault_summary.memory_page_io_status == r4os.abi.memory_page_io_status_page_in_ok and
            after_fault_summary.memory_page_io_owner_kind == r4os.abi.memory_backing_store_slot_owner_kind_vm_region and
            after_fault_summary.memory_page_io_page_count == 1 and
            after_fault_summary.memory_page_io_region_offset == 4096 and
            after_fault_summary.memory_page_io_io_bytes == 4096;
        self.printCheck("VM page state fault page in", fault_ok);
        if (!fault_ok) return false;

        const clear_slot = self.dev.memoryVmPageStateProbe(region.id, 0, 2, r4os.abi.memory_vm_page_state_operation_clear_slot, 0, 0, 0, 0) orelse {
            self.printCheck("VM page state clear slot", false);
            return false;
        };
        const clear_slot_ok = clear_slot.status == r4os.abi.memory_vm_page_state_status_ready and clear_slot.slot_bound_pages == 0;
        self.printCheck("VM page state clear slot", clear_slot_ok);
        if (!clear_slot_ok) return false;

        const before_cleanup = self.captureSummary() orelse {
            self.printCheck("VM page state cleanup", false);
            return false;
        };
        if (self.sys.vmRelease(region.id) != r4os.abi.vm_ok) {
            self.printCheck("VM page state cleanup", false);
            return false;
        }
        region_release_needed = false;
        slot_release_needed = false;
        const after_cleanup = self.captureSummary() orelse {
            self.printCheck("VM page state cleanup", false);
            return false;
        };
        const cleanup_ok = after_cleanup.memory_vm_page_state_cleanup_pages >= before_cleanup.memory_vm_page_state_cleanup_pages + state_pages and
            after_cleanup.memory_vm_page_state_transition_count >= before_cleanup.memory_vm_page_state_transition_count;
        const final_slot = self.dev.memoryBackingStoreSlotProbe(backing_store_path, backing_store_bytes, r4os.abi.memory_backing_store_slot_operation_probe, 0, 0, r4os.abi.memory_backing_store_slot_owner_kind_diagnostic, backing_store_slot_owner, 0, 0) orelse {
            self.printCheck("VM page state cleanup", false);
            return false;
        };
        const cleanup_final_ok = cleanup_ok and
            final_slot.status == r4os.abi.memory_backing_store_slot_status_ready and
            final_slot.reserved_slots == 0 and
            final_slot.free_slots == final_slot.capacity_slots and
            final_slot.valid_slots == 0 and
            final_slot.dirty_slots == 0 and
            final_slot.error_slots == 0 and
            final_slot.owner_kind == r4os.abi.memory_backing_store_slot_owner_kind_diagnostic and
            final_slot.region_id == 0;
        self.printCheck("VM page state cleanup", cleanup_final_ok);

        self.sys.write("  VM page state: resident=");
        self.sys.printU64(touched.resident_pages);
        self.sys.write(" dirty=");
        self.sys.printU64(after_page_out.dirty_pages);
        self.sys.write(" slot=");
        self.sys.printU64(after_page_out.slot_bound_pages);
        self.sys.write(" spans=");
        self.sys.printU64(after_cleanup.memory_vm_page_state_span_count);
        self.sys.write(" cleanup=");
        self.sys.printU64(after_cleanup.memory_vm_page_state_cleanup_pages);
        self.sys.write(" pageIn=");
        self.sys.printU64(after_fault_summary.memory_vm_page_state_fault_page_in_count);
        self.sys.println("");

        return cleanup_final_ok;
    }

    fn probeVmEvictionReclaim(self: *App) bool {
        if (!self.dev.hasFn("memory_pressure_snapshot")) {
            self.printCheck("VM eviction reclaim", false);
            return false;
        }

        if (!self.writeBackingStoreFile(backing_store_path, backing_store_bytes)) {
            self.printCheck("VM eviction backing file", false);
            return false;
        }

        const evict_pages: u64 = 4;
        const evict_bytes: u64 = evict_pages * 4096;
        const evict_len: usize = @intCast(evict_bytes);
        const region = self.sys.vmReserve(evict_bytes, 4096, r4os.abi.vm_region_flags_default) orelse {
            self.printCheck("VM eviction reserve", false);
            return false;
        };
        var region_release_needed = true;
        defer {
            if (region_release_needed) _ = self.sys.vmRelease(region.id);
        }
        if (self.sys.vmCommit(region.id, 0, evict_bytes) != r4os.abi.vm_ok) {
            self.printCheck("VM eviction commit", false);
            return false;
        }

        const ptr: [*]u8 = @ptrFromInt(region.base);
        var byte_index: usize = 0;
        while (byte_index < evict_len) : (byte_index += 1) {
            ptr[byte_index] = @truncate(byte_index *% 11 +% 0x33);
        }
        _ = self.dev.memoryVmPageStateProbe(region.id, 0, 1, r4os.abi.memory_vm_page_state_operation_mark_pinned, 0, 0, 0, 0) orelse {
            self.printCheck("VM eviction pin", false);
            return false;
        };

        const before_state = self.dev.memoryVmPageStateProbe(region.id, 0, evict_pages, r4os.abi.memory_vm_page_state_operation_query, 0, 0, 0, 0) orelse {
            self.printCheck("VM eviction state", false);
            return false;
        };
        const before = self.captureSummary() orelse {
            self.printCheck("VM eviction baseline", false);
            return false;
        };

        const frame_bytes: u64 = if (before.fs_cache_payload_frame_bytes == 0) 4096 else before.fs_cache_payload_frame_bytes;
        var remaining_fs_frames = before.fs_cache_pmm_reclaimable_bytes / frame_bytes;
        const fs_frames = remaining_fs_frames + 1;
        var requested_frames: u32 = if (fs_frames > 1024) 1024 else @intCast(fs_frames);
        if (requested_frames == 0) requested_frames = 1;

        var probe: ?r4os.abi.ProgramMemoryReclaimProbe = null;
        const max_reclaim_attempts: u32 = 16;
        var attempts: u32 = 0;
        while (attempts < max_reclaim_attempts) : (attempts += 1) {
            const current = self.dev.memoryReclaimProbe(requested_frames) orelse {
                self.printCheck("VM eviction reclaim", false);
                return false;
            };
            probe = current;
            if (current.vm_returned_frames > 0 and current.vm_page_outs > 0) break;

            const returned_fs_frames = @as(u64, current.fs_returned_frames);
            remaining_fs_frames = if (returned_fs_frames >= remaining_fs_frames)
                0
            else
                remaining_fs_frames - returned_fs_frames;
            const actual_cap = if (current.requested_frames == 0) 1 else current.requested_frames;
            const next_request = @min(remaining_fs_frames + 1, @as(u64, actual_cap));
            requested_frames = @intCast(next_request);
        }
        const final_probe = probe orelse {
            self.printCheck("VM eviction reclaim", false);
            return false;
        };

        const after_reclaim = self.captureSummary() orelse {
            self.printCheck("VM eviction summary", false);
            return false;
        };
        const after_state = self.dev.memoryVmPageStateProbe(region.id, 0, evict_pages, r4os.abi.memory_vm_page_state_operation_query, 0, 0, 0, 0) orelse {
            self.printCheck("VM eviction post-state", false);
            return false;
        };

        var evicted_page: u64 = evict_pages;
        var page_index: u64 = 1;
        while (page_index < evict_pages) : (page_index += 1) {
            const page_state = self.dev.memoryVmPageStateProbe(region.id, page_index * 4096, 1, r4os.abi.memory_vm_page_state_operation_query, 0, 0, 0, 0) orelse {
                self.printCheck("VM eviction page state", false);
                return false;
            };
            if (page_state.status == r4os.abi.memory_vm_page_state_status_ready and
                page_state.nonresident_pages == 1 and
                page_state.slot_bound_pages == 1)
            {
                evicted_page = page_index;
                break;
            }
        }

        const target_was_evicted = after_state.nonresident_pages > 0 or after_state.slot_bound_pages > 0;
        const target_state_ok = if (target_was_evicted)
            after_state.nonresident_pages > 0 and
                after_state.slot_bound_pages > 0 and
                evicted_page < evict_pages
        else
            after_state.resident_pages >= evict_pages and
                after_state.nonresident_pages == 0 and
                after_state.slot_bound_pages == 0;
        const ok = before_state.status == r4os.abi.memory_vm_page_state_status_ready and
            before_state.resident_pages >= evict_pages and
            before_state.pinned_pages == 1 and
            final_probe.version == r4os.abi.memory_reclaim_probe_version and
            final_probe.size >= @sizeOf(r4os.abi.ProgramMemoryReclaimProbe) and
            final_probe.vm_returned_frames > 0 and
            final_probe.vm_page_outs > 0 and
            final_probe.vm_failures == 0 and
            final_probe.failed_drains == 0 and
            after_reclaim.global_reclaim_vm_returned_frames >= before.global_reclaim_vm_returned_frames + final_probe.vm_returned_frames and
            after_reclaim.global_reclaim_vm_page_outs >= before.global_reclaim_vm_page_outs + final_probe.vm_page_outs and
            after_reclaim.memory_vm_eviction_success_count > before.memory_vm_eviction_success_count and
            after_reclaim.memory_vm_eviction_returned_frames >= before.memory_vm_eviction_returned_frames + final_probe.vm_returned_frames and
            after_state.status == r4os.abi.memory_vm_page_state_status_ready and
            after_state.pinned_pages == 1 and
            target_state_ok;
        self.printCheck("VM eviction reclaim", ok);
        const attempts_made = if (attempts < max_reclaim_attempts) attempts + 1 else attempts;
        self.sys.write("  VM eviction: attempts=");
        self.sys.printU64(attempts_made);
        self.sys.write(" requested=");
        self.sys.printU64(final_probe.requested_frames);
        self.sys.write(" returned=");
        self.sys.printU64(final_probe.returned_frames);
        self.sys.write(" fs=");
        self.sys.printU64(final_probe.fs_returned_frames);
        self.sys.write(" vm=");
        self.sys.printU64(final_probe.vm_returned_frames);
        self.sys.write(" pageOut=");
        self.sys.printU64(final_probe.vm_page_outs);
        self.sys.write(" vmFail=");
        self.sys.printU64(final_probe.vm_failures);
        self.sys.write(" page=");
        self.sys.printU64(evicted_page);
        self.sys.write(" targetEvicted=");
        self.sys.write(if (target_was_evicted) "yes" else "no");
        self.sys.println("");

        if (self.sys.vmRelease(region.id) != r4os.abi.vm_ok) {
            self.printCheck("VM eviction cleanup", false);
            return false;
        }
        region_release_needed = false;
        return ok;
    }

    fn writeBackingStoreFile(self: *App, path: [*:0]const u8, total_bytes: u64) bool {
        if (self.sys.fileStreamBegin(path, r4os.abi.file_stream_open_replace) != r4os.abi.file_stream_result_ok) return false;
        var chunk: [4096]u8 = undefined;
        var i: usize = 0;
        while (i < chunk.len) : (i += 1) {
            chunk[i] = @as(u8, @truncate(i *% 17 +% 0x5A));
        }
        var offset: u64 = 0;
        while (offset < total_bytes) {
            const remaining = total_bytes - offset;
            const len: usize = if (remaining > chunk.len) chunk.len else @intCast(remaining);
            const written = self.sys.fileStreamWrite(path, offset, chunk[0..len], 0);
            if (written != @as(i32, @intCast(len))) {
                _ = self.sys.fileStreamAbort(path);
                return false;
            }
            offset += @intCast(len);
        }
        return self.sys.fileStreamFinish(path, total_bytes, 0) == r4os.abi.file_stream_result_ok;
    }

    fn probeServiceQueue(self: *App) bool {
        var info: r4os.abi.ServiceInfo = .{};
        const status_rc = self.sys.serviceStatus("SVCAPPD", &info);
        if (status_rc == r4os.abi.service_api_result_not_found) return true;
        if (status_rc != r4os.abi.service_api_result_ok) {
            self.sys.write("  Service queue probe status rc=");
            self.sys.printI32(status_rc);
            self.sys.println("");
            self.printCheck("Service queue probe", false);
            return false;
        }
        var ok = info.state == r4os.abi.service_state_running and
            (info.flags & r4os.abi.service_api_flag_endpoint) != 0 and
            (info.flags & r4os.abi.service_api_flag_queue_backed) != 0 and
            info.queue_depth == r4os.abi.service_api_endpoint_queue_depth;

        const open_rc = self.sys.serviceOpen("SVCAPPD", &info);
        if (open_rc != r4os.abi.service_api_result_ok or info.handle == 0) {
            self.sys.write("  Service queue probe open rc=");
            self.sys.printI32(open_rc);
            self.sys.println("");
            self.printCheck("Service queue probe", false);
            return false;
        }
        defer _ = self.sys.serviceClose(info.handle);

        var header: r4os.abi.ServiceMessageHeader = .{};
        var response: [16]u8 = undefined;
        const echo_len = self.sys.serviceCall(info.handle, 1, "PING", &header, response[0..], 100);
        if (echo_len != 4 or header.status != r4os.abi.service_api_result_ok or !bytesEq(response[0..4], "PING")) ok = false;

        var tiny: [2]u8 = undefined;
        const small_rc = self.sys.serviceCall(info.handle, 1, "PONG", &header, tiny[0..], 100);
        if (small_rc != r4os.abi.service_api_result_buffer_too_small) ok = false;

        const too_large: [r4os.abi.service_api_max_payload + 1]u8 = .{0} ** (r4os.abi.service_api_max_payload + 1);
        const large_rc = self.sys.serviceCall(info.handle, 1, too_large[0..], &header, response[0..], 100);
        if (large_rc != r4os.abi.service_api_result_payload_too_large) ok = false;

        const bad_op_len = self.sys.serviceCall(info.handle, 0x9999, "X", &header, response[0..], 100);
        if (bad_op_len <= 0 or header.status != r4os.abi.service_api_result_bad_op) ok = false;

        var queue_info: r4os.abi.ServiceInfo = .{};
        const queue_rc = self.sys.serviceStatus("SVCAPPD", &queue_info);
        if (queue_rc != r4os.abi.service_api_result_ok or
            queue_info.queue_depth != r4os.abi.service_api_endpoint_queue_depth or
            queue_info.queue_high_water == 0 or
            queue_info.requests < 3 or
            queue_info.responses < 3 or
            queue_info.busy_rejections != 0 or
            queue_info.timeouts != 0)
        {
            ok = false;
        }

        self.printCheck("Service queue probe", ok);
        if (!ok) {
            self.sys.write("  svc status=");
            self.sys.printI32(status_rc);
            self.sys.write(" open=");
            self.sys.printI32(open_rc);
            self.sys.write(" q=");
            self.sys.printU64(queue_info.queue_used);
            self.sys.write("/");
            self.sys.printU64(queue_info.queue_depth);
            self.sys.write(" high=");
            self.sys.printU64(queue_info.queue_high_water);
            self.sys.write(" req=");
            self.sys.printU64(queue_info.requests);
            self.sys.write(" resp=");
            self.sys.printU64(queue_info.responses);
            self.sys.write(" busy=");
            self.sys.printU64(queue_info.busy_rejections);
            self.sys.write(" timeout=");
            self.sys.printU64(queue_info.timeouts);
            self.sys.println("");
        }
        return ok;
    }

    fn failBool(self: *App, msg: []const u8) bool {
        self.recordCheck(msg, false);
        self.sys.write("  ");
        self.sys.println(msg);
        return false;
    }
};

fn preemptionWorkerMain(_: u64) callconv(.c) i32 {
    const stop: *volatile u32 = &preemption_worker_stop;
    var rounds: u32 = 0;
    while (stop.* == 0 and rounds < 4096) : (rounds += 1) {
        spinForPreemption(1);
    }
    return if (stop.* != 0) 38 else 39;
}

fn avxWorkerMain(arg: u64) callconv(.c) i32 {
    const slot: usize = if (arg == 0) 0 else 1;
    const pattern = if (slot == 0) &avx_pattern_a else &avx_pattern_b;
    var scratch: [32]u8 align(32) = .{0} ** 32;
    var rounds: u32 = 0;
    while (rounds < 96) : (rounds += 1) {
        avxLoadYmm0(pattern);
        const sink: *volatile u64 = &preemption_burn_sink;
        var i: u64 = 0;
        while (i < 65536) : (i += 1) {
            sink.* = sink.* +% ((i << 2) ^ @as(u64, rounds + 31) ^ (sink.* >> 5));
        }
        avxStoreYmm0(&scratch);
        if (!bytesEq(scratch[0..], pattern[0..])) {
            avx_worker_results[slot] = 2;
            return if (slot == 0) 76 else 77;
        }
    }
    avx_worker_results[slot] = 1;
    return if (slot == 0) 74 else 75;
}

inline fn avxLoadYmm0(src: *const [32]u8) void {
    asm volatile ("vmovdqu (%[src]), %%ymm0"
        :
        : [src] "r" (src),
    );
}

inline fn avxStoreYmm0(dst: *[32]u8) void {
    asm volatile ("vmovdqu %%ymm0, (%[dst])"
        :
        : [dst] "r" (dst),
    );
}

fn spinForPreemption(rounds: u32) void {
    const sink: *volatile u64 = &preemption_burn_sink;
    var round: u32 = 0;
    while (round < rounds) : (round += 1) {
        var i: u64 = 0;
        while (i < 32768) : (i += 1) {
            sink.* = sink.* +% ((i << 1) ^ @as(u64, round + 17) ^ (sink.* >> 7));
        }
    }
}

pub fn r4_app_main(r4_app: *r4os.App) i32 {
    var app = App.init(r4_app) orelse return r4os.abi.err_no_group;
    return app.run();
}

fn runClassification(mode: measurement.Mode) []const u8 {
    return switch (mode) {
        .baseline => "passive-snapshot",
        .conformance => "contract-conformance",
        .benchmark => "performance-benchmark",
    };
}

fn timeBackendName(value: u32) []const u8 {
    return switch (value) {
        0 => "pit",
        1 => "hpet",
        2 => "lapic",
        else => "unknown",
    };
}

fn clockSourceName(value: u32) []const u8 {
    return switch (value) {
        r4os.abi.monotonic_clock_source_unavailable => "unavailable",
        r4os.abi.monotonic_clock_source_tsc => "tsc",
        r4os.abi.monotonic_clock_source_hpet => "hpet",
        r4os.abi.monotonic_clock_source_periodic_event => "periodic-event",
        else => "unknown",
    };
}

fn spanZ(raw: []const u8) []const u8 {
    var len: usize = 0;
    while (len < raw.len and raw[len] != 0) : (len += 1) {}
    return raw[0..len];
}

fn bytesEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn kernelIpcRequest(
    net: *const r4os.r4net.Context,
    channel_id: u32,
    op: u16,
    request_id: u32,
    payload: []const u8,
    expected_status: i32,
    require_payload: bool,
) bool {
    var response: [r4os.abi.ipc_max_message_size]u8 = undefined;
    const got = net.netServiceRequest(channel_id, op, request_id, payload, response[0..]);
    if (got < @as(i32, @intCast(r4os.abi.net_service_header_size))) return false;
    var status: i32 = 0;
    const result_payload = net.netServicePayload(response[0..@intCast(got)], &status) orelse return false;
    if (status != expected_status) return false;
    return if (require_payload) result_payload.len != 0 else result_payload.len == 0;
}

fn captureKernelIpcPerformance(
    net: *const r4os.r4net.Context,
    out: *KernelIpcPerformanceSnapshots,
) bool {
    for (kernel_ipc_channels, 0..) |channel_id, index| {
        out[index] = .{};
        if (net.ipcPerformance(channel_id, &out[index]) <= 0 or
            !ipcPerformanceContractOk(out[index]) or
            out[index].active_channels != 1 or
            out[index].queue_limit < r4os.abi.ipc_queue_depth or
            out[index].queue_used > out[index].queue_limit) return false;
    }
    return true;
}

fn kernelIpcPerformanceQuiet(
    previous: *const KernelIpcPerformanceSnapshots,
    current: *const KernelIpcPerformanceSnapshots,
) bool {
    for (previous.*, current.*) |before, after| {
        if (before.queue_used != 0 or before.queue_ready != 0 or before.queue_running != 0 or
            after.queue_used != 0 or after.queue_ready != 0 or after.queue_running != 0 or
            after.handler_queued != before.handler_queued or
            after.handler_completed != before.handler_completed or
            after.handler_failures != before.handler_failures or
            after.handler_waits != before.handler_waits or
            after.handler_wait_timeouts != before.handler_wait_timeouts or
            after.request_bytes != before.request_bytes or
            after.response_bytes != before.response_bytes or
            after.queue_full != before.queue_full or
            after.admission_timeouts != before.admission_timeouts or
            after.stale_drops != before.stale_drops) return false;
    }
    return true;
}

fn kernelIpcSampleHasConcurrentTraffic(
    sample: KernelIpcSample,
    requests: u64,
    expected_request_bytes: u64,
    minimum_response_bytes: u64,
) bool {
    const copied_request_and_response = sample.payload_copy_bytes >= sample.request_bytes and
        sample.payload_copy_bytes - sample.request_bytes >= sample.response_bytes;
    return sample.handler_queued > requests and
        sample.handler_completed == sample.handler_queued and
        sample.handler_waits == sample.handler_queued and
        sample.handler_failures == 0 and
        sample.handler_direct == 0 and
        sample.handler_wait_timeouts == 0 and
        sample.request_bytes > expected_request_bytes and
        sample.response_bytes >= minimum_response_bytes and
        copied_request_and_response and
        sample.payload_clear_bytes == 0 and
        sample.queue_full == 0 and
        sample.admission_timeouts == 0 and
        sample.recv_buffer_small == 0 and
        sample.response_search_slots == 0 and
        sample.stale_drops == 0 and
        sample.irq_denied == 0 and
        sample.queue_used_after == 0;
}

fn ipcPerformanceContractOk(summary: r4os.abi.IpcPerformanceSummary) bool {
    return summary.version >= 1 and
        summary.size >= @sizeOf(r4os.abi.IpcPerformanceSummary) and
        summary.worker_started != 0 and
        summary.queue_limit != 0;
}

fn delta(after: u64, before: u64) u64 {
    return if (after >= before) after - before else 0;
}

fn counterDelta(before: u64, after: u64) u64 {
    return after -% before;
}

fn sameClockInterval(start: r4os.abi.MonotonicClockInfo, end: r4os.abi.MonotonicClockInfo) bool {
    return start.generation != 0 and end.generation == start.generation and end.instant_ns > start.instant_ns;
}

fn perUnitCost(elapsed_ns: u64, units: u64) u64 {
    if (elapsed_ns == 0 or units == 0) return 0;
    return (elapsed_ns +| (units - 1)) / units;
}

fn memoryMetadataSummaryContractOk(summary: r4os.abi.ProgramPerformanceSummary) bool {
    const required_size = @offsetOf(r4os.abi.ProgramPerformanceSummary, "hot_path_memory_vm_reclaim_wraps") + @sizeOf(u64);
    return summary.version >= 8 and summary.size >= required_size;
}

fn memoryMetadataSampleOk(sample: MemoryMetadataSample) bool {
    // Global reclaim may legitimately select another eligible R4X range at
    // its persistent cursor. The target must remain internally consistent;
    // the separate reclaim gate below proves the requested multi-frame work.
    const target_accounting = sample.target_committed_pages == sample.pages and
        sample.target_resident_pages + sample.target_nonresident_pages == sample.pages and
        sample.target_slot_bound_pages == sample.target_nonresident_pages;
    const block_index_ok = sample.block_physical_index_entries > 0 and
        sample.block_physical_step_max > 0 and sample.block_physical_step_max <= 32 and
        sample.block_id_index_entries > 0 and
        sample.block_id_step_max > 0 and sample.block_id_step_max <= 128 and
        sample.block_free_slot_word_step_max > 0 and sample.block_free_slot_word_step_max <= 128 and
        sample.block_physical_lookups > 0 and sample.block_physical_steps >= sample.block_physical_lookups and
        sample.block_physical_mutations > 0 and sample.block_physical_rebuilds == 0 and
        sample.block_id_lookups > 0 and sample.block_id_steps >= sample.block_id_lookups and
        sample.block_free_slot_lookups > 0 and sample.block_free_slot_word_steps >= sample.block_free_slot_lookups and
        sample.block_claim_transactions >= sample.pages and sample.block_claim_rollbacks == 0;
    const vm_index_ok = sample.range_address_entries > 0 and
        sample.range_address_probe_max > 0 and sample.range_address_probe_max <= 16 and
        sample.commit_span_active > 0 and sample.commit_span_step_max > 0 and sample.commit_span_step_max <= 64 and
        sample.page_state_span_active > 0 and sample.page_state_span_step_max > 0 and sample.page_state_span_step_max <= 64 and
        sample.range_address_lookups >= sample.pages and sample.range_address_probes >= sample.range_address_lookups and
        sample.commit_span_lookups > 0 and sample.commit_span_steps > 0 and
        sample.page_state_span_lookups > 0 and sample.page_state_span_steps > 0;
    const reclaim_range_bound = sample.reclaim_vm_returned_frames +
        @as(u64, sample.range_address_entries) * @as(u64, sample.reclaim_attempts) + sample.pages;
    const reclaim_ok = sample.reclaim_attempts > 0 and
        sample.reclaim_attempts <= measurement.memory_metadata_reclaim_max_attempts and
        sample.reclaim_vm_returned_frames >= sample.pages and
        sample.reclaim_vm_page_outs >= sample.pages and
        sample.reclaim_vm_failures == 0 and
        sample.reclaim_returned_frames >= sample.reclaim_vm_returned_frames + sample.reclaim_fs_returned_frames and
        sample.reclaim_range_steps > 0 and sample.reclaim_range_steps <= reclaim_range_bound and
        sample.reclaim_span_steps > 0 and sample.reclaim_page_steps >= sample.reclaim_vm_returned_frames;
    return sample.pages == measurement.memory_metadata_pages_per_sample and
        sample.reserve_commit_elapsed_ns > 0 and sample.reserve_commit_ns_per_page > 0 and
        sample.fault_elapsed_ns > 0 and sample.fault_ns_per_page > 0 and
        sample.page_state_elapsed_ns > 0 and sample.page_state_ns_per_page > 0 and
        sample.reclaim_elapsed_ns > 0 and sample.reclaim_ns_per_vm_frame > 0 and
        target_accounting and block_index_ok and vm_index_ok and reclaim_ok;
}

fn pciInventorySnapshotContractOk(info: r4os.abi.ProgramPciInventoryPerformanceInfo) bool {
    const vendor_probes = info.vendor_probes_ecam +% info.vendor_probes_legacy;
    const retained_accounting = info.stored == info.ecam_stored +% info.legacy_stored;
    const found_accounting = info.found == info.stored +% info.dropped;
    const read_accounting = info.enumeration_config_reads ==
        vendor_probes +% info.class_reads +% info.header_reads;
    const truncation_ok = if (info.dropped == 0)
        (info.flags & r4os.abi.pci_inventory_flag_truncated) == 0 and info.early_stops == 0
    else
        (info.flags & r4os.abi.pci_inventory_flag_truncated) != 0 and info.early_stops != 0;
    const ecam_ok = if ((info.flags & r4os.abi.pci_inventory_flag_ecam) != 0)
        (info.flags & r4os.abi.pci_inventory_flag_ecam_aperture_ready) != 0 and
            info.mapping_checks == 2 and info.mapping_hits == 2 and info.mapping_misses == 0 and
            info.mapping_fast_accesses == info.ecam_config_reads +% info.ecam_config_writes
    else
        true;
    return info.version >= 1 and
        info.size >= @sizeOf(r4os.abi.ProgramPciInventoryPerformanceInfo) and
        (info.flags & r4os.abi.pci_inventory_flag_enumerated) != 0 and
        info.generation != 0 and
        info.capacity == r4os.abi.pci_inventory_capacity and info.stored <= info.capacity and
        info.found != 0 and retained_accounting and found_accounting and
        info.function_pages == vendor_probes and read_accounting and truncation_ok and ecam_ok and
        (info.enumeration_total_ns != 0 or info.timing_unavailable != 0);
}

fn mixPciInventoryRecord(hash: *u64, record: r4os.abi.DeviceInventoryRecord) void {
    mixServiceRegistryValue(hash, record.binding);
    mixServiceRegistryValue(hash, record.bus);
    mixServiceRegistryValue(hash, record.flags);
    mixServiceRegistryValue(hash, record.bus_no);
    mixServiceRegistryValue(hash, record.device_no);
    mixServiceRegistryValue(hash, record.function_no);
    mixServiceRegistryValue(hash, record.class_code);
    mixServiceRegistryValue(hash, record.subclass);
    mixServiceRegistryValue(hash, record.prog_if);
    mixServiceRegistryValue(hash, record.vendor_id);
    mixServiceRegistryValue(hash, record.device_id);
    mixServiceRegistryBytes(hash, record.name[0..]);
    mixServiceRegistryBytes(hash, record.driver[0..]);
    mixServiceRegistryBytes(hash, record.status[0..]);
    mixServiceRegistryBytes(hash, record.note[0..]);
}

fn reductionBasisPoints(reference: u64, current: u64) u64 {
    if (reference == 0 or current >= reference) return 0;
    return @intCast((@as(u128, reference - current) * 10_000) / reference);
}

fn serviceRegistrySummaryContractOk(summary: r4os.abi.ProgramPerformanceSummary) bool {
    const required_size = @offsetOf(r4os.abi.ProgramPerformanceSummary, "service_registry_index_end_markers") +
        @sizeOf(u64);
    return summary.version >= 7 and summary.size >= required_size;
}

fn mixServiceRegistryValue(hash: *u64, value: u64) void {
    hash.* = (hash.* ^ value) *% 0x100000001b3;
}

fn mixServiceRegistryBytes(hash: *u64, raw: []const u8) void {
    const value = spanZ(raw);
    mixServiceRegistryValue(hash, value.len);
    for (value) |byte| mixServiceRegistryValue(hash, byte);
}

fn consumeServiceInfo(hash: *u64, info: *const r4os.abi.ServiceInfo, servman_diag: bool) void {
    mixServiceRegistryValue(hash, info.handle);
    mixServiceRegistryValue(hash, info.state);
    mixServiceRegistryValue(hash, info.start_mode);
    mixServiceRegistryValue(hash, info.flags);
    mixServiceRegistryValue(hash, info.instance_id);
    mixServiceRegistryBytes(hash, info.name[0..]);
    if (!servman_diag) return;
    mixServiceRegistryValue(hash, @bitCast(@as(i64, info.exit_code)));
    mixServiceRegistryValue(hash, info.restart_count);
    mixServiceRegistryValue(hash, info.start_tick);
    mixServiceRegistryValue(hash, info.uptime_ticks);
    mixServiceRegistryValue(hash, info.requests);
    mixServiceRegistryValue(hash, info.responses);
    mixServiceRegistryValue(hash, info.drops);
    mixServiceRegistryValue(hash, info.queue_depth);
    mixServiceRegistryValue(hash, info.queue_used);
    mixServiceRegistryValue(hash, info.queue_high_water);
    mixServiceRegistryValue(hash, info.active_workers);
    mixServiceRegistryValue(hash, info.max_active_workers);
    mixServiceRegistryValue(hash, info.open_handles);
    mixServiceRegistryValue(hash, info.busy_rejections);
    mixServiceRegistryValue(hash, info.timeouts);
    mixServiceRegistryValue(hash, info.cancellations);
    mixServiceRegistryBytes(hash, info.last_error[0..]);
}

fn consumeServiceDetail(hash: *u64, detail: *const r4os.abi.ServiceDetail, servman_diag: bool) void {
    consumeServiceInfo(hash, &detail.info, servman_diag);
    mixServiceRegistryBytes(hash, detail.path[0..]);
    mixServiceRegistryBytes(hash, detail.args[0..]);
    mixServiceRegistryBytes(hash, detail.description[0..]);
}

fn pagefileBlockersOk(blockers: u32) bool {
    const required = r4os.abi.fs_cache_pagefile_blocker_no_pagefile |
        r4os.abi.fs_cache_pagefile_blocker_no_swap |
        r4os.abi.fs_cache_pagefile_blocker_no_pager;
    const forbidden = r4os.abi.fs_cache_pagefile_blocker_static_cache |
        r4os.abi.fs_cache_pagefile_blocker_no_global_reclaim;
    return (blockers & required) == required and (blockers & forbidden) == 0;
}

fn backingStoreReadyFlagsOk(flags: u32) bool {
    const required = r4os.abi.memory_backing_store_flag_file_backed |
        r4os.abi.memory_backing_store_flag_existing_file |
        r4os.abi.memory_backing_store_flag_fat32 |
        r4os.abi.memory_backing_store_flag_reserve_only |
        r4os.abi.memory_backing_store_flag_pager_disabled |
        r4os.abi.memory_backing_store_flag_uses_fs_api |
        r4os.abi.memory_backing_store_flag_no_second_io_path |
        r4os.abi.memory_backing_store_flag_page_aligned_request;
    return (flags & required) == required;
}

fn backingStoreSlotFlagsOk(flags: u32) bool {
    const required = r4os.abi.memory_backing_store_slot_flag_file_backed |
        r4os.abi.memory_backing_store_slot_flag_backing_ready |
        r4os.abi.memory_backing_store_slot_flag_metadata_only |
        r4os.abi.memory_backing_store_slot_flag_range_table |
        r4os.abi.memory_backing_store_slot_flag_page_sized_slots |
        r4os.abi.memory_backing_store_slot_flag_pager_disabled |
        r4os.abi.memory_backing_store_slot_flag_recovery_available;
    const forbidden = r4os.abi.memory_backing_store_slot_flag_eviction_disabled |
        r4os.abi.memory_backing_store_slot_flag_no_page_io;
    return (flags & required) == required and (flags & forbidden) == 0;
}

fn pagerGateFlagsOk(flags: u32) bool {
    const required = r4os.abi.memory_pager_gate_flag_file_backed |
        r4os.abi.memory_pager_gate_flag_backing_ready |
        r4os.abi.memory_pager_gate_flag_metadata_only |
        r4os.abi.memory_pager_gate_flag_vm_region_attached |
        r4os.abi.memory_pager_gate_flag_commit_gate |
        r4os.abi.memory_pager_gate_flag_fault_gate |
        r4os.abi.memory_pager_gate_flag_slot_reservation_tested |
        r4os.abi.memory_pager_gate_flag_rollback_complete |
        r4os.abi.memory_pager_gate_flag_pager_disabled |
        r4os.abi.memory_pager_gate_flag_no_page_io |
        r4os.abi.memory_pager_gate_flag_no_swap |
        r4os.abi.memory_pager_gate_flag_no_second_io_path |
        r4os.abi.memory_pager_gate_flag_page_sized_slots;
    return (flags & required) == required;
}

fn pageIoFlagsOk(flags: u32, operation: u32) bool {
    const required = r4os.abi.memory_page_io_flag_file_backed |
        r4os.abi.memory_page_io_flag_backing_ready |
        r4os.abi.memory_page_io_flag_vm_region_attached |
        r4os.abi.memory_page_io_flag_slot_reserved |
        r4os.abi.memory_page_io_flag_slot_valid |
        r4os.abi.memory_page_io_flag_slot_clean |
        r4os.abi.memory_page_io_flag_explicit_request |
        r4os.abi.memory_page_io_flag_uses_fs_api |
        r4os.abi.memory_page_io_flag_no_second_io_path |
        r4os.abi.memory_page_io_flag_pager_disabled |
        r4os.abi.memory_page_io_flag_no_swap |
        r4os.abi.memory_page_io_flag_page_sized_slots |
        r4os.abi.memory_page_io_flag_owner_matched |
        r4os.abi.memory_page_io_flag_generation_checked;
    const op_flag = if (operation == r4os.abi.memory_page_io_operation_page_in)
        r4os.abi.memory_page_io_flag_page_in
    else
        r4os.abi.memory_page_io_flag_page_out;
    return (flags & (required | op_flag)) == (required | op_flag);
}

fn bytesEqual(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}
