# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Threading and GVL release', if: GTE_E5_AVAILABLE do
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
    model = GTE.config(GTE_E5_DIR)
    10.times { model.embed_binary(text) }

    stop = false
    counter = 0
    spinner = Thread.new do
      until stop
        counter += 1
        Thread.pass
      end
    end

    50.times { model.embed_binary(text) }
    stop = true
    spinner.join

    # If GVL held during inference, spinner never gets scheduled.
    expect(counter).to be > 100, "spinner advanced #{counter}× — GVL likely held"
  end
end
