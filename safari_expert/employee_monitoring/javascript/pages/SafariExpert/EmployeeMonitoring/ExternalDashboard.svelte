<script lang="ts">
  import { onMount } from "svelte";
  import Button from "../../../../../../app/javascript/components/Button.svelte";

  type ScheduleDayRow = {
    weekday: number;
    day_label: string;
    enabled: boolean;
    expected_start_minute_local: number;
    expected_end_minute_local: number;
  };

  type WeekRow = {
    local_date: string;
    weekday_label: string;
    scheduled: boolean;
    expected_start_at: string | null;
    expected_end_at: string | null;
    expected_seconds: number;
    actual_start_at: string | null;
    actual_end_at: string | null;
    actual_seconds: number;
    start_status: string;
    hours_status: string;
    auto_closed: boolean;
  };

  type UserPayload = {
    id: number;
    display_name: string;
    username: string | null;
    avatar_url: string | null;
    schedule: {
      effective_timezone: string;
      timezone_override: string | null;
      label: string;
      monitoring_enabled: boolean;
      update_path: string;
      schedule_days: ScheduleDayRow[];
      start_grace_minutes: number;
      end_grace_minutes: number;
    };
    attendance: {
      state: string;
      open_session_started_at: string | null;
      today_seconds: number;
      week_seconds: number;
      month_seconds: number;
      week_rows: WeekRow[];
    };
  };

  let {
    page_title,
    user,
    can_clock,
    can_edit_schedule,
    clock_in_path,
    clock_out_path,
  }: {
    page_title: string;
    user: UserPayload;
    can_clock: boolean;
    can_edit_schedule: boolean;
    clock_in_path: string;
    clock_out_path: string;
  } = $props();

  let csrfToken = $state("");

  onMount(() => {
    csrfToken =
      document
        .querySelector("meta[name='csrf-token']")
        ?.getAttribute("content") || "";
  });

  function formatDuration(totalSeconds: number) {
    if (totalSeconds <= 0) return "0m";

    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);

    if (hours === 0) return `${minutes}m`;
    if (minutes === 0) return `${hours}h`;
    return `${hours}h ${minutes}m`;
  }

  function formatDateTime(value: string | null) {
    if (!value) return "Not recorded";

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

  function formatMinuteOfDay(totalMinutes: number) {
    const hours = Math.floor(totalMinutes / 60);
    const minutes = totalMinutes % 60;
    return `${hours.toString().padStart(2, "0")}:${minutes.toString().padStart(2, "0")}`;
  }

  function startTone(status: string) {
    switch (status) {
      case "on_time":
        return "badge badge--good";
      case "late":
        return "badge badge--warn";
      case "not_started":
        return "badge badge--critical";
      default:
        return "badge badge--neutral";
    }
  }

  function hoursTone(status: string) {
    switch (status) {
      case "met":
        return "badge badge--good";
      case "short":
        return "badge badge--warn";
      case "not_clocked_out":
        return "badge badge--critical";
      case "in_progress":
        return "badge badge--neutral";
      default:
        return "badge badge--neutral";
    }
  }

  function humanize(value: string) {
    return value.replaceAll("_", " ");
  }
</script>

<svelte:head>
  <title>{page_title}</title>
</svelte:head>

<div class="mx-auto max-w-6xl px-4 py-6">
  <div class="grid gap-5">
    <div class="rounded-2xl border border-surface-200 bg-dark p-5">
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div class="space-y-2">
          <p class="m-0 text-xs uppercase tracking-[0.22em] text-muted">
            External Attendance
          </p>
          <h1 class="m-0 text-3xl font-bold text-surface-content">
            {user.display_name}
          </h1>
          <p class="m-0 text-sm text-muted">
            {user.username ? `@${user.username}` : `User ${user.id}`} · {user.schedule.label}
          </p>
          <p class="m-0 text-sm text-muted">
            {user.schedule.effective_timezone}
          </p>
        </div>

        <div class="min-w-[240px] rounded-xl border border-surface-200 bg-surface p-4">
          <p class="m-0 text-xs uppercase tracking-[0.22em] text-muted">
            Current status
          </p>
          <p class="mt-2 text-xl font-semibold text-surface-content">
            {humanize(user.attendance.state)}
          </p>
          <p class="m-0 mt-2 text-sm text-muted">
            {user.attendance.state === "clocked_in"
              ? `Started ${formatDateTime(user.attendance.open_session_started_at)}`
              : "No active work session"}
          </p>

          {#if can_clock}
            <div class="mt-4 flex flex-wrap gap-2">
              <form method="POST" action={clock_in_path}>
                <input type="hidden" name="authenticity_token" value={csrfToken} />
                <Button
                  type="submit"
                  variant="primary"
                  disabled={user.attendance.state === "clocked_in"}
                  class="rounded-xl"
                >
                  Clock in
                </Button>
              </form>

              <form method="POST" action={clock_out_path}>
                <input type="hidden" name="authenticity_token" value={csrfToken} />
                <Button
                  type="submit"
                  variant="surface"
                  disabled={user.attendance.state !== "clocked_in"}
                  class="rounded-xl"
                >
                  Clock out
                </Button>
              </form>
            </div>
          {/if}
        </div>
      </div>
    </div>

    <div class="grid gap-4 md:grid-cols-3">
      <div class="rounded-2xl border border-surface-200 bg-surface p-4">
        <p class="m-0 text-xs uppercase tracking-[0.22em] text-muted">Today</p>
        <p class="mt-3 text-3xl font-semibold text-surface-content">
          {formatDuration(user.attendance.today_seconds)}
        </p>
      </div>
      <div class="rounded-2xl border border-surface-200 bg-surface p-4">
        <p class="m-0 text-xs uppercase tracking-[0.22em] text-muted">This week</p>
        <p class="mt-3 text-3xl font-semibold text-surface-content">
          {formatDuration(user.attendance.week_seconds)}
        </p>
      </div>
      <div class="rounded-2xl border border-surface-200 bg-surface p-4">
        <p class="m-0 text-xs uppercase tracking-[0.22em] text-muted">This month</p>
        <p class="mt-3 text-3xl font-semibold text-surface-content">
          {formatDuration(user.attendance.month_seconds)}
        </p>
      </div>
    </div>

    <div class="grid gap-4 lg:grid-cols-[minmax(0,1.5fr)_minmax(320px,1fr)]">
      <div class="rounded-2xl border border-surface-200 bg-surface p-4">
        <div class="flex items-center justify-between gap-3">
          <div>
            <h2 class="m-0 text-xl font-semibold text-surface-content">
              Current week
            </h2>
            <p class="m-1 text-sm text-muted">
              Expected schedule versus worked time for each day.
            </p>
          </div>
        </div>

        <div class="mt-4 overflow-x-auto">
          <table class="min-w-full monitoring-table monitoring-table--compact">
            <thead>
              <tr>
                <th>Day</th>
                <th>Expected start</th>
                <th>Expected finish</th>
                <th>Expected hours</th>
                <th>Actual start</th>
                <th>Actual finish</th>
                <th>Actual hours</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {#each user.attendance.week_rows as row}
                <tr>
                  <td>
                    <div class="grid gap-1">
                      <span class="font-medium text-surface-content">
                        {row.weekday_label}
                      </span>
                      <span class="text-xs text-muted">
                        {formatShortDate(row.local_date)}
                      </span>
                    </div>
                  </td>
                  <td>{formatDateTime(row.expected_start_at)}</td>
                  <td>{formatDateTime(row.expected_end_at)}</td>
                  <td>{formatDuration(row.expected_seconds)}</td>
                  <td>{formatDateTime(row.actual_start_at)}</td>
                  <td>{formatDateTime(row.actual_end_at)}</td>
                  <td>{formatDuration(row.actual_seconds)}</td>
                  <td>
                    <div class="flex flex-wrap gap-2">
                      <span class={startTone(row.start_status)}>
                        {humanize(row.start_status)}
                      </span>
                      <span class={hoursTone(row.hours_status)}>
                        {humanize(row.hours_status)}
                      </span>
                    </div>
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      </div>

      <div class="rounded-2xl border border-surface-200 bg-surface p-4">
        <h2 class="m-0 text-xl font-semibold text-surface-content">
          Weekly schedule
        </h2>
        <div class="mt-4 grid gap-3">
          {#each user.schedule.schedule_days as day}
            <div class="flex items-center justify-between gap-3 rounded-xl border border-surface-200 bg-dark px-3 py-2 text-sm">
              <span class="text-surface-content">{day.day_label}</span>
              {#if day.enabled}
                <span class="text-muted">
                  {formatMinuteOfDay(day.expected_start_minute_local)} -
                  {formatMinuteOfDay(day.expected_end_minute_local)}
                </span>
              {:else}
                <span class="text-muted">Off</span>
              {/if}
            </div>
          {/each}
        </div>

        {#if can_edit_schedule}
          <p class="mt-4 text-sm text-muted">
            Admin schedule editing is available from the shared employee monitoring roster.
          </p>
        {/if}
      </div>
    </div>
  </div>
</div>

<style>
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

  .badge {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
    padding: 0.3rem 0.65rem;
    border-radius: 9999px;
    font-size: 0.72rem;
    text-transform: uppercase;
    letter-spacing: 0.14em;
    font-weight: 600;
  }

  .badge--good {
    background: rgba(74, 222, 128, 0.12);
    color: #7af0a8;
  }

  .badge--warn {
    background: rgba(251, 146, 60, 0.12);
    color: #ffc285;
  }

  .badge--critical {
    background: rgba(248, 113, 113, 0.14);
    color: #ff9b9b;
  }

  .badge--neutral {
    background: rgba(148, 163, 184, 0.14);
    color: #d7dde7;
  }
</style>
