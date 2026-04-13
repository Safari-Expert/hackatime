# frozen_string_literal: true

module SafariExpert
  module EmployeeMonitoring
    class RollupBuilder
      NormalizedHeartbeat = Struct.new(
        :id,
        :at,
        :category,
        :project,
        :language,
        :editor,
        :entity,
        :is_write,
        :line_additions,
        :line_deletions,
        :source_type,
        keyword_init: true
      )

      def initialize(user:, now: Time.current, local_date: nil, persist: false)
        @user = user
        @now = now
        @persist = persist
        @local_date = local_date
      end

      def call
        profile = EmployeeMonitoringProfile.for_user(@user)
        timezone = profile.effective_timezone(@user)
        zone = ActiveSupport::TimeZone[timezone] || ActiveSupport::TimeZone["UTC"]
        reference_now = @now.in_time_zone(zone)
        local_date = @local_date || reference_now.to_date
        day_range = day_range_for(zone, local_date)
        window = profile.schedule_window(local_date, user: @user)

        heartbeats = load_heartbeats(day_range)
        intervals = build_intervals(heartbeats, reference_now, local_date)
        commits = load_commits(day_range)
        timeline = build_timeline(heartbeats, intervals, window, reference_now, zone, local_date)

        payload = build_payload(
          profile: profile,
          timezone: timezone,
          local_date: local_date,
          heartbeats: heartbeats,
          intervals: intervals,
          commits: commits,
          timeline: timeline,
          window: window,
          reference_now: reference_now
        )

        persist!(payload) if @persist
        payload
      end

      private

      def build_payload(profile:, timezone:, local_date:, heartbeats:, intervals:, commits:, timeline:, window:, reference_now:)
        first_seen_at = heartbeats.first&.at
        last_seen_at = heartbeats.last&.at
        project_mix = ranked_mix(intervals, :project)
        language_mix = ranked_mix(intervals, :language)
        editor_mix = ranked_mix(intervals, :editor)
        commit_markers = commits.map { |commit| commit_marker(commit) }.sort_by { |marker| marker[:timestamp] }
        coverage_percent = coverage_percent_for(intervals, window, reference_now)
        status = status_at(window: window, first_seen_at: first_seen_at, last_seen_at: last_seen_at, reference_time: reference_now, profile: profile)
        not_started_yet = not_started_yet?(window, first_seen_at, reference_now, profile)
        ended_early = ended_early?(window, last_seen_at, reference_now, profile)
        after_hours_active = after_hours_active?(window, last_seen_at, reference_now, profile)
        sessions = build_sessions(heartbeats, intervals)
        commit_additions = commit_markers.sum { |marker| marker[:additions].to_i }
        commit_deletions = commit_markers.sum { |marker| marker[:deletions].to_i }
        write_heartbeats = heartbeats.count(&:is_write)
        ai_signal = ai_signal_for(
          heartbeats: heartbeats,
          write_heartbeats: write_heartbeats,
          commit_additions: commit_additions,
          commit_deletions: commit_deletions
        )

        {
          id: @user.id,
          display_name: @user.display_name,
          username: @user.username.presence || @user.github_username.presence,
          avatar_url: @user.avatar_url,
          timezone: timezone,
          local_date: local_date.iso8601,
          expected_start_at: window&.dig(:start_at)&.iso8601,
          expected_end_at: window&.dig(:end_at)&.iso8601,
          schedule_label: profile.schedule_label(user: @user),
          first_seen_at: first_seen_at&.iso8601,
          last_seen_at: last_seen_at&.iso8601,
          start_delta_minutes: delta_minutes(first_seen_at, window&.dig(:start_at)),
          end_delta_minutes: delta_minutes(last_seen_at, window&.dig(:end_at)),
          status: status,
          not_started_yet: not_started_yet,
          ended_early: ended_early,
          after_hours_active: after_hours_active,
          presence_seconds: intervals.sum { |interval| interval[:seconds].to_i },
          coding_seconds: intervals.sum { |interval| coding_interval?(interval[:heartbeat]) ? interval[:seconds].to_i : 0 },
          write_heartbeats_count: write_heartbeats,
          unique_files_count: heartbeats.map(&:entity).compact_blank.uniq.count,
          unique_projects_count: heartbeats.map(&:project).compact_blank.uniq.count,
          unique_languages_count: heartbeats.map(&:language).compact_blank.uniq.count,
          session_count: sessions.length,
          gap_count: gap_count_for(heartbeats),
          coverage_percent: coverage_percent,
          commit_count: commits.length,
          commit_line_additions: commit_additions,
          commit_line_deletions: commit_deletions,
          top_project: project_mix.first&.dig(:name),
          top_language: language_mix.first&.dig(:name),
          top_editor: editor_mix.first&.dig(:name),
          attendance_signal: attendance_signal_for(status, not_started_yet, ended_early, first_seen_at, window, profile),
          activity_signal: activity_signal_for(intervals, coverage_percent, write_heartbeats),
          delivery_signal: delivery_signal_for(commits, write_heartbeats, commit_additions, commit_deletions),
          ai_assisted_output_level: ai_signal[:level],
          ai_assisted_output_ratio: ai_signal[:ratio],
          ai_assisted_output_confidence: ai_signal[:confidence],
          ai_assisted_output_reason: ai_signal[:reason],
          timeline_buckets: timeline[:buckets],
          active_bucket_count: timeline[:buckets].count { |bucket| bucket[:in_window] && bucket[:status] == "active" },
          idle_bucket_count: timeline[:buckets].count { |bucket| bucket[:in_window] && bucket[:status] == "idle" },
          session_spans: sessions,
          project_mix: project_mix,
          language_mix: language_mix,
          editor_mix: editor_mix,
          commit_markers: commit_markers
        }
      end

      def day_range_for(zone, local_date)
        day_start = zone.local(local_date.year, local_date.month, local_date.day)
        {
          start_at: day_start.beginning_of_day,
          end_at: day_start.end_of_day
        }
      end

      def load_heartbeats(day_range)
        Heartbeat.where(user_id: @user.id, deleted_at: nil)
                 .where(time: day_range[:start_at].to_i..day_range[:end_at].to_i)
                 .select(
                   :id,
                   :time,
                   :category,
                   :project,
                   :language,
                   :editor,
                   :entity,
                   :is_write,
                   :line_additions,
                   :line_deletions,
                   :source_type
                 )
                 .order(:time)
                 .map do |heartbeat|
          NormalizedHeartbeat.new(
            id: heartbeat.id,
            at: Time.at(heartbeat.time).utc,
            category: heartbeat.category.presence || "coding",
            project: heartbeat.project.presence,
            language: heartbeat.language.presence,
            editor: heartbeat.editor.presence,
            entity: heartbeat.entity.presence,
            is_write: !!heartbeat.is_write,
            line_additions: heartbeat.line_additions.to_i,
            line_deletions: heartbeat.line_deletions.to_i,
            source_type: heartbeat.source_type
          )
        end
      end

      def load_commits(day_range)
        Commit.where(user_id: @user.id, created_at: day_range[:start_at]..day_range[:end_at])
              .order(:created_at)
      end

      def build_intervals(heartbeats, reference_now, local_date)
        heartbeats.each_with_index.filter_map do |heartbeat, index|
          next_at = heartbeats[index + 1]&.at
          interval_seconds =
            if next_at
              [ [ next_at.to_i - heartbeat.at.to_i, 0 ].max, Constants::MAX_HEARTBEAT_GAP_SECONDS ].min
            elsif reference_now.to_date == local_date
              [ [ reference_now.to_i - heartbeat.at.to_i, 0 ].max, Constants::MAX_HEARTBEAT_GAP_SECONDS ].min
            else
              0
            end

          next if interval_seconds <= 0

          {
            heartbeat: heartbeat,
            start_at: heartbeat.at,
            end_at: heartbeat.at + interval_seconds.seconds,
            seconds: interval_seconds
          }
        end
      end

      def build_timeline(heartbeats, intervals, window, reference_now, zone, local_date)
        default_start =
          if window
            [ window[:start_at] - 60.minutes, zone.local(local_date.year, local_date.month, local_date.day) ].max
          else
            zone.local(local_date.year, local_date.month, local_date.day)
          end
        default_end =
          if window
            [ window[:end_at] + 60.minutes, reference_now ].min
          else
            reference_now
          end

        earliest = [ default_start, heartbeats.first&.at&.in_time_zone(zone) || default_start ].min
        latest = [ default_end, heartbeats.last&.at&.in_time_zone(zone) || default_end ].max
        bucket_start = floor_bucket(earliest)
        bucket_end = ceil_bucket([ latest, reference_now ].max)
        bucket_count = [ (((bucket_end - bucket_start) / Constants::BUCKET_SIZE_MINUTES.minutes).to_i + 1), 1 ].max

        buckets = Array.new(bucket_count) do |index|
          started_at = bucket_start + (index * Constants::BUCKET_SIZE_MINUTES.minutes)
          {
            bucket_started_at: started_at.iso8601,
            status: bucket_status(started_at, heartbeats),
            in_window: window.present? && started_at >= window[:start_at] && started_at < window[:end_at],
            presence_seconds: 0,
            coding_seconds: 0,
            write_heartbeats_count: 0,
            line_additions: 0,
            line_deletions: 0,
            categories: Hash.new(0),
            projects: [],
            languages: [],
            language_breakdown: []
          }
        end

        buckets.each_with_index do |bucket, index|
          bucket_range_start = bucket_start + (index * Constants::BUCKET_SIZE_MINUTES.minutes)
          bucket_range_end = bucket_range_start + Constants::BUCKET_SIZE_MINUTES.minutes
          language_stats = Hash.new { |hash, key| hash[key] = empty_language_stat(key) }

          intervals.each do |interval|
            overlap = overlap_seconds(interval[:start_at], interval[:end_at], bucket_range_start, bucket_range_end)
            next if overlap <= 0

            bucket[:presence_seconds] += overlap
            next unless coding_interval?(interval[:heartbeat])

            bucket[:coding_seconds] += overlap
            language_stats[bucket_language(interval[:heartbeat])][:coding_seconds] += overlap
          end

          heartbeats_in_bucket = heartbeats.select { |heartbeat| heartbeat.at >= bucket_range_start && heartbeat.at < bucket_range_end }
          heartbeats_in_bucket.each do |heartbeat|
            bucket[:write_heartbeats_count] += 1 if heartbeat.is_write
            bucket[:line_additions] += heartbeat.line_additions.to_i
            bucket[:line_deletions] += heartbeat.line_deletions.to_i
            bucket[:categories][heartbeat.category] += 1
            bucket[:projects] << heartbeat.project if heartbeat.project.present?

            next unless heartbeat.line_additions.to_i.positive? || heartbeat.line_deletions.to_i.positive?

            stat = language_stats[bucket_language(heartbeat)]
            stat[:line_additions] += heartbeat.line_additions.to_i
            stat[:line_deletions] += heartbeat.line_deletions.to_i
          end

          bucket[:projects] = bucket[:projects].uniq
          bucket[:categories] = bucket[:categories].to_h
          bucket[:language_breakdown] = sort_language_breakdown(language_stats)
          bucket[:languages] = bucket[:language_breakdown].map { |stat| stat[:language] }
        end

        {
          buckets: buckets
        }
      end

      def build_sessions(heartbeats, intervals)
        return [] if heartbeats.empty?

        interval_lookup = intervals.index_by { |interval| interval[:heartbeat].id }
        sessions = []
        current_session = nil
        previous_heartbeat = nil

        heartbeats.each do |heartbeat|
          if current_session.nil? || (previous_heartbeat && heartbeat.at.to_i - previous_heartbeat.at.to_i > Constants::SESSION_TIMEOUT_MINUTES.minutes)
            sessions << current_session if current_session
            current_session = new_session_payload(heartbeat, interval_lookup[heartbeat.id])
          else
            extend_session_payload(current_session, heartbeat, interval_lookup[heartbeat.id])
          end

          previous_heartbeat = heartbeat
        end

        sessions << current_session if current_session

        sessions.map do |session|
          session.merge(
            start_at: session[:start_at].iso8601,
            end_at: session[:end_at].iso8601,
            duration_seconds: [ session[:duration_seconds].to_i, 0 ].max
          )
        end
      end

      def new_session_payload(heartbeat, interval)
        {
          start_at: heartbeat.at,
          end_at: interval ? interval[:end_at] : heartbeat.at,
          duration_seconds: interval ? interval[:seconds].to_i : 0,
          files: heartbeat.entity.present? ? [ File.basename(heartbeat.entity) ] : [],
          projects: heartbeat.project.present? ? [ heartbeat.project ] : [],
          languages: heartbeat.language.present? ? [ heartbeat.language ] : [],
          editors: heartbeat.editor.present? ? [ heartbeat.editor ] : []
        }
      end

      def extend_session_payload(session, heartbeat, interval)
        session[:end_at] = [ session[:end_at], interval ? interval[:end_at] : heartbeat.at ].max
        session[:duration_seconds] += interval ? interval[:seconds].to_i : 0
        session[:files] << File.basename(heartbeat.entity) if heartbeat.entity.present?
        session[:projects] << heartbeat.project if heartbeat.project.present?
        session[:languages] << heartbeat.language if heartbeat.language.present?
        session[:editors] << heartbeat.editor if heartbeat.editor.present?
        session[:files].uniq!
        session[:projects].uniq!
        session[:languages].uniq!
        session[:editors].uniq!
      end

      def ranked_mix(intervals, attribute)
        intervals.each_with_object(Hash.new(0)) do |interval, totals|
          value = interval[:heartbeat].public_send(attribute).presence
          next unless value

          totals[value] += interval[:seconds].to_i
        end.sort_by { |(name, seconds)| [ -seconds, name ] }
          .map { |name, seconds| { name: name, seconds: seconds } }
      end

      def gap_count_for(heartbeats)
        return 0 if heartbeats.length < 2

        heartbeats.each_cons(2).count do |left, right|
          right.at.to_i - left.at.to_i > Constants::IDLE_WINDOW_MINUTES.minutes
        end
      end

      def commit_marker(commit)
        raw = commit.github_raw || {}
        timestamp =
          if raw.dig("commit", "committer", "date").present?
            Time.zone.parse(raw.dig("commit", "committer", "date")).utc
          else
            commit.created_at.utc
          end

        {
          sha: commit.sha,
          timestamp: timestamp.iso8601,
          additions: raw.dig("stats", "additions").to_i,
          deletions: raw.dig("stats", "deletions").to_i,
          github_url: raw["html_url"]
        }
      end

      def coverage_percent_for(intervals, window, reference_now)
        return 0.0 unless window

        elapsed_window_end = [ reference_now, window[:end_at] ].min
        scheduled_seconds = [ (elapsed_window_end - window[:start_at]).to_i, 0 ].max
        return 0.0 if scheduled_seconds <= 0

        presence_in_window = intervals.sum { |interval|
          overlap_seconds(interval[:start_at], interval[:end_at], window[:start_at], elapsed_window_end)
        }

        ((presence_in_window.to_f / scheduled_seconds) * 100).round(2)
      end

      def status_at(window:, first_seen_at:, last_seen_at:, reference_time:, profile:)
        return status_from_last_seen(last_seen_at, reference_time) unless window

        return "before_start" if reference_time < (window[:start_at] - profile.start_grace_minutes.minutes)
        return "after_end" if reference_time > (window[:end_at] + profile.end_grace_minutes.minutes)

        if first_seen_at.nil? || first_seen_at > (window[:start_at] + profile.start_grace_minutes.minutes)
          return "before_start" if reference_time <= (window[:start_at] + profile.start_grace_minutes.minutes)
        end

        status_from_last_seen(last_seen_at, reference_time)
      end

      def status_from_last_seen(last_seen_at, reference_time)
        return "inactive" unless last_seen_at

        gap_minutes = [ ((reference_time.to_i - last_seen_at.to_i) / 60.0), 0 ].max
        return "active" if gap_minutes <= Constants::ACTIVE_WINDOW_MINUTES
        return "idle" if gap_minutes <= Constants::IDLE_WINDOW_MINUTES

        "inactive"
      end

      def not_started_yet?(window, first_seen_at, reference_now, profile)
        return false unless window
        return false if reference_now < window[:start_at]

        first_seen_at.nil? || first_seen_at > (window[:start_at] + profile.start_grace_minutes.minutes)
      end

      def ended_early?(window, last_seen_at, reference_now, profile)
        return false unless window
        return false if reference_now < (window[:end_at] - profile.end_grace_minutes.minutes)
        return false unless last_seen_at

        last_seen_at < (window[:end_at] - profile.end_grace_minutes.minutes)
      end

      def after_hours_active?(window, last_seen_at, reference_now, profile)
        return false unless last_seen_at

        gap_minutes = ((reference_now.to_i - last_seen_at.to_i) / 60.0)
        return false if gap_minutes > Constants::IDLE_WINDOW_MINUTES

        return true unless window

        last_seen_at < (window[:start_at] - profile.start_grace_minutes.minutes) ||
          last_seen_at > (window[:end_at] + profile.end_grace_minutes.minutes)
      end

      def attendance_signal_for(status, not_started_yet, ended_early, first_seen_at, window, profile)
        return "in_progress" unless window
        return "not_started" if not_started_yet && first_seen_at.nil?
        return "ended_early" if ended_early
        return "late_start" if first_seen_at && first_seen_at > (window[:start_at] + profile.start_grace_minutes.minutes)
        return "completed" if status == "after_end"

        "on_track"
      end

      def activity_signal_for(intervals, coverage_percent, write_heartbeats)
        coding_seconds = intervals.sum { |interval| coding_interval?(interval[:heartbeat]) ? interval[:seconds].to_i : 0 }
        return "high" if coding_seconds >= 3.hours.to_i || coverage_percent >= 75 || write_heartbeats >= 24
        return "medium" if coding_seconds >= 90.minutes.to_i || coverage_percent >= 40 || write_heartbeats >= 8

        "low"
      end

      def delivery_signal_for(commits, write_heartbeats, additions, deletions)
        return "strong" if commits.length >= 3 || (additions + deletions) >= 250 || write_heartbeats >= 30
        return "steady" if commits.any? || (additions + deletions) >= 75 || write_heartbeats >= 10

        "quiet"
      end

      def ai_signal_for(heartbeats:, write_heartbeats:, commit_additions:, commit_deletions:)
        heartbeat_lines = heartbeats.sum { |heartbeat| heartbeat.line_additions + heartbeat.line_deletions }
        changed_lines = heartbeat_lines + commit_additions + commit_deletions
        ai_coding_heartbeats = heartbeats.count { |heartbeat| heartbeat.category == "ai coding" }
        ratio = changed_lines.to_f / [ write_heartbeats, 1 ].max
        confidence = [ [ write_heartbeats / 20.0, 1.0 ].min, [ changed_lines / 400.0, 1.0 ].min ].min.round(2)

        level =
          if write_heartbeats < 5 || changed_lines < 80
            "insufficient"
          elsif ai_coding_heartbeats.positive? || ratio >= 80
            "high"
          elsif ratio >= 45
            "moderate"
          else
            "low"
          end

        reason =
          if level == "insufficient"
            "Not enough write activity yet to infer an AI-assisted pattern."
          elsif ai_coding_heartbeats.positive?
            "Detected heartbeats explicitly labeled as AI coding plus elevated line churn."
          else
            "Derived from changed lines per write heartbeat and commit churn. Treat as directional only."
          end

        {
          level: level,
          ratio: ratio.round(2),
          confidence: confidence,
          reason: reason
        }
      end

      def bucket_status(bucket_started_at, heartbeats)
        bucket_end = bucket_started_at + Constants::BUCKET_SIZE_MINUTES.minutes

        last_seen = heartbeats.reverse.find { |heartbeat| heartbeat.at <= bucket_end }&.at
        status_from_last_seen(last_seen, bucket_end)
      end

      def overlap_seconds(left_start, left_end, right_start, right_end)
        return 0 unless left_start && left_end && right_start && right_end

        [ [ left_end, right_end ].min.to_i - [ left_start, right_start ].max.to_i, 0 ].max
      end

      def coding_interval?(heartbeat)
        heartbeat.category.in?([ "coding", "ai coding" ])
      end

      def delta_minutes(actual_time, expected_time)
        return nil unless actual_time && expected_time

        ((actual_time.to_i - expected_time.to_i) / 60.0).round
      end

      def empty_language_stat(language)
        {
          language: language,
          coding_seconds: 0,
          line_additions: 0,
          line_deletions: 0
        }
      end

      def bucket_language(heartbeat)
        heartbeat.language.presence || "Unknown"
      end

      def sort_language_breakdown(language_stats)
        language_stats.values
                      .select do |stat|
                        stat[:coding_seconds].positive? || stat[:line_additions].positive? || stat[:line_deletions].positive?
                      end
                      .sort_by do |stat|
                        [
                          -stat[:coding_seconds].to_i,
                          -(stat[:line_additions].to_i + stat[:line_deletions].to_i),
                          stat[:language]
                        ]
                      end
      end

      def floor_bucket(time)
        minute = (time.min / Constants::BUCKET_SIZE_MINUTES) * Constants::BUCKET_SIZE_MINUTES
        time.change(min: minute, sec: 0)
      end

      def ceil_bucket(time)
        floored = floor_bucket(time)
        floored == time.change(sec: 0) ? floored : floored + Constants::BUCKET_SIZE_MINUTES.minutes
      end

      def persist!(payload)
        profile = EmployeeMonitoringProfile.for_user(@user)
        rollup = EmployeeMonitoringDailyRollup.find_or_initialize_by(user: @user, local_date: Date.iso8601(payload[:local_date]))
        rollup.assign_attributes(
          timezone: payload[:timezone],
          scheduled_start_at: payload[:expected_start_at],
          scheduled_end_at: payload[:expected_end_at],
          first_seen_at: payload[:first_seen_at],
          last_seen_at: payload[:last_seen_at],
          status: payload[:status],
          not_started_yet: payload[:not_started_yet],
          ended_early: payload[:ended_early],
          after_hours_active: payload[:after_hours_active],
          presence_seconds: payload[:presence_seconds],
          coding_seconds: payload[:coding_seconds],
          write_heartbeats_count: payload[:write_heartbeats_count],
          unique_files_count: payload[:unique_files_count],
          unique_projects_count: payload[:unique_projects_count],
          unique_languages_count: payload[:unique_languages_count],
          session_count: payload[:session_count],
          gap_count: payload[:gap_count],
          active_bucket_count: payload[:active_bucket_count],
          idle_bucket_count: payload[:idle_bucket_count],
          coverage_percent: payload[:coverage_percent],
          commit_count: payload[:commit_count],
          commit_line_additions: payload[:commit_line_additions],
          commit_line_deletions: payload[:commit_line_deletions],
          attendance_signal: payload[:attendance_signal],
          activity_signal: payload[:activity_signal],
          delivery_signal: payload[:delivery_signal],
          ai_assisted_output_level: payload[:ai_assisted_output_level],
          ai_assisted_output_ratio: payload[:ai_assisted_output_ratio],
          ai_assisted_output_confidence: payload[:ai_assisted_output_confidence],
          ai_assisted_output_reason: payload[:ai_assisted_output_reason],
          project_mix: payload[:project_mix],
          language_mix: payload[:language_mix],
          editor_mix: payload[:editor_mix],
          commit_markers: payload[:commit_markers],
          session_spans: payload[:session_spans],
          timeline_buckets: payload[:timeline_buckets]
        )
        rollup.save!

        current_bucket = payload[:timeline_buckets].find do |bucket|
          bucket_started_at = Time.iso8601(bucket[:bucket_started_at])
          bucket_started_at <= @now && @now < (bucket_started_at + Constants::BUCKET_SIZE_MINUTES.minutes)
        end
        return unless current_bucket

        snapshot = EmployeeMonitoringIntervalSnapshot.find_or_initialize_by(
          user: @user,
          bucket_started_at: current_bucket[:bucket_started_at]
        )
        snapshot.assign_attributes(
          local_date: payload[:local_date],
          timezone: payload[:timezone],
          status: current_bucket[:status],
          in_window: current_bucket[:in_window],
          presence_seconds: current_bucket[:presence_seconds],
          coding_seconds: current_bucket[:coding_seconds],
          write_heartbeats_count: current_bucket[:write_heartbeats_count],
          line_additions: current_bucket[:line_additions],
          line_deletions: current_bucket[:line_deletions],
          categories: current_bucket[:categories],
          projects: current_bucket[:projects],
          languages: current_bucket[:languages],
          language_breakdown: current_bucket[:language_breakdown]
        )
        snapshot.save!

        profile.save! if profile.new_record?
      end
    end
  end
end
