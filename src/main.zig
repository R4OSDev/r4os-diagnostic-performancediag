const r4os = @import("r4os");

const backing_store_path = "C:\\TEMP\\R4PAGE.BIN";
const missing_backing_store_path = "C:\\TEMP\\R4MISS.SWP";
const backing_store_bytes: u64 = 64 * 1024;
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
var preemption_worker_stop: u32 = 0;
var avx_worker_results: [2]u32 = .{ 0, 0 };
// 0.56.12: Frame-Puffer fuer den Blit-Durchsatz-Benchmark (320x64 XRGB).
var blit_bench_frame: [320 * 64]u32 = .{0} ** (320 * 64);
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

const App = struct {
    sys: r4os.r4sys.Context,
    dev: r4os.r4dev.Context,
    draw: r4os.r4draw.Context,
    audio: r4os.r4audio.Context,

    fn init(r4_app: *r4os.App) ?App {
        return .{
            .sys = r4_app.system(),
            .dev = r4_app.devicesLowLevel() orelse return null,
            .draw = r4_app.drawing() orelse return null,
            .audio = r4_app.audioLowLevel() orelse return null,
        };
    }

    fn run(self: *App) i32 {
        self.sys.println("PERFDIAG");
        var ok = true;
        ok = self.testApiHeader() and ok;
        self.sys.sleepTicks(1);
        var fs_probe: [64]u8 = undefined;
        _ = self.sys.fileReadAt("C:\\R4OS\\CONFIG\\VERSION.R4S", 0, fs_probe[0..]);
        ok = self.testLocalFpuArithmetic() and ok;
        ok = self.probeDisplayResponsiveness() and ok;
        ok = self.probeBlitThroughput() and ok;
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
        const summary = self.dev.performanceSummary() orelse {
            _ = self.failBool("Performance snapshot unavailable");
            self.sys.println("PERFDIAG result: FAILED");
            return 1;
        };
        ok = self.testSummary(summary) and ok;
        ok = self.testPreemption(summary) and ok;
        ok = self.testSchedulerLatency(summary) and ok;
        ok = self.testFpuState(summary) and ok;
        ok = self.testAvxState(summary) and ok;
        ok = self.testDriverWork(summary) and ok;
        ok = self.testTasks(summary) and ok;
        ok = self.testStorage(summary) and ok;
        ok = self.testBootPhases(summary) and ok;
        self.printBaseline(summary);

        self.sys.write("PERFDIAG result: ");
        self.sys.println(if (ok) "OK" else "FAILED");
        return if (ok) 0 else 1;
    }

    fn testApiHeader(self: *App) bool {
        const ok = self.sys.contractValid() and self.dev.hasFn("performance_summary") and self.dev.hasFn("memory_reclaim_probe") and self.dev.hasFn("memory_reclaim_probe") and self.dev.hasFn("memory_backing_store_probe") and self.dev.hasFn("memory_backing_store_slot_probe") and self.dev.hasFn("memory_pager_gate_probe") and self.dev.hasFn("memory_page_io_probe") and self.dev.hasFn("memory_vm_page_state_probe") and self.dev.hasFn("memory_page_io_probe") and self.dev.hasFn("memory_pressure_snapshot") and self.dev.hasFn("memory_pager_gate_probe") and true and self.dev.hasFn("performance_summary") and true and self.dev.hasFn("performance_summary") and self.dev.hasFn("performance_summary") and self.dev.hasFn("performance_summary") and self.dev.hasFn("performance_summary") and self.dev.hasFn("performance_summary") and self.dev.hasFn("performance_summary") and self.dev.hasFn("performance_summary");
        self.printCheck("R4DEV performance snapshot v143", ok);
        if (!ok) return false;
        self.sys.write("  API version=");
        self.sys.printU64(self.sys.tableAbiVersion());
        self.sys.write(" size=");
        self.sys.printU64(self.sys.tableSize());
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
            summary.service_completion_timeouts <= summary.service_timeouts and
            summary.service_cancellations <= summary.service_drops;
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
            summary.loader_file_full_reads == 0 and
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
        const expected_page_io_bytes: u64 = if (page_io_last_is_vm_region_in) 4096 else 8192;
        const expected_page_io_pages: u64 = if (page_io_last_is_vm_region_in) 1 else 2;
        const expected_page_io_region_offset: u64 = if (page_io_last_is_vm_region_in) 4096 else 0;
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
        const ok = summary.version == r4os.abi.performance_snapshot_version and
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
            summary.fs_cache_dirty_entries == 0 and
            summary.fs_cache_dirty_bytes == 0 and
            summary.fs_cache_writeback_queue_depth == 0 and
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
            summary.fs_cache_pmm_dirty_bytes == 0 and
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
            summary.global_reclaim_last_returned_frames <= summary.global_reclaim_last_requested_frames and
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
            summary.memory_backing_store_slot_reserved == 0 and
            summary.memory_backing_store_slot_free == summary.memory_backing_store_slot_capacity and
            summary.memory_backing_store_slot_valid == 0 and
            summary.memory_backing_store_slot_dirty == 0 and
            summary.memory_backing_store_slot_error == 0 and
            summary.memory_backing_store_slot_range_count == 0 and
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
            summary.memory_page_io_blockers == 0 and
            summary.memory_page_io_slot_bytes == 4096 and
            summary.memory_page_io_io_bytes == expected_page_io_bytes and
            summary.memory_page_io_io_status == @as(i32, @intCast(expected_page_io_bytes)) and
            summary.memory_page_io_page_count == expected_page_io_pages and
            summary.memory_page_io_transfer_bytes == expected_page_io_bytes and
            summary.memory_page_io_expected_generation != 0 and
            summary.memory_page_io_pager_enabled == 0 and
            summary.memory_page_io_eviction_enabled == 1 and
            summary.memory_page_io_page_in_enabled == 1 and
            summary.memory_page_io_page_out_enabled == 1 and
            summary.memory_page_io_region_offset == expected_page_io_region_offset and
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
            display_responsiveness_ok and
            audio_latency_ok and
            loader_perf_ok and
            loader_memory_ok and
            hot_path_ok and
            flags_ok and
            wait_missing_ok and
            lock_ok;
        self.printCheck("Performance summary fields", ok);
        if (!ok) {
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
        return ok;
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
        const before = self.dev.performanceSummary() orelse return self.failBool("AVX snapshot unavailable");
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
            self.printCheck("Display responsiveness present", false);
            return false;
        }
        const before = self.dev.displaySummary() orelse {
            self.printCheck("Display responsiveness present", false);
            return false;
        };
        const pixel: [1]u32 = .{0x00_20_60_a0};
        const begin_rc = self.draw.displayBeginFrameRect(0, 0, 1, 1);
        const blit_rc = self.draw.displayBlitXrgb32(0, 0, 1, 1, pixel[0..]);
        const present_rc = self.draw.displayPresent();
        const after = self.dev.displaySummary() orelse {
            self.printCheck("Display responsiveness present", false);
            return false;
        };
        const ok = begin_rc > 0 and
            blit_rc >= 0 and
            present_rc > 0 and
            after.present_count > before.present_count and
            after.present_bytes_total >= before.present_bytes_total + 4 and
            after.present_max_ticks >= after.present_last_ticks and
            after.present_total_ticks >= before.present_total_ticks;
        self.printCheck("Display responsiveness present", ok);
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

    // 0.56.12: Blit-Durchsatz-Mikrobenchmark (Vorher/Nachher-Beleg fuer
    // den copyToVisible-Fast-Path). Adaptiv: blittet 320x64-XRGB-Frames,
    // bis >=30 Ticks vergangen sind (oder Deckel), und rechnet MB/s.
    fn probeBlitThroughput(self: *App) bool {
        if (!self.dev.hasFn("display_summary")) {
            self.printCheck("Blit throughput bench", false);
            return false;
        }
        const width: u32 = 320;
        const height: u32 = 64;
        const pixel_count: usize = @as(usize, width) * height;
        var i: usize = 0;
        while (i < pixel_count) : (i += 1) {
            blit_bench_frame[i] = 0xFF000000 | @as(u32, @intCast((i * 7) & 0xFFFFFF));
        }
        const min_ticks: u64 = 30;
        const max_iters: u64 = 20000;
        var iters: u64 = 0;
        const start = self.sys.ticks();
        var elapsed: u64 = 0;
        while (iters < max_iters) {
            _ = self.draw.displayBeginFrameRect(0, 0, width, height);
            const rc = self.draw.displayBlitXrgb32(0, 0, width, height, blit_bench_frame[0..pixel_count]);
            const present_rc = self.draw.displayPresent();
            if (rc < 0 or present_rc <= 0) {
                self.printCheck("Blit throughput bench", false);
                return false;
            }
            iters += 1;
            elapsed = self.sys.ticks() - start;
            if (elapsed >= min_ticks) break;
        }
        const bytes_total = iters * pixel_count * 4;
        // Ticks laufen mit ~100 Hz: MB/s = bytes / (ticks/100) / 1MB.
        const mb_s: u64 = if (elapsed > 0)
            (bytes_total * 100) / (elapsed * 1024 * 1024)
        else
            0;
        self.sys.write("PERFDIAG blit-bench: iters=");
        self.sys.printU64(iters);
        self.sys.write(" ticks=");
        self.sys.printU64(elapsed);
        self.sys.write(" bytes=");
        self.sys.printU64(bytes_total);
        self.sys.write(" approx_mb_s=");
        self.sys.printU64(mb_s);
        self.sys.println("");
        self.printCheck("Blit throughput bench", true);
        return true;
    }

    fn probeAudioLatency(self: *App) bool {
        if (!self.dev.hasFn("performance_summary")) {
            self.printCheck("Audio latency write", false);
            return false;
        }
        const before = self.dev.performanceSummary() orelse {
            self.printCheck("Audio latency write", false);
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
            self.printCheck("Audio latency write", false);
            return false;
        }
        const stream_id: u32 = @intCast(stream);
        const written = self.audio.audioWrite(stream_id, pcm[0..]);
        const closed = self.audio.audioClose(stream_id);
        const after = self.dev.performanceSummary() orelse {
            self.printCheck("Audio latency write", false);
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
        self.printCheck("Audio latency write", ok);
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
        const ok = (summary.flags & r4os.abi.performance_flag_driver_workqueue_ready) != 0 and
            summary.driver_work_worker_started != 0 and
            summary.driver_work_capacity >= r4os.abi.driver_work_queue_capacity and
            // 0.56.31-Triage: Inaktivitaet ist seit der R4D-Treiber-
            // Auslagerung (0.56.12) der Sollzustand im Normal-Boot; die
            // Aktiv-Erwartungen gelten weiter, sobald Items laufen.
            ((summary.driver_work_submitted_from_irq == 0 and
                summary.driver_work_started == 0 and
                summary.driver_work_failed == 0 and
                summary.driver_work_dropped == 0 and
                summary.driver_work_wait_timeouts == 0 and
                summary.driver_work_invalid_handles == 0) or
                (summary.driver_work_submitted_from_irq > 0 and
                    summary.driver_work_submitted_from_task == 0 and
                    summary.driver_work_started > 0 and
                    summary.driver_work_completed > 0 and
                    summary.driver_work_failed == 0 and
                    summary.driver_work_dropped == 0 and
                    summary.driver_work_waits > 0 and
                    summary.driver_work_wait_timeouts == 0 and
                    summary.driver_work_wait_denied_irq == 0 and
                    summary.driver_work_releases > 0 and
                    summary.driver_work_invalid_handles == 0));
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
        self.printCheck("Storage counter baseline", ok);
        return ok;
    }

    fn testBootPhases(self: *App, summary: r4os.abi.ProgramPerformanceSummary) bool {
        var saw_runtime = false;
        var checked: u32 = 0;
        var i: u32 = 0;
        while (i < summary.boot_phase_count) : (i += 1) {
            const phase = self.dev.performanceBootPhase(i) orelse return self.failBool("Boot phase performance entry unavailable");
            checked += 1;
            if (phase.phase == 13) saw_runtime = true;
            if (i < 12) self.printBootPhase(phase);
        }
        const ok = checked > 0 and saw_runtime;
        self.printCheck("Boot phase baseline", ok);
        return ok;
    }

    fn printBaseline(self: *App, summary: r4os.abi.ProgramPerformanceSummary) void {
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
        self.sys.println("");

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
        const before = self.dev.performanceSummary() orelse {
            self.printCheck("FS page cache read-through", false);
            return false;
        };
        var first: [128]u8 = undefined;
        var second: [128]u8 = undefined;
        const a = self.sys.fileReadAt("C:\\R4OS\\CONFIG\\VERSION.R4S", 0, first[0..]);
        const b = self.sys.fileReadAt("C:\\R4OS\\CONFIG\\VERSION.R4S", 0, second[0..]);
        const after = self.dev.performanceSummary() orelse {
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
        const before = self.dev.performanceSummary() orelse {
            self.printCheck("FS page cache writeback", false);
            return false;
        };
        const payload = "perfdiag-writeback-v119";
        const written = self.sys.fileWrite("C:\\TEMP\\PERFWB.TXT", payload);
        var verify: [64]u8 = undefined;
        const read = self.sys.fileReadAt("C:\\TEMP\\PERFWB.TXT", 0, verify[0..]);
        const after = self.dev.performanceSummary() orelse {
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
        const before = self.dev.performanceSummary() orelse {
            self.printCheck("Global reclaim probe", false);
            return false;
        };
        const probe = self.dev.memoryReclaimProbe(1) orelse {
            self.printCheck("Global reclaim probe", false);
            return false;
        };
        const after = self.dev.performanceSummary() orelse {
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
            after.global_reclaim_last_returned_frames == probe.returned_frames and
            after.fs_cache_pmm_reclaimable_bytes + probe.returned_bytes <= before.fs_cache_pmm_reclaimable_bytes;
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

        const before_cleanup = self.dev.performanceSummary() orelse {
            self.printCheck("Backing slots lifecycle counters", false);
            return false;
        };
        if (self.sys.vmRelease(region.id) != r4os.abi.vm_ok) {
            self.printCheck("Backing slots lifecycle VM release", false);
            return false;
        }
        region_release_needed = false;
        const after_cleanup = self.dev.performanceSummary() orelse {
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

        const perf = self.dev.performanceSummary() orelse {
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
        const before_error_policy = self.dev.performanceSummary() orelse {
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
        const after_error_policy = self.dev.performanceSummary() orelse {
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

        const before_page_out_summary = self.dev.performanceSummary() orelse {
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
        const after_page_out_summary = self.dev.performanceSummary() orelse {
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

        const before_fault = self.dev.performanceSummary() orelse {
            self.printCheck("VM page state fault page in", false);
            return false;
        };
        const fault_byte0 = ptr[0];
        const fault_byte1 = ptr[4096 + 17];
        const after_fault = self.dev.memoryVmPageStateProbe(region.id, 0, state_pages, r4os.abi.memory_vm_page_state_operation_query, 0, 0, 0, 0) orelse {
            self.printCheck("VM page state fault page in", false);
            return false;
        };
        const after_fault_summary = self.dev.performanceSummary() orelse {
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

        const before_cleanup = self.dev.performanceSummary() orelse {
            self.printCheck("VM page state cleanup", false);
            return false;
        };
        if (self.sys.vmRelease(region.id) != r4os.abi.vm_ok) {
            self.printCheck("VM page state cleanup", false);
            return false;
        }
        region_release_needed = false;
        slot_release_needed = false;
        const after_cleanup = self.dev.performanceSummary() orelse {
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
        const before = self.dev.performanceSummary() orelse {
            self.printCheck("VM eviction baseline", false);
            return false;
        };

        const frame_bytes: u64 = if (before.fs_cache_payload_frame_bytes == 0) 4096 else before.fs_cache_payload_frame_bytes;

        var probe: ?r4os.abi.ProgramMemoryReclaimProbe = null;
        var attempts: u32 = 0;
        while (attempts < 8) : (attempts += 1) {
            const current_perf = self.dev.performanceSummary() orelse {
                self.printCheck("VM eviction reclaim", false);
                return false;
            };
            const fs_frames = (current_perf.fs_cache_pmm_reclaimable_bytes / frame_bytes) + 1;
            var requested_frames: u32 = if (fs_frames > 1024) 1024 else @intCast(fs_frames);
            if (requested_frames == 0) requested_frames = 1;
            const current = self.dev.memoryReclaimProbe(requested_frames) orelse {
                self.printCheck("VM eviction reclaim", false);
                return false;
            };
            probe = current;
            if (current.vm_returned_frames > 0 and current.vm_page_outs > 0) break;
            requested_frames = 1;
        }
        const final_probe = probe orelse {
            self.printCheck("VM eviction reclaim", false);
            return false;
        };

        const after_reclaim = self.dev.performanceSummary() orelse {
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

        const before_fault = self.dev.performanceSummary() orelse {
            self.printCheck("VM eviction fault baseline", false);
            return false;
        };
        const fault_index: usize = @intCast(evicted_page * 4096 + 17);
        const fault_byte = if (evicted_page < evict_pages) ptr[fault_index] else 0;
        const after_fault_state = self.dev.memoryVmPageStateProbe(region.id, 0, evict_pages, r4os.abi.memory_vm_page_state_operation_query, 0, 0, 0, 0) orelse {
            self.printCheck("VM eviction fault state", false);
            return false;
        };
        const after_fault = self.dev.performanceSummary() orelse {
            self.printCheck("VM eviction fault summary", false);
            return false;
        };

        const expected_byte: u8 = @truncate(fault_index *% 11 +% 0x33);
        const ok = before_state.status == r4os.abi.memory_vm_page_state_status_ready and
            before_state.resident_pages >= evict_pages and
            before_state.pinned_pages == 1 and
            final_probe.version == r4os.abi.memory_reclaim_probe_version and
            final_probe.size >= @sizeOf(r4os.abi.ProgramMemoryReclaimProbe) and
            final_probe.vm_returned_frames > 0 and
            final_probe.vm_page_outs > 0 and
            after_reclaim.global_reclaim_vm_returned_frames >= before.global_reclaim_vm_returned_frames + final_probe.vm_returned_frames and
            after_reclaim.global_reclaim_vm_page_outs >= before.global_reclaim_vm_page_outs + final_probe.vm_page_outs and
            after_reclaim.memory_vm_eviction_success_count > before.memory_vm_eviction_success_count and
            after_reclaim.memory_vm_eviction_returned_frames >= before.memory_vm_eviction_returned_frames + final_probe.vm_returned_frames and
            after_state.status == r4os.abi.memory_vm_page_state_status_ready and
            after_state.pinned_pages == 1 and
            after_state.nonresident_pages > 0 and
            after_state.slot_bound_pages > 0 and
            evicted_page < evict_pages and
            fault_byte == expected_byte and
            after_fault_state.resident_pages >= after_state.resident_pages + 1 and
            after_fault.memory_vm_page_state_fault_page_in_count > before_fault.memory_vm_page_state_fault_page_in_count and
            after_fault.memory_page_io_status == r4os.abi.memory_page_io_status_page_in_ok and
            after_fault.memory_page_io_eviction_enabled == 1;
        self.printCheck("VM eviction reclaim", ok);
        self.sys.write("  VM eviction: fs=");
        self.sys.printU64(final_probe.fs_returned_frames);
        self.sys.write(" vm=");
        self.sys.printU64(final_probe.vm_returned_frames);
        self.sys.write(" pageOut=");
        self.sys.printU64(final_probe.vm_page_outs);
        self.sys.write(" page=");
        self.sys.printU64(evicted_page);
        self.sys.write(" faultIn=");
        self.sys.printU64(after_fault.memory_vm_page_state_fault_page_in_count);
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

fn delta(after: u64, before: u64) u64 {
    return if (after >= before) after - before else 0;
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
