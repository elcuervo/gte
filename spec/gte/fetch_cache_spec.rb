# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'GTE model cache', if: GTE_E5_AVAILABLE do
  let(:dir) { GTE_E5_DIR }

  it 'returns the same model instance for identical arguments via GTE.new' do
    a = GTE.new(dir)
    b = GTE.new(dir)
    expect(a.object_id).to eq(b.object_id)
  end

  it 'keeps GTE.fetch as alias of GTE.new caching behavior' do
    a = GTE.new(dir)
    b = GTE.fetch(dir)
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
end
