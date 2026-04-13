require "test_helper"

class Api::Hackatime::V1::HackatimeControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs
  end

  teardown do
    ActiveJob::Base.queue_adapter = @original_queue_adapter
  end

  test "single text plain heartbeat normalizes hash payloads" do
    user = User.create!(timezone: "UTC")
    api_key = user.api_keys.create!(name: "primary")

    payload = {
      entity: "src/main.rb",
      plugin: "vscode/1.0.0",
      project: "hackatime",
      time: Time.current.to_f,
      type: "file"
    }

    assert_difference("Heartbeat.count", 1) do
      post "/api/hackatime/v1/users/current/heartbeats",
        params: payload.to_json,
        headers: {
          "Authorization" => "Bearer #{api_key.token}",
          "CONTENT_TYPE" => "text/plain"
        }
    end

    assert_response :accepted
    heartbeat = Heartbeat.order(:id).last
    assert_equal user.id, heartbeat.user_id
    assert_equal "vscode/1.0.0", heartbeat.user_agent
    assert_equal "coding", heartbeat.category
  end

  test "single heartbeat resolves <<LAST_LANGUAGE>> from existing heartbeats" do
    user = User.create!(timezone: "UTC")
    api_key = user.api_keys.create!(name: "primary")
    # Seed a prior heartbeat with a known language
    user.heartbeats.create!(
      entity: "src/old.rb",
      type: "file",
      category: "coding",
      time: 1.hour.ago.to_f,
      language: "Ruby",
      source_type: :direct_entry
    )

    payload = {
      entity: "src/main.rb",
      plugin: "vscode/1.0.0",
      project: "hackatime",
      time: Time.current.to_f,
      type: "file",
      language: "<<LAST_LANGUAGE>>"
    }

    assert_difference("Heartbeat.count", 1) do
      post "/api/hackatime/v1/users/current/heartbeats",
        params: payload.to_json,
        headers: {
          "Authorization" => "Bearer #{api_key.token}",
          "CONTENT_TYPE" => "text/plain"
        }
    end

    assert_response :accepted
    heartbeat = Heartbeat.order(:id).last
    assert_equal "Ruby", heartbeat.language
  end

  test "bulk heartbeat resolves <<LAST_LANGUAGE>> from previous heartbeat in same batch" do
    user = User.create!(timezone: "UTC")
    api_key = user.api_keys.create!(name: "primary")

    now = Time.current.to_f
    payload = [
      {
        entity: "src/first.rb",
        plugin: "vscode/1.0.0",
        project: "hackatime",
        time: now - 2,
        type: "file",
        language: "Python"
      },
      {
        entity: "src/second.rb",
        plugin: "vscode/1.0.0",
        project: "hackatime",
        time: now - 1,
        type: "file",
        language: "<<LAST_LANGUAGE>>"
      }
    ]

    assert_difference("Heartbeat.count", 2) do
      post "/api/hackatime/v1/users/current/heartbeats.bulk",
        params: payload.to_json,
        headers: {
          "Authorization" => "Bearer #{api_key.token}",
          "CONTENT_TYPE" => "application/json"
        }
    end

    assert_response :created
    heartbeats = Heartbeat.order(:id).last(2)
    assert_equal "Python", heartbeats.first.language
    assert_equal "Python", heartbeats.last.language
  end

  test "single heartbeat with <<LAST_LANGUAGE>> and no prior heartbeats infers language from extension" do
    user = User.create!(timezone: "UTC")
    api_key = user.api_keys.create!(name: "primary")

    payload = {
      entity: "src/main.rb",
      plugin: "vscode/1.0.0",
      project: "hackatime",
      time: Time.current.to_f,
      type: "file",
      language: "<<LAST_LANGUAGE>>"
    }

    assert_difference("Heartbeat.count", 1) do
      post "/api/hackatime/v1/users/current/heartbeats",
        params: payload.to_json,
        headers: {
          "Authorization" => "Bearer #{api_key.token}",
          "CONTENT_TYPE" => "text/plain"
        }
    end

    assert_response :accepted
    heartbeat = Heartbeat.order(:id).last
    assert_equal "Ruby", heartbeat.language
  end

  test "bulk heartbeat normalizes permitted params" do
    user = User.create!(timezone: "UTC")
    api_key = user.api_keys.create!(name: "primary")

    payload = [ {
      entity: "src/main.rb",
      plugin: "zed/1.0.0",
      project: "hackatime",
      time: Time.current.to_f,
      type: "file"
    } ]

    assert_difference("Heartbeat.count", 1) do
      post "/api/hackatime/v1/users/current/heartbeats.bulk",
        params: payload.to_json,
        headers: {
          "Authorization" => "Bearer #{api_key.token}",
          "CONTENT_TYPE" => "application/json"
        }
    end

    assert_response :created
    heartbeat = Heartbeat.order(:id).last
    assert_equal user.id, heartbeat.user_id
    assert_equal "zed/1.0.0", heartbeat.user_agent
    assert_equal "coding", heartbeat.category
  end

  test "heartbeat enqueues commit pull when an active repo mapping exists" do
    user = User.create!(timezone: "UTC", github_username: "alexb", github_access_token: "github-token")
    api_key = user.api_keys.create!(name: "primary")
    repository = Repository.find_or_create_by_url("https://github.com/Safari-Expert/internal_ui")
    mapping = user.project_repo_mappings.create!(project_name: "internal_ui")
    mapping.update_columns(repo_url: repository.url, repository_id: repository.id)

    payload = {
      entity: "src/main.rb",
      plugin: "vscode/1.0.0",
      project: "internal_ui",
      time: Time.current.to_f,
      type: "file"
    }

    with_memory_cache_store do
      assert_enqueued_with(job: PullRepoCommitsJob, args: [ user.id, "Safari-Expert", "internal_ui" ]) do
        post "/api/hackatime/v1/users/current/heartbeats",
          params: payload.to_json,
          headers: {
            "Authorization" => "Bearer #{api_key.token}",
            "CONTENT_TYPE" => "text/plain"
          }
      end
    end

    assert_response :accepted
  end

  test "heartbeat throttles repeated commit pull enqueueing for the same mapped repo" do
    user = User.create!(timezone: "UTC", github_username: "alexb", github_access_token: "github-token")
    api_key = user.api_keys.create!(name: "primary")
    repository = Repository.find_or_create_by_url("https://github.com/Safari-Expert/internal_ui")
    mapping = user.project_repo_mappings.create!(project_name: "internal_ui")
    mapping.update_columns(repo_url: repository.url, repository_id: repository.id)

    payload = {
      entity: "src/main.rb",
      plugin: "vscode/1.0.0",
      project: "internal_ui",
      time: Time.current.to_f,
      type: "file"
    }

    with_memory_cache_store do
      post "/api/hackatime/v1/users/current/heartbeats",
        params: payload.to_json,
        headers: {
          "Authorization" => "Bearer #{api_key.token}",
          "CONTENT_TYPE" => "text/plain"
        }
      post "/api/hackatime/v1/users/current/heartbeats",
        params: payload.merge(time: Time.current.to_f + 1).to_json,
        headers: {
          "Authorization" => "Bearer #{api_key.token}",
          "CONTENT_TYPE" => "text/plain"
        }
    end

    pull_jobs = enqueued_jobs.select { |job| job[:job] == PullRepoCommitsJob }
    assert_equal 1, pull_jobs.length
  end

  private

  def with_memory_cache_store
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache.lookup_store(:memory_store)
    yield
  ensure
    Rails.cache = original_cache
  end
end
