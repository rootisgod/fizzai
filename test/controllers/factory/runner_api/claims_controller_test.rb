require "test_helper"

class Factory::RunnerApi::ClaimsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @runner = factory_runners(:local)
    @run = Factory::Run.queue_for(card: cards(:text), profile: factory_profiles(:codex_local), requester: users(:kevin))
  end

  test "runner claims the next ready run" do
    post factory_runner_api_claim_path(format: :json), headers: authorization_headers, as: :json

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal @run.id, payload["id"]
    assert_equal "running", @run.reload.state
    assert_equal @runner, @run.runner
    assert_includes payload["prompt"], cards(:text).title
  end

  test "runner token is required" do
    post factory_runner_api_claim_path(format: :json), headers: { "Authorization" => "Bearer nope" }, as: :json

    assert_response :unauthorized
    assert_predicate @run.reload, :queued?
  end

  test "claimed run accepts logs and completion" do
    assert @run.claim_by(@runner)

    assert_difference -> { @run.logs.count }, 1 do
      post factory_runner_api_run_logs_path(@run, format: :json),
        params: { stream: "agent", content: "working" },
        headers: authorization_headers,
        as: :json
    end

    post factory_runner_api_run_completion_path(@run, format: :json),
      params: { summary: "Done", verification_status: "passed", commit_sha: "abc123" },
      headers: authorization_headers,
      as: :json

    assert_response :success
    assert_predicate @run.reload, :completed?
    assert_equal "abc123", @run.commit_sha
  end

  private
    def authorization_headers
      { "Authorization" => "Bearer #{@runner.token}" }
    end
end
