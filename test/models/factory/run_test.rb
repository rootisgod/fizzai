require "test_helper"

class Factory::RunTest < ActiveSupport::TestCase
  setup do
    @card = cards(:text)
    @profile = factory_profiles(:codex_local)
    @runner = factory_runners(:local)
  end

  test "queues a card run from profile defaults" do
    run = Factory::Run.queue_for(card: @card, profile: @profile, requester: users(:kevin))

    assert_predicate run, :queued?
    assert_equal @profile.max_attempts, run.max_attempts
    assert_equal @profile.max_iterations, run.max_iterations
    assert_equal @profile.verification_command, run.verification_command
    assert_includes run.runner_prompt, @card.title
    assert_includes run.runner_prompt, @profile.prompt
  end

  test "does not claim runs blocked by parent card dependencies" do
    Factory::CardDependency.add!(child: @card, parent: cards(:logo))
    Factory::Run.queue_for(card: @card, profile: @profile, requester: users(:kevin))

    assert_nil Factory::Run.claim_next_for(@runner)

    cards(:logo).close(user: users(:system))

    assert_equal @card, Factory::Run.claim_next_for(@runner).card
  end

  test "complete marks the run completed and closes the card after passing verification" do
    run = Factory::Run.queue_for(card: @card, profile: @profile, requester: users(:kevin))

    assert run.claim_by(@runner)

    assert_difference -> { @card.comments.count }, 2 do
      run.complete_by!(@runner, summary: "Implemented", verification_status: "passed", commit_sha: "abc123")
    end

    assert_predicate run.reload, :completed?
    assert_equal "abc123", run.commit_sha
    assert_predicate @card.reload, :closed?
  end

  test "failure requeues until attempts are exhausted" do
    run = Factory::Run.queue_for(card: @card, profile: @profile, requester: users(:kevin))

    assert run.claim_by(@runner)
    run.fail_by!(@runner, failure_reason: "Tests failed")

    assert_predicate run.reload, :queued?
    assert_nil run.runner

    assert run.claim_by(@runner)
    run.fail_by!(@runner, failure_reason: "Still failing")

    assert_predicate run.reload, :failed?
    assert_equal "Still failing", run.failure_reason
  end
end
