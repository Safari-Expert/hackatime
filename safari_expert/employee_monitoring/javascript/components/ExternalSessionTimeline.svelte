<script lang="ts">
  type TimelineSession = {
    id: number;
    started_at: string;
    ended_at: string | null;
    display_started_at: string;
    display_ended_at: string;
    duration_seconds: number;
    close_reason: string | null;
    state: string;
  };

  type TimelinePayload = {
    local_date: string;
    timezone: string;
    day_start_at: string;
    day_end_at: string;
    expected_start_at: string | null;
    expected_end_at: string | null;
    session_count: number;
    sessions: TimelineSession[];
  };

  const MINUTES_IN_DAY = 24 * 60;
  const VIEWBOX_WIDTH = MINUTES_IN_DAY;
  const VIEWBOX_HEIGHT = 72;
  const TRACK_Y = 24;
  const TRACK_HEIGHT = 24;
  const SESSION_Y = 28;
  const SESSION_HEIGHT = 16;
  const AXIS_TICKS = Array.from({ length: 9 }, (_, index) => index * 180);

  let {
    timeline,
    title = "Today's session timeline",
    description = "Clocked sessions across the current local day.",
  }: {
    timeline: TimelinePayload;
    title?: string;
    description?: string;
  } = $props();

  function formatDuration(totalSeconds: number) {
    if (totalSeconds <= 0) return "0m";

    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);

    if (hours === 0) return `${minutes}m`;
    if (minutes === 0) return `${hours}h`;
    return `${hours}h ${minutes}m`;
  }

  function formatTime(value: string | null) {
    if (!value) return "In progress";

    return new Intl.DateTimeFormat("en-GB", {
      hour: "2-digit",
      minute: "2-digit",
      timeZone: timeline.timezone,
    }).format(new Date(value));
  }

  function formatDate(value: string) {
    return new Intl.DateTimeFormat("en-GB", {
      weekday: "short",
      day: "numeric",
      month: "short",
      timeZone: timeline.timezone,
    }).format(new Date(value));
  }

  function minuteOffset(value: string) {
    const offset = (new Date(value).getTime() - new Date(timeline.day_start_at).getTime()) / 60000;
    return Math.min(Math.max(offset, 0), MINUTES_IN_DAY);
  }

  function rectX(startAt: string) {
    return minuteOffset(startAt);
  }

  function rectWidth(startAt: string, endAt: string) {
    return Math.max(minuteOffset(endAt) - minuteOffset(startAt), 4);
  }

  function tickLabel(offsetMinutes: number) {
    return formatTime(new Date(new Date(timeline.day_start_at).getTime() + offsetMinutes * 60_000).toISOString());
  }

  function sessionTone(session: TimelineSession) {
    return session.state === "open" ? "timeline-card__session timeline-card__session--open" : "timeline-card__session";
  }

  function closeReasonLabel(value: string | null) {
    if (value === "auto_closed_eod") return "auto-closed";
    if (value === "user_clock_out") return "clocked out";
    return "in progress";
  }
</script>

<div class="timeline-card" data-external-session-timeline data-session-count={timeline.sessions.length}>
  <div class="timeline-card__header">
    <div>
      <h3 class="timeline-card__title">{title}</h3>
      <p class="timeline-card__description">{description}</p>
    </div>
    <div class="timeline-card__meta">
      <strong>{formatDate(timeline.local_date)}</strong>
      <span>{timeline.timezone}</span>
    </div>
  </div>

  <div class="timeline-card__chart">
    <svg
      class="timeline-card__svg"
      viewBox={`0 0 ${VIEWBOX_WIDTH} ${VIEWBOX_HEIGHT}`}
      aria-label={`Session timeline for ${timeline.local_date}`}
      preserveAspectRatio="none"
      role="img"
    >
      <rect
        class="timeline-card__track"
        x="0"
        y={TRACK_Y}
        width={VIEWBOX_WIDTH}
        height={TRACK_HEIGHT}
        rx="12"
      />

      {#if timeline.expected_start_at && timeline.expected_end_at}
        <rect
          class="timeline-card__expected-window"
          x={rectX(timeline.expected_start_at)}
          y={TRACK_Y}
          width={rectWidth(timeline.expected_start_at, timeline.expected_end_at)}
          height={TRACK_HEIGHT}
          rx="12"
        />
      {/if}

      {#each AXIS_TICKS.slice(1, -1) as tick}
        <line
          class="timeline-card__gridline"
          x1={tick}
          x2={tick}
          y1={TRACK_Y - 6}
          y2={TRACK_Y + TRACK_HEIGHT + 6}
        />
      {/each}

      {#each timeline.sessions as session}
        <rect
          class={session.state === "open"
            ? "timeline-card__session-bar timeline-card__session-bar--open"
            : "timeline-card__session-bar"}
          x={rectX(session.display_started_at)}
          y={SESSION_Y}
          width={rectWidth(session.display_started_at, session.display_ended_at)}
          height={SESSION_HEIGHT}
          rx="8"
          data-session-id={session.id}
          data-session-state={session.state}
        >
          <title>
            {`${formatTime(session.started_at)} - ${session.ended_at ? formatTime(session.ended_at) : "Now"} · ${formatDuration(session.duration_seconds)}`}
          </title>
        </rect>
      {/each}
    </svg>

    <div class="timeline-card__axis" aria-hidden="true">
      {#each AXIS_TICKS as tick}
        <span>{tickLabel(tick)}</span>
      {/each}
    </div>

    <div class="timeline-card__legend">
      <span><i class="timeline-card__legend-swatch timeline-card__legend-swatch--expected"></i>Expected schedule</span>
      <span><i class="timeline-card__legend-swatch timeline-card__legend-swatch--session"></i>Clocked session</span>
      <span><i class="timeline-card__legend-swatch timeline-card__legend-swatch--open"></i>Active session</span>
    </div>
  </div>

  {#if timeline.sessions.length === 0}
    <div class="timeline-card__empty">
      No sessions recorded for this day yet.
    </div>
  {:else}
    <div class="timeline-card__session-list">
      {#each timeline.sessions as session}
        <article
          class={sessionTone(session)}
          data-external-session-row
          data-session-state={session.state}
        >
          <div class="timeline-card__session-main">
            <strong>{formatTime(session.started_at)} - {session.ended_at ? formatTime(session.ended_at) : "Now"}</strong>
            <span>{formatDuration(session.duration_seconds)}</span>
          </div>
          <div class="timeline-card__session-meta">
            <span>{closeReasonLabel(session.close_reason)}</span>
            <span>{session.state === "open" ? "currently clocked in" : "session closed"}</span>
          </div>
        </article>
      {/each}
    </div>
  {/if}
</div>

<style>
  .timeline-card {
    display: grid;
    gap: 1rem;
  }

  .timeline-card__header {
    display: flex;
    justify-content: space-between;
    gap: 1rem;
    align-items: flex-start;
    flex-wrap: wrap;
  }

  .timeline-card__title {
    margin: 0;
    font-size: 1.125rem;
    font-weight: 600;
    color: var(--color-surface-content);
  }

  .timeline-card__description {
    margin: 0.35rem 0 0;
    font-size: 0.92rem;
    color: var(--color-muted);
  }

  .timeline-card__meta {
    display: grid;
    gap: 0.2rem;
    text-align: right;
    color: var(--color-muted);
    font-size: 0.82rem;
  }

  .timeline-card__meta strong {
    color: var(--color-surface-content);
    font-size: 0.92rem;
  }

  .timeline-card__chart {
    display: grid;
    gap: 0.7rem;
  }

  .timeline-card__svg {
    width: 100%;
    min-height: 5.5rem;
    overflow: visible;
  }

  .timeline-card__track {
    fill: rgba(148, 163, 184, 0.12);
    stroke: rgba(148, 163, 184, 0.18);
    stroke-width: 1;
  }

  .timeline-card__expected-window {
    fill: rgba(250, 204, 21, 0.12);
    stroke: rgba(250, 204, 21, 0.24);
    stroke-width: 1;
  }

  .timeline-card__gridline {
    stroke: rgba(148, 163, 184, 0.2);
    stroke-width: 1;
    stroke-dasharray: 6 10;
  }

  .timeline-card__session-bar {
    fill: rgba(56, 189, 248, 0.8);
    stroke: rgba(125, 211, 252, 0.95);
    stroke-width: 1;
  }

  .timeline-card__session-bar--open {
    fill: rgba(74, 222, 128, 0.85);
    stroke: rgba(134, 239, 172, 0.95);
  }

  .timeline-card__axis {
    display: grid;
    grid-template-columns: repeat(9, minmax(0, 1fr));
    gap: 0.5rem;
    font-size: 0.74rem;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--color-muted);
  }

  .timeline-card__axis span {
    white-space: nowrap;
  }

  .timeline-card__axis span:last-child {
    text-align: right;
  }

  .timeline-card__legend {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75rem 1rem;
    font-size: 0.78rem;
    color: var(--color-muted);
  }

  .timeline-card__legend span {
    display: inline-flex;
    align-items: center;
    gap: 0.45rem;
  }

  .timeline-card__legend-swatch {
    display: inline-block;
    width: 0.8rem;
    height: 0.8rem;
    border-radius: 9999px;
  }

  .timeline-card__legend-swatch--expected {
    background: rgba(250, 204, 21, 0.35);
    border: 1px solid rgba(250, 204, 21, 0.45);
  }

  .timeline-card__legend-swatch--session {
    background: rgba(56, 189, 248, 0.8);
  }

  .timeline-card__legend-swatch--open {
    background: rgba(74, 222, 128, 0.85);
  }

  .timeline-card__empty {
    border: 1px dashed var(--color-surface-200);
    border-radius: 1rem;
    padding: 1rem;
    color: var(--color-muted);
    background: rgba(15, 23, 42, 0.28);
  }

  .timeline-card__session-list {
    display: grid;
    gap: 0.75rem;
  }

  .timeline-card__session {
    display: grid;
    gap: 0.35rem;
    border: 1px solid var(--color-surface-200);
    border-radius: 1rem;
    padding: 0.9rem 1rem;
    background: rgba(15, 23, 42, 0.3);
  }

  .timeline-card__session--open {
    border-color: rgba(74, 222, 128, 0.45);
    background: rgba(20, 83, 45, 0.22);
  }

  .timeline-card__session-main {
    display: flex;
    justify-content: space-between;
    gap: 0.75rem;
    flex-wrap: wrap;
    color: var(--color-surface-content);
  }

  .timeline-card__session-meta {
    display: flex;
    justify-content: space-between;
    gap: 0.75rem;
    flex-wrap: wrap;
    color: var(--color-muted);
    font-size: 0.82rem;
    text-transform: lowercase;
  }

  @media (max-width: 640px) {
    .timeline-card__axis {
      font-size: 0.66rem;
      gap: 0.35rem;
    }
  }
</style>
