# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'GTE.config', if: GTE_E5_AVAILABLE do
  let(:dir) { GTE_E5_DIR }

  it 'creates independent models for each config() call' do
    a = GTE.config(dir)
    b = GTE.config(dir)
    expect(a.object_id).not_to eq(b.object_id)
  end

  it 'handles concurrent construction' do
    models = Array.new(16)
    threads = 16.times.map do |idx|
      Thread.new { models[idx] = GTE.config(dir) }
    end
    threads.each(&:join)
    expect(models.uniq.length).to eq(16)
  end

  it 'passes config overrides via block' do
    model = GTE.config(dir) { |c| c.with(execution_providers: 'cpu') }
    expect(model).to be_a(GTE::Model)
    expect(model.embed('test').rows).to eq(1)
  end
end
