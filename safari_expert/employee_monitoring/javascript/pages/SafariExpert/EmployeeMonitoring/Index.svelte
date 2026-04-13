<script lang="ts">
  import { Link } from "@inertiajs/svelte";
  import { onMount } from "svelte";
  import Button from "../../../../../../app/javascript/components/Button.svelte";

  type Summary = {
    monitored_users: number;
    active_in_window: number;
    idle_in_window: number;
    not_started_yet: number;
    ended_early: number;
    after_hours_active: number;
  };

  type RosterRow = {
    id: number;
    display_name: string;
    username: string | null;
    avatar_url: string | null;
    timezone: string;
    local_date: string;
    expected_start_at: string | null;
    expected_end_at: string | null;
    schedule_label: string;
    first_seen_at: string | null;
    last_seen_at: string | null;
    start_delta_minutes: number | null;
    end_delta_minutes: number | null;
    status: string;
    not_started_yet: boolean;
    ended_early: boolean;
    after_hours_active: boolean;
    presence_seconds: number;
    coding_seconds: number;
    write_heartbeats_count: number;
    unique_files_count: number;
    unique_projects_count: number;
    unique_languages_count: number;
    session_count: number;
    gap_count: number;
    coverage_percent: number;
    commit_count: number;
    commit_line_additions: number;
    commit_line_deletions: number;
    top_project?: string | null;
    top_language?: string | null;
    top_editor?: string | null;
    attendance_signal: string;
    activity_signal: string;
    delivery_signal: string;
    ai_assisted_output_level: string;
    ai_assisted_output_ratio: number;
    ai_assisted_output_confidence: number;
    ai_assisted_output_reason?: string | null;
    selection_path: string;
  };

  type LanguageBreakdownRow = {
    language: string;
    coding_seconds: number;
    line_additions: number;
    line_deletions: number;
  };

  type TimelineBucket = {
    bucket_started_at: string;
    status: string;
    in_window: boolean;
    presence_seconds: number;
    coding_seconds: number;
    write_heartbeats_count: number;
    line_additions: number;
    line_deletions: number;
    categories: Record<string, number>;
    projects: string[];
    languages: string[];
    language_breakdown: LanguageBreakdownRow[];
  };

  type SessionSpan = {
    start_at: string;
    end_at: string;
    duration_seconds: number;
    files: string[];
    projects: string[];
    languages: string[];
    editors: string[];
  };

  type MixRow = {
    name: string;
    seconds: number;
  };

  type CommitMarker = {
    sha: string;
    timestamp: string;
    additions: number;
    deletions: number;
    github_url?: string | null;
  };

  type Trend = {
    days_sampled: number;
    on_time_days: number;
    late_start_days: number;
    absent_days: number;
    ended_early_days: number;
    average_coverage: number;
    coding_hours: number;
  };

  type HistoryRow = {
    local_date: string;
    attendance_signal: string;
    coverage_percent: number;
    coding_seconds: number;
    commit_count: number;
    after_hours_active: boolean;
  };

  type SelectedUser = {
    id: number;
    display_name: string;
    username: string | null;
    avatar_url: string | null;
    schedule: {
      monitoring_enabled: boolean;
      timezone_override: string | null;
      effective_timezone: string;
      expected_start_minute_local: number;
      expected_end_minute_local: number;
      workdays: number[];
      start_grace_minutes: number;
      end_grace_minutes: number;
      label: string;
      update_path: string;
    };
    current_day: RosterRow & {
      timeline_buckets: TimelineBucket[];
      session_spans: SessionSpan[];
      project_mix: MixRow[];
      language_mix: MixRow[];
      editor_mix: MixRow[];
      commit_markers: CommitMarker[];
    };
    trend_14d: Trend;
    trend_30d: Trend;
    history: HistoryRow[];
  };

  let {
    page_title,
    overview,
    selected_user,
    can_edit_schedule,
    page_path,
  }: {
    page_title: string;
    overview: {
      generated_at: string;
      timezone: string;
      summary: Summary;
      filters: {
        search: string;
        status: string;
      };
      roster: RosterRow[];
    };
    selected_user: SelectedUser | null;
    can_edit_schedule: boolean;
    page_path: string;
  } = $props();

  const dayOptions = [
    { value: 1, label: "Mon" },
    { value: 2, label: "Tue" },
    { value: 3, label: "Wed" },
    { value: 4, label: "Thu" },
    { value: 5, label: "Fri" },
    { value: 6, label: "Sat" },
    { value: 0, label: "Sun" },
  ];

  type ActivityChartSeries = {
    key: string;
    label: string;
    color: string;
  };
  type ActivityChartSegment = ActivityChartSeries & {
    value: number;
  };
  type ActivityChartBucket = {
    bucket: TimelineBucket;
    total: number;
    segments: ActivityChartSegment[];
    tick_label: string;
  };
  type ActivitySummaryStat = {
    label: string;
    value: string;
    detail: string;
  };
  type FocusedActivityBucket = {
    bucket: TimelineBucket;
    churn: ActivityChartBucket;
    languages: ActivityChartBucket;
  };

  const LANGUAGE_COLORS = [
    "#60a5fa",
    "#f472b6",
    "#fb923c",
    "#facc15",
    "#4ade80",
    "#2dd4bf",
    "#a78bfa",
    "#38bdf8",
    "#e879f9",
    "#34d399",
  ];
  const CHURN_SERIES: ActivityChartSeries[] = [
    { key: "line_additions", label: "Additions", color: "#4ade80" },
    { key: "line_deletions", label: "Deletions", color: "#f87171" },
  ];
  const PRESENCE_SERIES = [
    { label: "Active", className: "chart-legend__swatch--active" },
    { label: "Idle", className: "chart-legend__swatch--idle" },
    { label: "Before start", className: "chart-legend__swatch--before" },
    { label: "After end", className: "chart-legend__swatch--after" },
    { label: "Inactive", className: "chart-legend__swatch--inactive" },
  ];

  let csrfToken = $state("");
  let activeBucketStartedAt = $state<string | null>(null);

  onMount(() => {
    csrfToken =
      document
        .querySelector("meta[name='csrf-token']")
        ?.getAttribute("content") || "";
  });

  function formatDateTime(value: string | null) {
    if (!value) return "Not seen";

    return new Intl.DateTimeFormat("en-GB", {
      dateStyle: "medium",
      timeStyle: "short",
    }).format(new Date(value));
  }

  function formatShortDate(value: string) {
    return new Intl.DateTimeFormat("en-GB", {
      month: "short",
      day: "numeric",
    }).format(new Date(value));
  }

  function formatShortTime(value: string) {
    return new Intl.DateTimeFormat("en-GB", {
      hour: "2-digit",
      minute: "2-digit",
    }).format(new Date(value));
  }

  function formatDuration(totalSeconds: number) {
    if (totalSeconds <= 0) return "0m";

    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);

    if (hours === 0) return `${minutes}m`;
    if (minutes === 0) return `${hours}h`;
    return `${hours}h ${minutes}m`;
  }

  function formatLineAxis(value: number) {
    if (value === 0) return "0";
    if (value >= 1000) return `${(value / 1000).toFixed(1)}k`;
    return `${Math.round(value)}`;
  }

  function formatPercent(value: number) {
    return `${Math.round(value)}%`;
  }

  function formatDelta(value: number | null, positiveLabel = "late") {
    if (value === null) return "No check-in";
    if (value === 0) return "On time";
    if (value > 0) return `+${value}m ${positiveLabel}`;
    return `${value}m early`;
  }

  function humanizeStatus(value: string) {
    return value.replaceAll("_", " ");
  }

  function formatMinuteOfDay(totalMinutes: number) {
    const hours = Math.floor(totalMinutes / 60);
    const minutes = totalMinutes % 60;
    return `${hours.toString().padStart(2, "0")}:${minutes.toString().padStart(2, "0")}`;
  }

  function statusTone(status: string, afterHours = false) {
    if (afterHours) return "badge badge--after-hours";

    switch (status) {
      case "active":
        return "badge badge--active";
      case "idle":
        return "badge badge--idle";
      case "before_start":
        return "badge badge--before";
      case "after_end":
        return "badge badge--after";
      default:
        return "badge badge--inactive";
    }
  }

  function signalTone(value: string) {
    if (value.includes("high") || value.includes("strong") || value.includes("completed") || value.includes("on_track")) {
      return "badge badge--good";
    }

    if (value.includes("late") || value.includes("ended_early")) {
      return "badge badge--warn";
    }

    if (value.includes("not_started") || value.includes("quiet")) {
      return "badge badge--critical";
    }

    return "badge badge--neutral";
  }

  function aiTone(value: string) {
    switch (value) {
      case "high":
        return "badge badge--critical";
      case "moderate":
        return "badge badge--warn";
      case "low":
        return "badge badge--neutral";
      default:
        return "badge badge--after";
    }
  }

  function statusRailTone(bucket: TimelineBucket) {
    if (bucket.status === "active") return "status-rail__segment status-rail__segment--active";
    if (bucket.status === "idle") return "status-rail__segment status-rail__segment--idle";
    if (bucket.status === "after_end") return "status-rail__segment status-rail__segment--after";
    if (bucket.status === "before_start") return "status-rail__segment status-rail__segment--before";
    return "status-rail__segment status-rail__segment--inactive";
  }

  function shouldShowBucketTick(bucket: TimelineBucket, index: number, buckets: TimelineBucket[]) {
    if (buckets.length <= 18) return true;

    const bucketDate = new Date(bucket.bucket_started_at);
    return index === 0 || index === buckets.length - 1 || bucketDate.getMinutes() === 0;
  }

  function chartScaleMax(mode: "churn" | "languages", maxValue: number) {
    if (maxValue <= 0) return mode === "churn" ? 10 : 300;

    if (mode === "churn") {
      const step = maxValue <= 20 ? 5 : maxValue <= 100 ? 10 : maxValue <= 250 ? 25 : 50;
      return Math.ceil((maxValue * 1.1) / step) * step;
    }

    const step = maxValue <= 900 ? 300 : maxValue <= 3600 ? 900 : 1800;
    return Math.ceil((maxValue * 1.1) / step) * step;
  }

  function buildTickValues(maxValue: number) {
    const values = [maxValue, Math.round((maxValue * 2) / 3), Math.round(maxValue / 3), 0];
    return values.filter((value, index) => values.indexOf(value) === index);
  }

  function chartAxisFormat(mode: "churn" | "languages", value: number) {
    return mode === "churn" ? formatLineAxis(value) : formatDuration(value);
  }

  function buildBucketTitle(chartBucket: ActivityChartBucket, mode: "churn" | "languages") {
    const lines = [
      `${formatDateTime(chartBucket.bucket.bucket_started_at)} · ${humanizeStatus(chartBucket.bucket.status)}`,
    ];

    if (mode === "churn") {
      lines.push(`Additions: ${chartBucket.bucket.line_additions}`);
      lines.push(`Deletions: ${chartBucket.bucket.line_deletions}`);
      lines.push(`Coding: ${formatDuration(chartBucket.bucket.coding_seconds)}`);
      lines.push(`Writes: ${chartBucket.bucket.write_heartbeats_count}`);
    } else {
      lines.push(`Coding: ${formatDuration(chartBucket.bucket.coding_seconds)}`);
      lines.push(`Languages: ${chartBucket.segments.length}`);

      for (const segment of chartBucket.segments) {
        if (segment.value <= 0) continue;
        lines.push(`${segment.label}: ${formatDuration(segment.value)}`);
      }
    }

    return lines.join("\n");
  }

  function bucketHasVisibleActivity(bucket: TimelineBucket) {
    return bucket.presence_seconds > 0 ||
      bucket.coding_seconds > 0 ||
      bucket.line_additions > 0 ||
      bucket.line_deletions > 0;
  }

  function defaultTimelineBucket(buckets: TimelineBucket[]) {
    for (let index = buckets.length - 1; index >= 0; index -= 1) {
      if (bucketHasVisibleActivity(buckets[index])) return buckets[index];
    }

    return buckets[buckets.length - 1] || null;
  }

  const timelineBuckets = $derived.by(() => selected_user?.current_day.timeline_buckets || []);

  const topLanguageKeys = $derived.by(() => {
    const totals = new Map<string, number>();

    for (const bucket of timelineBuckets) {
      for (const stat of bucket.language_breakdown) {
        if (stat.coding_seconds <= 0) continue;
        totals.set(stat.language, (totals.get(stat.language) || 0) + stat.coding_seconds);
      }
    }

    return Array.from(totals.entries())
      .sort((left, right) => {
        if (right[1] !== left[1]) return right[1] - left[1];
        return left[0].localeCompare(right[0]);
      })
      .slice(0, 5)
      .map(([language]) => language);
  });

  const hasOtherLanguages = $derived.by(() => {
    const topLanguages = new Set(topLanguageKeys);

    for (const bucket of timelineBuckets) {
      for (const stat of bucket.language_breakdown) {
        if (stat.coding_seconds <= 0) continue;
        if (!topLanguages.has(stat.language)) return true;
      }
    }

    return false;
  });

  const languageSeries = $derived.by<ActivityChartSeries[]>(() => {
    const baseSeries = topLanguageKeys.map((language, index) => ({
      key: language,
      label: language,
      color: LANGUAGE_COLORS[index % LANGUAGE_COLORS.length],
    }));

    if (hasOtherLanguages) {
      baseSeries.push({
        key: "Other",
        label: "Other",
        color: "#94a3b8",
      });
    }

    return baseSeries;
  });

  const churnChartBuckets = $derived.by<ActivityChartBucket[]>(() => (
    timelineBuckets.map((bucket, index) => ({
      bucket,
      total: bucket.line_additions + bucket.line_deletions,
      segments: CHURN_SERIES.map((series) => ({
        ...series,
        value: series.key === "line_additions" ? bucket.line_additions : bucket.line_deletions,
      })).filter((segment) => segment.value > 0),
      tick_label: shouldShowBucketTick(bucket, index, timelineBuckets)
        ? formatShortTime(bucket.bucket_started_at)
        : "",
    }))
  ));

  const languageChartBuckets = $derived.by<ActivityChartBucket[]>(() => {
    const topLanguages = new Set(topLanguageKeys);

    return timelineBuckets.map((bucket, index) => {
      const segments: ActivityChartSegment[] = topLanguageKeys.map((language, languageIndex) => ({
        key: language,
        label: language,
        color: LANGUAGE_COLORS[languageIndex % LANGUAGE_COLORS.length],
        value: 0,
      }));
      let otherSeconds = 0;

      for (const stat of bucket.language_breakdown) {
        if (stat.coding_seconds <= 0) continue;

        if (topLanguages.has(stat.language)) {
          const segment = segments.find((entry) => entry.key === stat.language);
          if (segment) segment.value = stat.coding_seconds;
        } else {
          otherSeconds += stat.coding_seconds;
        }
      }

      if (hasOtherLanguages) {
        segments.push({
          key: "Other",
          label: "Other",
          color: "#94a3b8",
          value: otherSeconds,
        });
      }

      const visibleSegments = segments.filter((segment) => segment.value > 0);

      return {
        bucket,
        total: bucket.coding_seconds,
        segments: visibleSegments,
        tick_label: shouldShowBucketTick(bucket, index, timelineBuckets)
          ? formatShortTime(bucket.bucket_started_at)
          : "",
      };
    });
  });

  const churnScaleMax = $derived.by(() => (
    chartScaleMax("churn", Math.max(0, ...churnChartBuckets.map((bucket) => bucket.total)))
  ));

  const languageScaleMax = $derived.by(() => (
    chartScaleMax("languages", Math.max(0, ...languageChartBuckets.map((bucket) => bucket.total)))
  ));

  const activeTimelineIndex = $derived.by(() => {
    if (timelineBuckets.length === 0) return -1;
    if (activeBucketStartedAt) {
      const hoveredIndex = timelineBuckets.findIndex((bucket) => (
        bucket.bucket_started_at === activeBucketStartedAt
      ));
      if (hoveredIndex >= 0) return hoveredIndex;
    }

    const fallbackBucket = defaultTimelineBucket(timelineBuckets);
    if (!fallbackBucket) return -1;

    return timelineBuckets.findIndex((bucket) => (
      bucket.bucket_started_at === fallbackBucket.bucket_started_at
    ));
  });

  const activeTimelineBucket = $derived.by<FocusedActivityBucket | null>(() => {
    if (activeTimelineIndex < 0) return null;

    return {
      bucket: timelineBuckets[activeTimelineIndex],
      churn: churnChartBuckets[activeTimelineIndex],
      languages: languageChartBuckets[activeTimelineIndex],
    };
  });

  const hasChurnData = $derived.by(() => churnChartBuckets.some((bucket) => bucket.total > 0));

  const hasLanguageData = $derived.by(() => languageChartBuckets.some((bucket) => bucket.total > 0));

  const bucketCount = $derived.by(() => Math.max(timelineBuckets.length, 1));

  const bucketColumnWidth = $derived.by(() => {
    if (timelineBuckets.length >= 144) return "0.72rem";
    if (timelineBuckets.length >= 120) return "0.8rem";
    if (timelineBuckets.length >= 96) return "0.9rem";
    if (timelineBuckets.length >= 72) return "0.98rem";
    return "1.08rem";
  });

  const axisTickLabels = $derived.by(() => (
    timelineBuckets.map((bucket, index) => ({
      bucket_started_at: bucket.bucket_started_at,
      label: shouldShowBucketTick(bucket, index, timelineBuckets) ? formatShortTime(bucket.bucket_started_at) : "",
    }))
  ));

  const activityChartSummaryStats = $derived.by<ActivitySummaryStat[]>(() => {
    const totalAdditions = timelineBuckets.reduce((sum, bucket) => sum + bucket.line_additions, 0);
    const totalDeletions = timelineBuckets.reduce((sum, bucket) => sum + bucket.line_deletions, 0);
    const bucketsWithChurn = churnChartBuckets.filter((bucket) => bucket.total > 0).length;
    const bucketsWithPresence = timelineBuckets.filter((bucket) => bucket.presence_seconds > 0).length;
    const activeLanguages = new Set<string>();

    for (const bucket of timelineBuckets) {
      for (const stat of bucket.language_breakdown) {
        activeLanguages.add(stat.language);
      }
    }

    const bucketsWithCoding = languageChartBuckets.filter((bucket) => bucket.total > 0).length;

    return [
      {
        label: "Total coding",
        value: formatDuration(selected_user?.current_day.coding_seconds || 0),
        detail: `${bucketsWithCoding}/${timelineBuckets.length} buckets with language-attributed coding`,
      },
      {
        label: "Language mix",
        value: `${activeLanguages.size}`,
        detail: activeLanguages.size === 0
          ? "No language-attributed coding yet"
          : `${Math.min(topLanguageKeys.length, activeLanguages.size)} highlighted + ${hasOtherLanguages ? "Other grouped" : "no overflow group"}`,
      },
      {
        label: "Line churn",
        value: `+${totalAdditions} / -${totalDeletions}`,
        detail: `${bucketsWithChurn}/${timelineBuckets.length} buckets with additions or deletions`,
      },
      {
        label: "Presence",
        value: `${bucketsWithPresence}/${timelineBuckets.length}`,
        detail: "Buckets with any recorded presence across the selected day",
      },
    ];
  });
</script>

<svelte:head>
  <title>{page_title}</title>
</svelte:head>

<div class="monitoring-shell">
  <div class="mb-6 grid gap-3">
    <p class="m-0 text-sm uppercase tracking-[0.24em] text-muted">
      Safari Expert Monitoring
    </p>
    <div class="flex flex-wrap items-end justify-between gap-3">
      <div class="grid gap-2">
        <h1 class="m-0 text-3xl font-bold text-surface-content md:text-4xl">
          Employee Monitoring
        </h1>
        <p class="m-0 max-w-3xl text-base text-muted">
          Review attendance, coding activity, delivery signals, and the
          experimental AI-assisted output heuristic on one page. This surface is
          tuned for shift adherence and output monitoring, not generic
          time-tracking.
        </p>
      </div>
      <div class="rounded-xl border border-surface-200 bg-dark px-4 py-3 text-sm text-muted">
        <div>Generated: {formatDateTime(overview.generated_at)}</div>
        <div>Server timezone: {overview.timezone}</div>
      </div>
    </div>
  </div>

  <form method="GET" action={page_path} class="mb-6 grid gap-3 rounded-2xl border border-surface-200 bg-dark p-4 lg:grid-cols-[1.6fr_220px_auto]">
    {#if selected_user}
      <input type="hidden" name="user_id" value={selected_user.id} />
    {/if}
    <label class="grid gap-2 text-sm text-muted">
      <span>Search developers</span>
      <input
        class="rounded-xl border border-surface-200 bg-surface px-3 py-2 text-surface-content"
        type="search"
        name="search"
        value={overview.filters.search}
        placeholder="Search by username, GitHub, email, or id"
      />
    </label>
    <label class="grid gap-2 text-sm text-muted">
      <span>Status focus</span>
      <select
        class="rounded-xl border border-surface-200 bg-surface px-3 py-2 text-surface-content"
        name="status"
      >
        <option value="" selected={overview.filters.status === ""}>All statuses</option>
        <option value="active" selected={overview.filters.status === "active"}>Active in window</option>
        <option value="idle" selected={overview.filters.status === "idle"}>Idle in window</option>
        <option value="inactive" selected={overview.filters.status === "inactive"}>Inactive</option>
        <option value="before_start" selected={overview.filters.status === "before_start"}>Before start</option>
        <option value="after_end" selected={overview.filters.status === "after_end"}>After end</option>
        <option value="not_started_yet" selected={overview.filters.status === "not_started_yet"}>Not started yet</option>
        <option value="ended_early" selected={overview.filters.status === "ended_early"}>Ended early</option>
        <option value="after_hours" selected={overview.filters.status === "after_hours"}>After-hours active</option>
      </select>
    </label>
    <div class="flex items-end">
      <Button type="submit" variant="primary" class="w-full rounded-xl">
        Apply filters
      </Button>
    </div>
  </form>

  <section class="mb-6 grid gap-4 md:grid-cols-3 xl:grid-cols-6">
    {#each [
      { label: "Monitored users", value: overview.summary.monitored_users, tone: "summary-card" },
      { label: "Active in window", value: overview.summary.active_in_window, tone: "summary-card summary-card--active" },
      { label: "Idle in window", value: overview.summary.idle_in_window, tone: "summary-card summary-card--idle" },
      { label: "Not started", value: overview.summary.not_started_yet, tone: "summary-card summary-card--warn" },
      { label: "Ended early", value: overview.summary.ended_early, tone: "summary-card summary-card--critical" },
      { label: "After-hours active", value: overview.summary.after_hours_active, tone: "summary-card summary-card--after" },
    ] as card}
      <div class={card.tone}>
        <p class="m-0 text-xs uppercase tracking-[0.22em] text-muted">{card.label}</p>
        <p class="mt-3 text-3xl font-bold text-surface-content">{card.value}</p>
      </div>
    {/each}
  </section>

  <div class="monitoring-grid">
    <section class="rounded-2xl border border-surface-200 bg-dark p-4">
      <div class="mb-4 flex items-center justify-between gap-3">
        <div>
          <h2 class="m-0 text-xl font-semibold text-surface-content">Roster</h2>
          <p class="m-1 text-sm text-muted">
            Attendance, activity, and delivery are surfaced separately. No
            single productivity score is computed.
          </p>
        </div>
        <div class="text-xs uppercase tracking-[0.22em] text-muted">
          {overview.roster.length} visible
        </div>
      </div>

      {#if overview.roster.length === 0}
        <div class="rounded-2xl border border-surface-200 bg-surface p-8 text-center text-muted">
          No monitored developers match the current filters.
        </div>
      {:else}
        <div class="overflow-x-auto">
          <table class="min-w-full monitoring-table">
            <thead>
              <tr>
                <th>Developer</th>
                <th>Status</th>
                <th>Attendance</th>
                <th>Coverage</th>
                <th>Output</th>
                <th>Signals</th>
              </tr>
            </thead>
            <tbody>
              {#each overview.roster as row}
                <tr class:selected={selected_user?.id === row.id}>
                  <td>
                    <Link href={row.selection_path} class="row-link">
                      <div class="grid gap-1">
                        <span class="font-semibold text-surface-content">{row.display_name}</span>
                        <span class="text-xs text-muted">
                          {row.username ? `@${row.username}` : `User ${row.id}`}
                        </span>
                        <span class="text-xs text-muted">{row.schedule_label}</span>
                      </div>
                    </Link>
                  </td>
                  <td>
                    <div class="grid gap-2">
                      <span class={statusTone(row.status, row.after_hours_active)}>
                        {row.after_hours_active ? "after hours" : row.status.replaceAll("_", " ")}
                      </span>
                      <span class="text-xs text-muted">
                        Last seen {formatDateTime(row.last_seen_at)}
                      </span>
                    </div>
                  </td>
                  <td>
                    <div class="grid gap-1 text-sm text-surface-content">
                      <span>Start: {formatDelta(row.start_delta_minutes)}</span>
                      <span>End: {formatDelta(row.end_delta_minutes, "over")}</span>
                      <span class="text-xs text-muted">
                        First seen {formatDateTime(row.first_seen_at)}
                      </span>
                    </div>
                  </td>
                  <td>
                    <div class="grid gap-1 text-sm text-surface-content">
                      <span>{formatPercent(row.coverage_percent)}</span>
                      <span>{formatDuration(row.coding_seconds)} coding</span>
                      <span class="text-xs text-muted">
                        {row.gap_count} long gaps · {row.session_count} sessions
                      </span>
                    </div>
                  </td>
                  <td>
                    <div class="grid gap-1 text-sm text-surface-content">
                      <span>{row.write_heartbeats_count} writes · {row.commit_count} commits</span>
                      <span>
                        +{row.commit_line_additions} / -{row.commit_line_deletions}
                      </span>
                      <span class="text-xs text-muted">
                        {row.unique_projects_count} projects · {row.unique_languages_count} langs
                      </span>
                    </div>
                  </td>
                  <td>
                    <div class="grid gap-2">
                      <span class={signalTone(row.attendance_signal)}>
                        {row.attendance_signal.replaceAll("_", " ")}
                      </span>
                      <span class={signalTone(row.activity_signal)}>
                        activity {row.activity_signal}
                      </span>
                      <span class={signalTone(row.delivery_signal)}>
                        delivery {row.delivery_signal}
                      </span>
                      <span class={aiTone(row.ai_assisted_output_level)}>
                        AI {row.ai_assisted_output_level}
                      </span>
                    </div>
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}
    </section>

    <section class="rounded-2xl border border-surface-200 bg-dark p-4">
      {#if selected_user}
        <div class="grid gap-5">
          <div class="grid gap-2">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <div>
                <p class="m-0 text-xs uppercase tracking-[0.22em] text-muted">
                  Selected developer
                </p>
                <h2 class="m-0 text-2xl font-semibold text-surface-content">
                  {selected_user.display_name}
                </h2>
                <p class="m-0 text-sm text-muted">
                  {selected_user.username ? `@${selected_user.username}` : `User ${selected_user.id}`}
                  {" · "}
                  {selected_user.schedule.label}
                </p>
              </div>
              <span class={statusTone(selected_user.current_day.status, selected_user.current_day.after_hours_active)}>
                {selected_user.current_day.after_hours_active
                  ? "after-hours active"
                  : selected_user.current_day.status.replaceAll("_", " ")}
              </span>
            </div>

            <div class="grid gap-3 md:grid-cols-3">
              <div class="metric-card">
                <p class="metric-card__label">Attendance</p>
                <p class="metric-card__value">
                  {selected_user.current_day.attendance_signal.replaceAll("_", " ")}
                </p>
                <p class="metric-card__hint">
                  Start {formatDelta(selected_user.current_day.start_delta_minutes)}
                </p>
              </div>
              <div class="metric-card">
                <p class="metric-card__label">Activity</p>
                <p class="metric-card__value">
                  {selected_user.current_day.activity_signal}
                </p>
                <p class="metric-card__hint">
                  {formatDuration(selected_user.current_day.coding_seconds)} coding · {formatPercent(selected_user.current_day.coverage_percent)} coverage
                </p>
              </div>
              <div class="metric-card">
                <p class="metric-card__label">Delivery</p>
                <p class="metric-card__value">
                  {selected_user.current_day.delivery_signal}
                </p>
                <p class="metric-card__hint">
                  {selected_user.current_day.commit_count} commits · {selected_user.current_day.write_heartbeats_count} writes
                </p>
              </div>
            </div>
          </div>

          <div class="rounded-2xl border border-surface-200 bg-surface p-4">
            <div class="activity-chart__meta">
              <div class="activity-chart__intro">
                <h3 class="m-0 text-lg font-semibold text-surface-content">
                  5-minute activity chart
                </h3>
                <p class="m-0 text-sm text-muted">
                  One shared bucket ladder drives all three panes. Languages stay in the
                  primary panel, raw additions and deletions live underneath as a subchart,
                  and presence status sits on the same communal time axis at the bottom.
                </p>
              </div>

              {#if activeTimelineBucket}
                <div class="activity-chart__focus-card">
                  <p class="activity-chart__focus-label">Focused bucket</p>
                  <strong class="text-surface-content">
                    {formatDateTime(activeTimelineBucket.bucket.bucket_started_at)}
                  </strong>
                  <p class="m-0 text-sm text-muted">
                    {humanizeStatus(activeTimelineBucket.bucket.status)} · {formatDuration(activeTimelineBucket.bucket.presence_seconds)} presence
                  </p>
                  <div class="activity-chart__focus-grid">
                    <span>{formatDuration(activeTimelineBucket.bucket.coding_seconds)} coding</span>
                    <span>+{activeTimelineBucket.bucket.line_additions} adds</span>
                    <span>-{activeTimelineBucket.bucket.line_deletions} deletes</span>
                    <span>{activeTimelineBucket.bucket.write_heartbeats_count} writes</span>
                  </div>
                  {#if activeTimelineBucket.languages.segments.length > 0}
                    <div class="activity-chart__focus-grid activity-chart__focus-grid--compact">
                      {#each activeTimelineBucket.languages.segments.slice(0, 3) as segment}
                        <span>{segment.label}: {formatDuration(segment.value)}</span>
                      {/each}
                    </div>
                  {/if}
                </div>
              {/if}
            </div>

            <div class="mb-4 mt-4 grid gap-3 md:grid-cols-2 xl:grid-cols-4">
              {#each activityChartSummaryStats as stat}
                <div class="activity-chart__summary-card">
                  <p class="activity-chart__summary-label">{stat.label}</p>
                  <p class="activity-chart__summary-value">{stat.value}</p>
                  <p class="activity-chart__summary-detail">{stat.detail}</p>
                </div>
              {/each}
            </div>

            <div class="activity-chart__legend-groups">
              <div class="activity-chart__legend-block">
                <p class="activity-chart__eyebrow">Languages</p>
                <div class="chart-legend">
                  {#if languageSeries.length === 0}
                    <span class="text-xs text-muted">No language stacks yet.</span>
                  {:else}
                    {#each languageSeries as series}
                      <span class="chart-legend__item">
                        <span
                          class="chart-legend__swatch"
                          style:background-color={series.color}
                        ></span>
                        <span>{series.label}</span>
                      </span>
                    {/each}
                  {/if}
                </div>
              </div>

              <div class="activity-chart__legend-block">
                <p class="activity-chart__eyebrow">Adds / Deletes</p>
                <div class="chart-legend">
                  {#each CHURN_SERIES as series}
                    <span class="chart-legend__item">
                      <span
                        class="chart-legend__swatch"
                        style:background-color={series.color}
                      ></span>
                      <span>{series.label}</span>
                    </span>
                  {/each}
                </div>
              </div>

              <div class="activity-chart__legend-block">
                <p class="activity-chart__eyebrow">Presence status</p>
                <div class="chart-legend">
                  {#each PRESENCE_SERIES as series}
                    <span class="chart-legend__item">
                      <span class={`chart-legend__swatch ${series.className}`}></span>
                      <span>{series.label}</span>
                    </span>
                  {/each}
                </div>
              </div>
            </div>

            {#if timelineBuckets.length === 0}
              <div class="activity-chart__empty-state">
                No 5-minute buckets are available for the selected day yet.
              </div>
            {:else}
              <div class="market-chart" data-bucket-count={bucketCount}>
                <div class="market-chart__frame">
                  <div class="market-chart__axes">
                    <div class="market-chart__axis-block">
                      <p class="market-chart__axis-title">Languages</p>
                      <p class="market-chart__axis-subtitle">Coding time by language per 5-minute bucket</p>
                      <div class="market-chart__y-axis">
                        {#each buildTickValues(languageScaleMax) as tick}
                          <span>{chartAxisFormat("languages", tick)}</span>
                        {/each}
                      </div>
                    </div>

                    <div class="market-chart__axis-block">
                      <p class="market-chart__axis-title">Adds / Deletes</p>
                      <p class="market-chart__axis-subtitle">Line churn by 5-minute bucket</p>
                      <div class="market-chart__y-axis">
                        {#each buildTickValues(churnScaleMax) as tick}
                          <span>{chartAxisFormat("churn", tick)}</span>
                        {/each}
                      </div>
                    </div>

                    <div class="market-chart__axis-block market-chart__axis-block--status">
                      <p class="market-chart__axis-title">PRESENCE STATUS</p>
                      <p class="market-chart__axis-subtitle">Active &lt; 5m · idle &lt; 15m</p>
                    </div>

                    <div class="market-chart__axis-footer">
                      <span>5 min buckets</span>
                    </div>
                  </div>

                  <div class="market-chart__scroll">
                    <div
                      class="market-chart__timeline"
                      style={`--bucket-count: ${bucketCount}; --bucket-width: ${bucketColumnWidth};`}
                    >
                      <div class="market-chart__track market-chart__track--languages">
                        <div
                          class="market-chart__grid market-chart__grid--bars"
                          data-track="languages"
                          data-bucket-count={bucketCount}
                        >
                          {#each languageChartBuckets as chartBucket}
                            <div
                              class:market-chart__slot--active={activeTimelineBucket?.bucket.bucket_started_at === chartBucket.bucket.bucket_started_at}
                              class="market-chart__slot"
                            >
                              <Button
                                type="button"
                                unstyled
                                class={activeTimelineBucket?.bucket.bucket_started_at === chartBucket.bucket.bucket_started_at
                                  ? "market-chart__stack market-chart__stack--active"
                                  : "market-chart__stack"}
                                title={buildBucketTitle(chartBucket, "languages")}
                                aria-label={buildBucketTitle(chartBucket, "languages")}
                                onclick={() => (activeBucketStartedAt = chartBucket.bucket.bucket_started_at)}
                                onmouseenter={() => (activeBucketStartedAt = chartBucket.bucket.bucket_started_at)}
                                onfocus={() => (activeBucketStartedAt = chartBucket.bucket.bucket_started_at)}
                              >
                                {#if chartBucket.total > 0}
                                  {#each chartBucket.segments as segment}
                                    <span
                                      class="market-chart__segment"
                                      style:height={`${(segment.value / languageScaleMax) * 100}%`}
                                      style:background-color={segment.color}
                                    ></span>
                                  {/each}
                                {:else}
                                  <span class="market-chart__zero"></span>
                                {/if}
                              </Button>
                            </div>
                          {/each}
                        </div>
                        {#if !hasLanguageData}
                          <p class="market-chart__panel-note">
                            No language-attributed coding activity has been recorded for these buckets yet.
                          </p>
                        {/if}
                      </div>

                      <div class="market-chart__track market-chart__track--churn">
                        <div
                          class="market-chart__grid market-chart__grid--bars"
                          data-track="churn"
                          data-bucket-count={bucketCount}
                        >
                          {#each churnChartBuckets as chartBucket}
                            <div
                              class:market-chart__slot--active={activeTimelineBucket?.bucket.bucket_started_at === chartBucket.bucket.bucket_started_at}
                              class="market-chart__slot"
                            >
                              <Button
                                type="button"
                                unstyled
                                class={activeTimelineBucket?.bucket.bucket_started_at === chartBucket.bucket.bucket_started_at
                                  ? "market-chart__stack market-chart__stack--active"
                                  : "market-chart__stack"}
                                title={buildBucketTitle(chartBucket, "churn")}
                                aria-label={buildBucketTitle(chartBucket, "churn")}
                                onclick={() => (activeBucketStartedAt = chartBucket.bucket.bucket_started_at)}
                                onmouseenter={() => (activeBucketStartedAt = chartBucket.bucket.bucket_started_at)}
                                onfocus={() => (activeBucketStartedAt = chartBucket.bucket.bucket_started_at)}
                              >
                                {#if chartBucket.total > 0}
                                  {#each chartBucket.segments as segment}
                                    <span
                                      class="market-chart__segment"
                                      style:height={`${(segment.value / churnScaleMax) * 100}%`}
                                      style:background-color={segment.color}
                                    ></span>
                                  {/each}
                                {:else}
                                  <span class="market-chart__zero"></span>
                                {/if}
                              </Button>
                            </div>
                          {/each}
                        </div>
                        {#if !hasChurnData}
                          <p class="market-chart__panel-note">
                            No raw heartbeat additions or deletions have been recorded for these buckets yet.
                          </p>
                        {/if}
                      </div>

                      <div class="market-chart__track market-chart__track--status">
                        <div
                          class="market-chart__grid market-chart__grid--status status-rail"
                          data-track="status"
                          data-bucket-count={bucketCount}
                        >
                          {#each timelineBuckets as bucket}
                            <div
                              class:market-chart__slot--active={activeTimelineBucket?.bucket.bucket_started_at === bucket.bucket_started_at}
                              class="market-chart__slot"
                            >
                              <Button
                                type="button"
                                unstyled
                                class={activeTimelineBucket?.bucket.bucket_started_at === bucket.bucket_started_at
                                  ? "market-chart__status-button market-chart__status-button--active"
                                  : "market-chart__status-button"}
                                title={`${formatDateTime(bucket.bucket_started_at)} · ${humanizeStatus(bucket.status)}\nPresence: ${formatDuration(bucket.presence_seconds)}\nCoding: ${formatDuration(bucket.coding_seconds)}`}
                                aria-label={`${formatDateTime(bucket.bucket_started_at)} · ${humanizeStatus(bucket.status)}`}
                                onclick={() => (activeBucketStartedAt = bucket.bucket_started_at)}
                                onmouseenter={() => (activeBucketStartedAt = bucket.bucket_started_at)}
                                onfocus={() => (activeBucketStartedAt = bucket.bucket_started_at)}
                              >
                                <span class={statusRailTone(bucket)}></span>
                              </Button>
                            </div>
                          {/each}
                        </div>
                      </div>

                      <div class="market-chart__x-axis" data-bucket-count={bucketCount}>
                        {#each axisTickLabels as tick}
                          <div class="market-chart__tick-slot">
                            {#if tick.label}
                              <span>{tick.label}</span>
                            {/if}
                          </div>
                        {/each}
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            {/if}
          </div>

          <div class="grid gap-4 lg:grid-cols-3">
            <div class="rounded-2xl border border-surface-200 bg-surface p-4">
              <h3 class="m-0 text-lg font-semibold text-surface-content">
                Output mix
              </h3>
              <div class="mt-4 grid gap-4">
                <div>
                  <p class="m-0 text-xs uppercase tracking-[0.22em] text-muted">Projects</p>
                  <div class="mt-2 grid gap-2">
                    {#if selected_user.current_day.project_mix.length === 0}
                      <p class="m-0 text-sm text-muted">No project mix yet.</p>
                    {:else}
                      {#each selected_user.current_day.project_mix.slice(0, 5) as project}
                        <div class="flex items-center justify-between gap-3 text-sm">
                          <span class="text-surface-content">{project.name}</span>
                          <span class="text-muted">{formatDuration(project.seconds)}</span>
                        </div>
                      {/each}
                    {/if}
                  </div>
                </div>

                <div>
                  <p class="m-0 text-xs uppercase tracking-[0.22em] text-muted">Languages</p>
                  <div class="mt-2 grid gap-2">
                    {#if selected_user.current_day.language_mix.length === 0}
                      <p class="m-0 text-sm text-muted">No language mix yet.</p>
                    {:else}
                      {#each selected_user.current_day.language_mix.slice(0, 5) as language}
                        <div class="flex items-center justify-between gap-3 text-sm">
                          <span class="text-surface-content">{language.name}</span>
                          <span class="text-muted">{formatDuration(language.seconds)}</span>
                        </div>
                      {/each}
                    {/if}
                  </div>
                </div>

                <div>
                  <p class="m-0 text-xs uppercase tracking-[0.22em] text-muted">Editors</p>
                  <div class="mt-2 grid gap-2">
                    {#if selected_user.current_day.editor_mix.length === 0}
                      <p class="m-0 text-sm text-muted">No editor mix yet.</p>
                    {:else}
                      {#each selected_user.current_day.editor_mix.slice(0, 5) as editor}
                        <div class="flex items-center justify-between gap-3 text-sm">
                          <span class="text-surface-content">{editor.name}</span>
                          <span class="text-muted">{formatDuration(editor.seconds)}</span>
                        </div>
                      {/each}
                    {/if}
                  </div>
                </div>
              </div>
            </div>

            <div class="rounded-2xl border border-surface-200 bg-surface p-4">
              <h3 class="m-0 text-lg font-semibold text-surface-content">
                Delivery detail
              </h3>
              <div class="mt-4 grid gap-3 text-sm">
                <div class="flex items-center justify-between gap-3">
                  <span class="text-muted">Writes</span>
                  <strong class="text-surface-content">{selected_user.current_day.write_heartbeats_count}</strong>
                </div>
                <div class="flex items-center justify-between gap-3">
                  <span class="text-muted">Files touched</span>
                  <strong class="text-surface-content">{selected_user.current_day.unique_files_count}</strong>
                </div>
                <div class="flex items-center justify-between gap-3">
                  <span class="text-muted">Commits</span>
                  <strong class="text-surface-content">{selected_user.current_day.commit_count}</strong>
                </div>
                <div class="flex items-center justify-between gap-3">
                  <span class="text-muted">Commit additions</span>
                  <strong class="text-surface-content">{selected_user.current_day.commit_line_additions}</strong>
                </div>
                <div class="flex items-center justify-between gap-3">
                  <span class="text-muted">Commit deletions</span>
                  <strong class="text-surface-content">{selected_user.current_day.commit_line_deletions}</strong>
                </div>
                <div class="rounded-xl border border-surface-200 bg-dark p-3">
                  <p class="m-0 text-xs uppercase tracking-[0.22em] text-muted">
                    AI-Assisted Output (Experimental)
                  </p>
                  <div class="mt-2 flex items-center justify-between gap-3">
                    <span class={aiTone(selected_user.current_day.ai_assisted_output_level)}>
                      {selected_user.current_day.ai_assisted_output_level}
                    </span>
                    <span class="text-sm text-surface-content">
                      ratio {selected_user.current_day.ai_assisted_output_ratio.toFixed(1)}
                    </span>
                  </div>
                  <p class="mb-0 mt-2 text-xs text-muted">
                    {selected_user.current_day.ai_assisted_output_reason}
                  </p>
                </div>
              </div>
            </div>

            <div class="rounded-2xl border border-surface-200 bg-surface p-4">
              <h3 class="m-0 text-lg font-semibold text-surface-content">
                Schedule and trends
              </h3>
              <div class="mt-4 grid gap-4">
                <div class="grid gap-2 text-sm">
                  <div class="flex items-center justify-between gap-3">
                    <span class="text-muted">Window</span>
                    <strong class="text-surface-content">
                      {formatMinuteOfDay(selected_user.schedule.expected_start_minute_local)} - {formatMinuteOfDay(selected_user.schedule.expected_end_minute_local)}
                    </strong>
                  </div>
                  <div class="flex items-center justify-between gap-3">
                    <span class="text-muted">Timezone</span>
                    <strong class="text-surface-content">{selected_user.schedule.effective_timezone}</strong>
                  </div>
                  <div class="flex items-center justify-between gap-3">
                    <span class="text-muted">14d on-time</span>
                    <strong class="text-surface-content">{selected_user.trend_14d.on_time_days}/{selected_user.trend_14d.days_sampled}</strong>
                  </div>
                  <div class="flex items-center justify-between gap-3">
                    <span class="text-muted">30d on-time</span>
                    <strong class="text-surface-content">{selected_user.trend_30d.on_time_days}/{selected_user.trend_30d.days_sampled}</strong>
                  </div>
                  <div class="flex items-center justify-between gap-3">
                    <span class="text-muted">30d average coverage</span>
                    <strong class="text-surface-content">{formatPercent(selected_user.trend_30d.average_coverage)}</strong>
                  </div>
                </div>

                {#if can_edit_schedule}
                  <form method="POST" action={selected_user.schedule.update_path} class="grid gap-3 rounded-xl border border-surface-200 bg-dark p-4">
                    <input type="hidden" name="authenticity_token" value={csrfToken} />
                    <input type="hidden" name="_method" value="patch" />
                    <input type="hidden" name="profile[monitoring_enabled]" value="false" />
                    <h4 class="m-0 text-sm font-semibold uppercase tracking-[0.22em] text-muted">
                      Edit schedule
                    </h4>
                    <label class="grid gap-2 text-sm text-muted">
                      <span>Timezone override</span>
                      <input
                        class="rounded-xl border border-surface-200 bg-surface px-3 py-2 text-surface-content"
                        type="text"
                        name="profile[timezone_override]"
                        value={selected_user.schedule.timezone_override || ""}
                        placeholder={selected_user.schedule.effective_timezone}
                      />
                    </label>
                    <div class="grid gap-3 sm:grid-cols-2">
                      <label class="grid gap-2 text-sm text-muted">
                        <span>Expected start</span>
                        <input
                          class="rounded-xl border border-surface-200 bg-surface px-3 py-2 text-surface-content"
                          type="time"
                          step="60"
                          name="profile[expected_start_minute_local]"
                          value={formatMinuteOfDay(selected_user.schedule.expected_start_minute_local)}
                          placeholder="09:00"
                        />
                      </label>
                      <label class="grid gap-2 text-sm text-muted">
                        <span>Expected finish</span>
                        <input
                          class="rounded-xl border border-surface-200 bg-surface px-3 py-2 text-surface-content"
                          type="time"
                          step="60"
                          name="profile[expected_end_minute_local]"
                          value={formatMinuteOfDay(selected_user.schedule.expected_end_minute_local)}
                          placeholder="17:00"
                        />
                      </label>
                    </div>
                    <div class="grid gap-3 sm:grid-cols-2">
                      <label class="grid gap-2 text-sm text-muted">
                        <span>Start grace (minutes)</span>
                        <input
                          class="rounded-xl border border-surface-200 bg-surface px-3 py-2 text-surface-content"
                          type="number"
                          min="0"
                          max="240"
                          name="profile[start_grace_minutes]"
                          value={selected_user.schedule.start_grace_minutes}
                        />
                      </label>
                      <label class="grid gap-2 text-sm text-muted">
                        <span>End grace (minutes)</span>
                        <input
                          class="rounded-xl border border-surface-200 bg-surface px-3 py-2 text-surface-content"
                          type="number"
                          min="0"
                          max="240"
                          name="profile[end_grace_minutes]"
                          value={selected_user.schedule.end_grace_minutes}
                        />
                      </label>
                    </div>
                    <fieldset class="grid gap-2 border-0 p-0">
                      <legend class="text-sm text-muted">Workdays</legend>
                      <input type="hidden" name="profile[workdays][]" value="" />
                      <div class="flex flex-wrap gap-2">
                        {#each dayOptions as option}
                          <label class="workday-chip">
                            <input
                              type="checkbox"
                              name="profile[workdays][]"
                              value={option.value}
                              checked={selected_user.schedule.workdays.includes(option.value)}
                            />
                            <span>{option.label}</span>
                          </label>
                        {/each}
                      </div>
                    </fieldset>
                    <label class="workday-chip workday-chip--toggle">
                      <input
                        type="checkbox"
                        name="profile[monitoring_enabled]"
                        value="true"
                        checked={selected_user.schedule.monitoring_enabled}
                      />
                      <span>Monitoring enabled</span>
                    </label>
                    <Button type="submit" variant="primary" class="rounded-xl">
                      Save schedule
                    </Button>
                  </form>
                {:else}
                  <div class="rounded-xl border border-surface-200 bg-dark p-4 text-sm text-muted">
                    This view is read-only for viewers. Admins and superadmins can
                    edit schedule windows here.
                  </div>
                {/if}
              </div>
            </div>
          </div>

          <div class="grid gap-4 lg:grid-cols-2">
            <div class="rounded-2xl border border-surface-200 bg-surface p-4">
              <h3 class="m-0 text-lg font-semibold text-surface-content">Session spans</h3>
              <div class="mt-4 grid gap-3">
                {#if selected_user.current_day.session_spans.length === 0}
                  <p class="m-0 text-sm text-muted">No recorded sessions for this day yet.</p>
                {:else}
                  {#each selected_user.current_day.session_spans as session}
                    <div class="rounded-xl border border-surface-200 bg-dark p-3">
                      <div class="flex flex-wrap items-center justify-between gap-3">
                        <strong class="text-surface-content">
                          {formatDateTime(session.start_at)} - {formatDateTime(session.end_at)}
                        </strong>
                        <span class="text-sm text-muted">{formatDuration(session.duration_seconds)}</span>
                      </div>
                      <div class="mt-2 grid gap-1 text-xs text-muted">
                        <span>Projects: {session.projects.join(", ") || "None"}</span>
                        <span>Languages: {session.languages.join(", ") || "None"}</span>
                        <span>Editors: {session.editors.join(", ") || "None"}</span>
                      </div>
                    </div>
                  {/each}
                {/if}
              </div>
            </div>

            <div class="rounded-2xl border border-surface-200 bg-surface p-4">
              <h3 class="m-0 text-lg font-semibold text-surface-content">Recent attendance history</h3>
              <div class="mt-4 overflow-x-auto">
                <table class="min-w-full monitoring-table monitoring-table--compact">
                  <thead>
                    <tr>
                      <th>Date</th>
                      <th>Attendance</th>
                      <th>Coverage</th>
                      <th>Coding</th>
                      <th>Commits</th>
                    </tr>
                  </thead>
                  <tbody>
                    {#each selected_user.history.slice(0, 14) as row}
                      <tr>
                        <td>{formatShortDate(row.local_date)}</td>
                        <td>
                          <span class={signalTone(row.attendance_signal)}>
                            {row.attendance_signal.replaceAll("_", " ")}
                          </span>
                        </td>
                        <td>{formatPercent(row.coverage_percent)}</td>
                        <td>{formatDuration(row.coding_seconds)}</td>
                        <td>{row.commit_count}</td>
                      </tr>
                    {/each}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
      {:else}
        <div class="rounded-2xl border border-surface-200 bg-surface p-8 text-center text-muted">
          Select a developer from the roster to inspect timeline, schedule, and output detail.
        </div>
      {/if}
    </section>
  </div>
</div>

<style>
  .monitoring-shell {
    max-width: 1600px;
    margin: 0 auto;
  }

  .monitoring-grid {
    display: grid;
    gap: 1.25rem;
    grid-template-columns: minmax(0, 1fr);
  }

  .summary-card {
    border: 1px solid var(--color-surface-200);
    border-radius: 1rem;
    background: var(--color-dark);
    padding: 1rem;
  }

  .summary-card--active {
    box-shadow: inset 0 0 0 1px rgba(99, 255, 180, 0.25);
  }

  .summary-card--idle {
    box-shadow: inset 0 0 0 1px rgba(255, 215, 107, 0.22);
  }

  .summary-card--warn {
    box-shadow: inset 0 0 0 1px rgba(255, 153, 102, 0.22);
  }

  .summary-card--critical {
    box-shadow: inset 0 0 0 1px rgba(255, 107, 107, 0.24);
  }

  .summary-card--after {
    box-shadow: inset 0 0 0 1px rgba(111, 179, 255, 0.22);
  }

  .monitoring-table {
    width: 100%;
    border-collapse: collapse;
  }

  .monitoring-table th,
  .monitoring-table td {
    padding: 0.9rem 0.85rem;
    border-bottom: 1px solid var(--color-surface-200);
    vertical-align: top;
    text-align: left;
  }

  .monitoring-table thead th {
    font-size: 0.72rem;
    text-transform: uppercase;
    letter-spacing: 0.16em;
    color: var(--color-muted);
  }

  .monitoring-table tbody tr.selected {
    background: rgba(255, 191, 72, 0.08);
  }

  .monitoring-table--compact th,
  .monitoring-table--compact td {
    padding: 0.7rem 0.75rem;
  }

  .row-link {
    color: inherit;
    text-decoration: none;
  }

  .badge {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border-radius: 999px;
    padding: 0.28rem 0.68rem;
    font-size: 0.72rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.14em;
  }

  .badge--active,
  .badge--good {
    background: rgba(99, 255, 180, 0.16);
    color: #9cffca;
  }

  .badge--idle,
  .badge--warn {
    background: rgba(255, 215, 107, 0.16);
    color: #ffd76b;
  }

  .badge--inactive,
  .badge--critical {
    background: rgba(255, 107, 107, 0.16);
    color: #ff9a9a;
  }

  .badge--before,
  .badge--neutral {
    background: rgba(160, 174, 192, 0.16);
    color: #d1d9e6;
  }

  .badge--after,
  .badge--after-hours {
    background: rgba(111, 179, 255, 0.18);
    color: #8bc0ff;
  }

  .metric-card {
    border: 1px solid var(--color-surface-200);
    border-radius: 1rem;
    background: var(--color-surface);
    padding: 1rem;
  }

  .metric-card__label {
    margin: 0;
    font-size: 0.72rem;
    letter-spacing: 0.16em;
    text-transform: uppercase;
    color: var(--color-muted);
  }

  .metric-card__value {
    margin: 0.65rem 0 0;
    font-size: 1.35rem;
    font-weight: 700;
    color: var(--color-surface-content);
    text-transform: capitalize;
  }

  .metric-card__hint {
    margin: 0.35rem 0 0;
    color: var(--color-muted);
    font-size: 0.9rem;
  }

  .activity-chart__meta {
    display: flex;
    flex-wrap: wrap;
    align-items: flex-start;
    justify-content: space-between;
    gap: 1rem;
  }

  .activity-chart__intro {
    display: grid;
    gap: 0.45rem;
    max-width: 46rem;
  }

  .activity-chart__summary-card {
    border: 1px solid var(--color-surface-200);
    border-radius: 1rem;
    background: var(--color-dark);
    padding: 0.85rem 1rem;
  }

  .activity-chart__summary-label {
    margin: 0;
    font-size: 0.72rem;
    letter-spacing: 0.16em;
    text-transform: uppercase;
    color: var(--color-muted);
  }

  .activity-chart__summary-value {
    margin: 0.6rem 0 0;
    font-size: 1.25rem;
    font-weight: 700;
    color: var(--color-surface-content);
  }

  .activity-chart__summary-detail {
    margin: 0.35rem 0 0;
    font-size: 0.82rem;
    color: var(--color-muted);
  }

  .activity-chart__eyebrow {
    margin: 0;
    font-size: 0.72rem;
    letter-spacing: 0.18em;
    text-transform: uppercase;
    color: var(--color-muted);
  }

  .activity-chart__focus-card {
    width: min(100%, 18rem);
    border: 1px solid var(--color-surface-200);
    border-radius: 1rem;
    background: var(--color-dark);
    padding: 0.9rem 1rem;
    display: grid;
    gap: 0.4rem;
  }

  .activity-chart__focus-label {
    margin: 0;
    font-size: 0.72rem;
    letter-spacing: 0.16em;
    text-transform: uppercase;
    color: var(--color-muted);
  }

  .activity-chart__focus-grid {
    display: flex;
    flex-wrap: wrap;
    gap: 0.45rem;
    color: var(--color-muted);
    font-size: 0.82rem;
  }

  .activity-chart__focus-grid--compact {
    margin-top: -0.1rem;
  }

  .activity-chart__focus-grid span {
    border-radius: 999px;
    border: 1px solid var(--color-surface-200);
    background: var(--color-surface);
    padding: 0.28rem 0.55rem;
  }

  .activity-chart__legend-groups {
    display: grid;
    gap: 0.9rem;
    margin-bottom: 1rem;
  }

  .activity-chart__legend-block {
    display: grid;
    gap: 0.35rem;
  }

  .chart-legend {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75rem;
    align-items: center;
  }

  .chart-legend__item {
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    font-size: 0.8rem;
    color: var(--color-muted);
  }

  .chart-legend__swatch {
    width: 0.72rem;
    height: 0.72rem;
    border-radius: 999px;
    display: inline-block;
    box-shadow: 0 0 0 1px rgba(255, 255, 255, 0.08);
  }

  .chart-legend__swatch--active,
  .status-rail__segment--active {
    background: rgba(99, 255, 180, 0.32);
  }

  .chart-legend__swatch--idle,
  .status-rail__segment--idle {
    background: rgba(255, 215, 107, 0.32);
  }

  .chart-legend__swatch--inactive,
  .status-rail__segment--inactive {
    background: rgba(255, 107, 107, 0.28);
  }

  .chart-legend__swatch--before,
  .status-rail__segment--before {
    background: rgba(160, 174, 192, 0.24);
  }

  .chart-legend__swatch--after,
  .status-rail__segment--after {
    background: rgba(111, 179, 255, 0.28);
  }

  .activity-chart__empty-state {
    border: 1px dashed var(--color-surface-200);
    border-radius: 1rem;
    background: var(--color-dark);
    padding: 1rem 1.1rem;
    color: var(--color-muted);
    font-size: 0.92rem;
  }

  .market-chart {
    border: 1px solid var(--color-surface-200);
    border-radius: 1.1rem;
    background:
      radial-gradient(circle at top left, rgba(255, 191, 72, 0.08), transparent 34%),
      linear-gradient(180deg, rgba(255, 255, 255, 0.03), rgba(255, 255, 255, 0.01)),
      var(--color-dark);
    padding: 1rem;
  }

  .market-chart__frame {
    display: grid;
    grid-template-columns: 4.4rem minmax(0, 1fr);
    gap: 0.85rem;
    align-items: start;
  }

  .market-chart__axes,
  .market-chart__timeline {
    display: grid;
    grid-template-rows: 16rem 8rem 2.5rem 1.8rem;
    gap: 0.8rem;
  }

  .market-chart__axis-block {
    display: grid;
    grid-template-rows: auto auto 1fr;
    gap: 0.35rem;
  }

  .market-chart__axis-block--status {
    grid-template-rows: auto auto;
    align-content: center;
  }

  .market-chart__axis-title {
    margin: 0;
    font-size: 0.72rem;
    letter-spacing: 0.16em;
    text-transform: uppercase;
    color: var(--color-muted);
  }

  .market-chart__axis-subtitle {
    margin: 0;
    font-size: 0.74rem;
    line-height: 1.35;
    color: var(--color-muted);
  }

  .market-chart__y-axis {
    display: grid;
    grid-template-rows: repeat(4, minmax(0, 1fr));
    align-items: end;
    font-size: 0.74rem;
    color: var(--color-muted);
  }

  .market-chart__axis-footer {
    display: flex;
    align-items: flex-start;
    font-size: 0.74rem;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--color-muted);
    padding-top: 0.2rem;
  }

  .market-chart__scroll {
    overflow-x: auto;
    padding-bottom: 0.25rem;
  }

  .market-chart__timeline {
    --bucket-count: 1;
    --bucket-width: 1rem;
    --bucket-gap: 0.28rem;
    min-width: max-content;
  }

  .market-chart__track {
    position: relative;
    border: 1px solid var(--color-surface-200);
    border-radius: 1rem;
    overflow: hidden;
    padding: 0.38rem 0.32rem;
  }

  .market-chart__track--languages,
  .market-chart__track--churn {
    background-color: rgba(255, 255, 255, 0.015);
    background-image: linear-gradient(
      to top,
      rgba(255, 255, 255, 0.09) 0,
      rgba(255, 255, 255, 0.09) 1px,
      transparent 1px,
      transparent 25%
    );
    background-size: 100% 25%;
  }

  .market-chart__track--status {
    background: rgba(255, 255, 255, 0.02);
    padding: 0.32rem;
  }

  .market-chart__grid,
  .market-chart__x-axis {
    display: grid;
    grid-template-columns: repeat(var(--bucket-count), minmax(var(--bucket-width), var(--bucket-width)));
    gap: var(--bucket-gap);
    min-width: max-content;
  }

  .market-chart__grid {
    height: 100%;
  }

  .market-chart__grid--bars {
    align-items: end;
  }

  .market-chart__grid--status {
    align-items: stretch;
  }

  .market-chart__slot {
    position: relative;
    min-width: 0;
  }

  .market-chart__slot--active::after {
    content: "";
    position: absolute;
    inset: -0.16rem -0.12rem;
    border-radius: 0.8rem;
    border: 1px solid rgba(255, 191, 72, 0.28);
    background: rgba(255, 191, 72, 0.05);
    pointer-events: none;
  }

  .market-chart__stack,
  .market-chart__status-button {
    width: 100%;
    height: 100%;
    padding: 0;
    border: 0;
    background: transparent;
  }

  .market-chart__stack {
    border-radius: 0.75rem;
    display: flex;
    flex-direction: column-reverse;
    gap: 1px;
    align-items: stretch;
    cursor: pointer;
    transition:
      transform 120ms ease,
      box-shadow 120ms ease,
      background 120ms ease;
  }

  .market-chart__stack:focus-visible,
  .market-chart__stack--active,
  .market-chart__status-button:focus-visible,
  .market-chart__status-button--active {
    transform: translateY(-2px);
    box-shadow: 0 0 0 1px rgba(255, 191, 72, 0.35);
    background: rgba(255, 191, 72, 0.06);
    outline: none;
  }

  .market-chart__segment {
    width: 100%;
    border-radius: 0.4rem;
    min-height: 0.16rem;
  }

  .market-chart__zero {
    width: 100%;
    height: 2px;
    margin-top: auto;
    border-radius: 999px;
    background: rgba(160, 174, 192, 0.4);
  }

  .market-chart__status-button {
    border-radius: 0.7rem;
  }

  .status-rail {
    display: grid;
    gap: var(--bucket-gap);
  }

  .status-rail__segment {
    display: block;
    width: 100%;
    height: 100%;
    min-height: 1.55rem;
    border-radius: 999px;
    border: 1px solid transparent;
  }

  .market-chart__panel-note {
    position: absolute;
    left: 0.7rem;
    bottom: 0.55rem;
    margin: 0;
    max-width: 20rem;
    font-size: 0.76rem;
    line-height: 1.35;
    color: var(--color-muted);
    pointer-events: none;
  }

  .market-chart__x-axis {
    align-items: start;
    padding: 0 0.08rem;
  }

  .market-chart__tick-slot {
    position: relative;
    min-height: 1.7rem;
  }

  .market-chart__tick-slot::before {
    content: "";
    position: absolute;
    top: 0;
    left: 50%;
    width: 1px;
    height: 0.42rem;
    transform: translateX(-50%);
    background: rgba(160, 174, 192, 0.36);
  }

  .market-chart__tick-slot span {
    position: absolute;
    top: 0.56rem;
    left: 50%;
    transform: translateX(-50%);
    white-space: nowrap;
    font-size: 0.7rem;
    color: var(--color-muted);
  }

  .workday-chip {
    display: inline-flex;
    align-items: center;
    gap: 0.45rem;
    border-radius: 999px;
    border: 1px solid var(--color-surface-200);
    padding: 0.45rem 0.8rem;
    color: var(--color-surface-content);
    background: var(--color-surface);
    font-size: 0.9rem;
  }

  .workday-chip--toggle {
    justify-content: flex-start;
    width: fit-content;
  }

  @media (max-width: 768px) {
    .market-chart {
      padding: 0.8rem;
    }

    .market-chart__frame {
      grid-template-columns: 1fr;
    }

    .market-chart__axes {
      grid-template-rows: none;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 0.55rem;
      order: 2;
    }

    .market-chart__axis-block {
      grid-template-rows: auto auto auto;
    }

    .market-chart__axis-block--status {
      grid-template-rows: auto auto;
    }

    .market-chart__y-axis {
      grid-template-columns: repeat(4, minmax(0, 1fr));
      grid-template-rows: none;
      align-items: start;
      gap: 0.4rem;
    }

    .market-chart__timeline {
      grid-template-rows: 13rem 6.5rem 2.3rem 1.7rem;
      --bucket-gap: 0.22rem;
    }

    .activity-chart__focus-card {
      width: 100%;
    }

    .status-rail__segment {
      min-height: 1.2rem;
    }

    .market-chart__panel-note {
      max-width: 13rem;
    }
  }
</style>
