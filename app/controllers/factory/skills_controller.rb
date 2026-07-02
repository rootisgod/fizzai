class Factory::SkillsController < ApplicationController
  before_action :ensure_admin
  before_action :set_skill, only: %i[ show edit update destroy ]

  def index
    @skills = Current.account.factory_skills.ordered
  end

  def show
  end

  def new
    @skill = Current.account.factory_skills.new
  end

  def create
    @skill = Current.account.factory_skills.new(skill_params)

    if @skill.save
      redirect_to factory_skill_path(@skill)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @skill.update(skill_params)
      redirect_to factory_skill_path(@skill)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @skill.update!(active: false)
    redirect_to factory_skills_path
  end

  private
    def set_skill
      @skill = Current.account.factory_skills.find(params[:id])
    end

    def skill_params
      params.expect(factory_skill: %i[ name description instructions active ])
    end
end
