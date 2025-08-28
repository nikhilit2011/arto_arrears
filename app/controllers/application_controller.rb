class ApplicationController < ActionController::Base
  before_action :authenticate_user!, unless: :devise_controller?
  
  private

    def allow_unauthenticated_paths?
      devise_controller? || request.path == "/up"
    end
end
