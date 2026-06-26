# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'GTE::Reranker' do
  context 'class structure' do
    it 'exists as a Ruby class' do
      expect(defined?(GTE::Reranker)).to eq('constant')
    end

    it 'responds to native score API' do
      expect(GTE::Reranker.instance_methods(false)).to include(:score)
    end

    it 'accepts execution_providers in config without argument errors' do
      expect do
        GTE::Reranker.new('/nonexistent/dir') { |config| config.with(execution_providers: 'cpu') }
      end.to raise_error(GTE::Error)
    end

    it 'rejects unknown keyword pool_size' do
      expect { GTE::Reranker.new('/nonexistent', pool_size: 4) }.to raise_error(ArgumentError)
    end
  end

  context 'with real reranker fixture', if: GTE_RERANK_AVAILABLE do
    let(:query) { 'how to train a neural network?' }
    let(:candidates) do
      [
        'Backpropagation and gradient descent are core techniques.',
        'This recipe uses flour and eggs.'
      ]
    end

    it 'scores query/candidate pairs with one score per candidate' do
      reranker = GTE::Reranker.new(GTE_RERANK_DIR)
      scores = reranker.score(query, candidates)

      expect(scores).to be_a(Array)
      expect(scores.length).to eq(candidates.length)
      scores.each { |score| expect(score).to be_a(Float) }
    end
  end
end
