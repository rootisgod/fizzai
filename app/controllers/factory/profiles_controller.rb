class Factory::ProfilesController < ApplicationController
  before_action :ensure_admin
  before_action :set_profile, only: %i[ show edit update destroy ]

  def index
    @profiles = Current.account.factory_profiles.ordered.includes(:skills)
  end

  def show
  end

  def new
    @profile = Current.account.factory_profiles.new
  end

  def create
    @profile = Current.account.factory_profiles.new
    assign_profile_attributes

    if @profile.save
      redirect_to factory_profile_path(@profile)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    assign_profile_attributes

    if @profile.save
      redirect_to factory_profile_path(@profile)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @profile.update!(active: false)
    redirect_to factory_profiles_path
  end

  private
    def set_profile
      @profile = Current.account.factory_profiles.find(params[:id])
    end

    def assign_profile_attributes
      attributes = profile_params.to_h
      skill_ids = Array(attributes.delete("skill_ids")).compact_blank

      @profile.assign_attributes(attributes)
      @profile.skills = Current.account.factory_skills.where(id: skill_ids)
    end

    def profile_params
      params.expect(factory_profile: [
        :name, :description, :brain_provider, :brain_model, :prompt, :runner_kind, :active,
        :verification_command, :max_iterations, :max_attempts, skill_ids: []
      ])
    end
end
