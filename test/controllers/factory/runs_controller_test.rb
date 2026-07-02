require "test_helper"

class Factory::RunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :kevin
  end

  test "admin can queue a factory run for an accessible card" do
    assert_difference -> { Factory::Run.count }, 1 do
      post factory_runs_path, params: {
        card_id: cards(:text).id,
        profile_id: factory_profiles(:codex_local).id
      }
    end

    run = Factory::Run.order(:created_at).last

    assert_redirected_to factory_run_path(run)
    assert_equal "queued", run.state
  end

  test "member cannot queue a factory run on another creator's card" do
    logout_and_sign_in_as :jz

    assert_no_difference -> { Factory::Run.count } do
      post factory_runs_path, params: {
        card_id: cards(:text).id,
        profile_id: factory_profiles(:codex_local).id
      }
    end

    assert_response :forbidden
  end
end
