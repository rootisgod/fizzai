class Factory::RunnerApi::Runs::HeartbeatsController < Factory::RunnerApi::BaseController
  before_action :set_run

  def create
    @run.heartbeat_by!(current_factory_runner, metadata: params[:metadata])
    render json: run_status_payload(@run)
  end
end
