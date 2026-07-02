class Factory::RunnerApi::Runs::LogsController < Factory::RunnerApi::BaseController
  before_action :set_run

  def create
    log = @run.add_log!(
      stream: params[:stream].presence || "agent",
      content: params[:content],
      sequence: params[:sequence]
    )

    render json: { id: log.id, sequence: log.sequence }, status: :created
  end
end
