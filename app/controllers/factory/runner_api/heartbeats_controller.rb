class Factory::RunnerApi::HeartbeatsController < Factory::RunnerApi::BaseController
  def create
    current_factory_runner.heartbeat!(metadata: params[:metadata])
    render json: { ok: true, last_seen_at: current_factory_runner.last_seen_at.utc.iso8601 }
  end
end
