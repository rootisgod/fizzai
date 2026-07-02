class Factory::RunnerApi::Runs::BlocksController < Factory::RunnerApi::BaseController
  before_action :set_run

  def create
    @run.block_by!(
      current_factory_runner,
      block_reason: params[:block_reason].presence || "Runner blocked",
      metadata: params[:metadata]
    )

    render json: run_status_payload(@run)
  end
end
