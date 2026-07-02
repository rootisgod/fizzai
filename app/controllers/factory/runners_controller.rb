class Factory::RunnersController < ApplicationController
  before_action :ensure_admin
  before_action :set_runner, only: %i[ show destroy ]

  def index
    @runners = Current.account.factory_runners.ordered
  end

  def show
  end

  def new
    @runner = Current.account.factory_runners.new(kind: "sandcastle")
  end

  def create
    @runner = Current.account.factory_runners.new(runner_params)

    if @runner.save
      redirect_to factory_runner_path(@runner), notice: "Runner registered"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @runner.update!(active: false)
    redirect_to factory_runners_path
  end

  private
    def set_runner
      @runner = Current.account.factory_runners.find(params[:id])
    end

    def runner_params
      params.expect(factory_runner: %i[ name kind active ])
    end
end
