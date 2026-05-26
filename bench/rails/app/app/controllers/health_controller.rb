class HealthController < ApplicationController
  def show
    render json: { status: "ok", runtime: RUNTIME.name }
  end
end
