class EmbedController < ApplicationController
  def show
    text = params[:text].to_s
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    vector = RUNTIME.embed(text)
    elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(2)

    render json: { runtime: RUNTIME.name, dim: vector.length,
                   ms: elapsed, embedding: vector }
  rescue => e
    render json: { error: e.class.name, message: e.message }, status: 500
  end
end
