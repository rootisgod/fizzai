class Factory::RunnerApi::BaseController < ApplicationController
  include Factory::RunnerApiAuthentication

  rescue_from Factory::Run::RunnerMismatch, with: :render_forbidden
  rescue_from ActiveRecord::RecordInvalid, with: :render_unprocessable_entity

  private
    def set_run
      @run = current_factory_runner.account.factory_runs.find(params[:run_id])
    end

    def run_payload(run)
      {
        id: run.id,
        state: run.state,
        branch_name: run.branch_name,
        max_iterations: run.max_iterations,
        verification_command: run.verification_command,
        prompt: run.runner_prompt,
        card: card_payload(run.card),
        profile: profile_payload(run.profile)
      }
    end

    def card_payload(card)
      {
        id: card.id,
        number: card.number,
        title: card.title,
        description: card.description&.to_plain_text.to_s,
        url: card_url(card)
      }
    end

    def profile_payload(profile)
      {
        id: profile.id,
        name: profile.name,
        brain_provider: profile.brain_provider,
        brain_model: profile.brain_model,
        brain_options: profile.brain_options,
        runner_kind: profile.runner_kind,
        skills: profile.skills.active.ordered.map { |skill| skill_payload(skill) }
      }
    end

    def skill_payload(skill)
      {
        id: skill.id,
        name: skill.name,
        description: skill.description,
        instructions: skill.instructions
      }
    end

    def run_status_payload(run)
      {
        id: run.id,
        state: run.state,
        attempts_count: run.attempts_count,
        heartbeat_at: run.heartbeat_at&.utc&.iso8601,
        completed_at: run.completed_at&.utc&.iso8601
      }
    end

    def render_forbidden
      render json: { error: "forbidden" }, status: :forbidden
    end

    def render_unprocessable_entity(error)
      render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
end
