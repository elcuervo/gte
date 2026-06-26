# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'GTE::Pool', if: GTE_E5_AVAILABLE do
  let(:dir) { GTE_E5_DIR }

  it 'creates independent pools for each new() call' do
    a = GTE::Pool.new(dir)
    b = GTE::Pool.new(dir)
    expect(a.object_id).not_to eq(b.object_id)
  end

  it 'handles concurrent pool construction' do
    pools = Array.new(16)
    threads = 16.times.map do |idx|
      Thread.new { pools[idx] = GTE::Pool.new(dir) }
    end
    threads.each(&:join)
    expect(pools.uniq.length).to eq(16)
  end

  it 'passes config overrides via block' do
    pool = GTE::Pool.new(dir) { |c| c.with(execution_providers: 'cpu') }
    expect(pool).to be_a(GTE::Pool)
    expect(pool.embed('test').rows).to eq(1)
  end

  it 'warmup runs without error' do
    pool = GTE::Pool.new(dir)
    expect { pool.warmup }.not_to raise_error
  end
end
