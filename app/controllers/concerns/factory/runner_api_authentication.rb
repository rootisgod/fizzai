module Factory::RunnerApiAuthentication
  extend ActiveSupport::Concern

  included do
    allow_unauthenticated_access
    before_action :require_factory_runner
  end

  private
    attr_reader :current_factory_runner

    def require_factory_runner
      @current_factory_runner = Current.account.factory_runners.active.find_by(token: bearer_token)

      unless current_factory_runner
        render json: { error: "unauthorized" }, status: :unauthorized
      end
    end

    def bearer_token
      request.authorization.to_s[/\ABearer\s+(.+)\z/, 1]&.strip
    end
end
