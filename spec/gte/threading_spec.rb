# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Threading and GVL release', if: GTE_E5_AVAILABLE do
  let(:pool) { GTE.config(GTE_E5_DIR) }
  let(:text) { 'query: cat' }

  def time_concurrent(model, threads, calls_per_thread)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    workers = Array.new(threads) do
      Thread.new { calls_per_thread.times { model.embed_binary(text) } }
    end
    workers.each(&:join)
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  end

  it 'releases GVL: background Ruby thread makes progress during inference' do
    10.times { pool.embed_binary(text) }

    stop = false
    counter = 0
    spinner = Thread.new do
      until stop
        counter += 1
        Thread.pass
      end
    end

    50.times { pool.embed_binary(text) }
    stop = true
    spinner.join

    expect(counter).to be > 100, "spinner advanced #{counter}× — GVL likely held"
  end
end
