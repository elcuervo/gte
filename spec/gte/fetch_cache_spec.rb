# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'GTE model cache', if: GTE_E5_AVAILABLE do
  let(:dir) { GTE_E5_DIR }

  def build_model(model_dir, **overrides)
    GTE.config(model_dir) do |config|
      overrides.empty? ? config : config.with(**overrides)
    end
  end

  it 'returns the same model instance for identical arguments via GTE.config' do
    a = build_model(dir)
    b = build_model(dir)
    expect(a.object_id).to eq(b.object_id)
  end

  it 'returns one shared instance across concurrent constructor calls' do
    ids = Array.new(16)
    threads = 16.times.map do |idx|
      Thread.new { ids[idx] = build_model(dir).object_id }
    end
    threads.each(&:join)
    expect(ids.uniq.length).to eq(1)
  end

  it 'uses independent cache entries when parameters differ' do
    a = build_model(dir, threads: 1)
    b = build_model(dir, threads: 2)
    expect(a.object_id).not_to eq(b.object_id)
  end

  it 'accepts 0 threads for full-throttle mode as a separate cache key' do
    default_model = build_model(dir)
    full_throttle = build_model(dir, threads: 0)
    expect(default_model.object_id).not_to eq(full_throttle.object_id)
  end

  it 'uses independent cache entries when normalize differs' do
    normalized = build_model(dir, normalize: true)
    raw = build_model(dir, normalize: false)
    expect(normalized.object_id).not_to eq(raw.object_id)
  end

  it 'uses independent cache entries when output_tensor differs' do
    a = build_model(dir)
    b = build_model(dir, output_tensor: 'last_hidden_state')
    expect(a.object_id).not_to eq(b.object_id)
  end

  it 'uses independent cache entries when max_length differs' do
    a = build_model(dir, max_length: 64)
    b = build_model(dir, max_length: 128)
    expect(a.object_id).not_to eq(b.object_id)
  end
end
