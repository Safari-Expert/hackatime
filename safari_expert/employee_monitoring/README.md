# Employee Monitoring

This fork-owned feature adds a native Hackatime monitoring surface at `/admin/employee_monitoring`.

Scope:
- attendance tracking against per-user schedule windows
- activity and delivery monitoring without collapsing into one score
- 5-minute interval snapshots and daily rollups stored inside Hackatime
- an experimental AI-assisted output heuristic derived from telemetry already present in heartbeats and commits

Storage:
- `employee_monitoring_profiles`
- `employee_monitoring_daily_rollups`
- `employee_monitoring_interval_snapshots`

Runtime pieces:
- Rails controllers and admin APIs live under `safari_expert/employee_monitoring/app`
- Svelte pages live under `safari_expert/employee_monitoring/javascript/pages`
- the GoodJob cron entry runs every 5 minutes via `SafariExpert::EmployeeMonitoring::RollupJob`

Important constraints:
- viewers can read the monitoring surface
- only admins and superadmins can edit schedule profiles
- the AI metric is directional only and must not be treated as proof of Copilot usage or as an attendance signal
