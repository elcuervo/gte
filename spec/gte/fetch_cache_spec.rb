# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'GTE model cache', if: GTE_E5_AVAILABLE do
  let(:dir) { GTE_E5_DIR }

  it 'returns the same model instance for identical arguments via GTE.new' do
    a = GTE.new(dir)
    b = GTE.new(dir)
    expect(a.object_id).to eq(b.object_id)
  end

  it 'returns one shared instance across concurrent constructor calls' do
    ids = Array.new(16)
    threads = 16.times.map do |idx|
      Thread.new { ids[idx] = GTE.new(dir).object_id }
    end
    threads.each(&:join)
    expect(ids.uniq.length).to eq(1)
  end

  it 'uses independent cache entries when parameters differ' do
    a = GTE.new(dir, num_threads: 1)
    b = GTE.new(dir, num_threads: 2)
    expect(a.object_id).not_to eq(b.object_id)
  end

  it 'uses independent cache entries when normalize differs' do
    normalized = GTE.new(dir, normalize: true)
    raw = GTE.new(dir, normalize: false)
    expect(normalized.object_id).not_to eq(raw.object_id)
  end
end
