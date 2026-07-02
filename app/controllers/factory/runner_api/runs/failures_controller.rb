class Factory::RunnerApi::Runs::FailuresController < Factory::RunnerApi::BaseController
  before_action :set_run

  def create
    @run.fail_by!(
      current_factory_runner,
      failure_reason: params[:failure_reason].presence || "Runner failed",
      metadata: params[:metadata]
    )

    render json: run_status_payload(@run)
  end
end
