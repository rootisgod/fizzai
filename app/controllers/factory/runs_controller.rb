class Factory::RunsController < ApplicationController
  before_action :ensure_admin, only: :index
  before_action :set_run, only: :show

  def index
    @runs = Current.account.factory_runs.ordered.includes(:card, :profile, :runner)
    @profiles = Current.account.factory_profiles.active.ordered
    @runners = Current.account.factory_runners.ordered
  end

  def show
    Current.user.accessible_cards.find(@run.card_id)
  end

  def create
    card = Current.user.accessible_cards.find(params[:card_id])
    head :forbidden and return unless Current.user.can_administer_card?(card)

    profile = Current.account.factory_profiles.active.find(params[:profile_id])
    run = Factory::Run.queue_for(card: card, profile: profile, requester: Current.user)

    respond_to do |format|
      format.html { redirect_to factory_run_path(run), notice: "Factory run queued" }
      format.json { render json: run_payload(run), status: :created }
    end
  end

  private
    def set_run
      @run = Current.account.factory_runs.includes(:card, :profile, :runner, logs: []).find(params[:id])
    end

    def run_payload(run)
      {
        id: run.id,
        state: run.state,
        card_id: run.card_id,
        profile_id: run.profile_id,
        branch_name: run.branch_name,
        max_attempts: run.max_attempts,
        max_iterations: run.max_iterations,
        verification_command: run.verification_command
      }
    end
end
