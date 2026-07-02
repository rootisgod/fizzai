class Factory::RunnerApi::Runs::CompletionsController < Factory::RunnerApi::BaseController
  before_action :set_run

  def create
    @run.complete_by!(
      current_factory_runner,
      summary: params[:summary].presence || "Completed",
      commit_sha: params[:commit_sha],
      branch_name: params[:branch_name],
      verification_status: params[:verification_status],
      metadata: params[:metadata]
    )

    render json: run_status_payload(@run)
  end
end
