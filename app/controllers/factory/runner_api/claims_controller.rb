class Factory::RunnerApi::ClaimsController < Factory::RunnerApi::BaseController
  def create
    current_factory_runner.heartbeat!(metadata: params[:metadata])

    if run = Factory::Run.claim_next_for(current_factory_runner)
      render json: run_payload(run)
    else
      head :no_content
    end
  end
end
