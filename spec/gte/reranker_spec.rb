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

    it 'responds to convenience rerank API' do
      expect(GTE::Reranker.instance_methods(false)).to include(:rerank)
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
      reranker = GTE::Reranker.new(GTE_RERANK_DIR, 0, 3, '', false, '', 0)
      scores = reranker.score(query, candidates)

      expect(scores).to be_a(Array)
      expect(scores.length).to eq(candidates.length)
      scores.each { |score| expect(score).to be_a(Float) }
    end

    it 'supports module-level reranker helper and ranked output' do
      reranker = GTE.reranker(GTE_RERANK_DIR, sigmoid: true)
      ranked = reranker.rerank(query: query, candidates: candidates)

      expect(ranked.length).to eq(candidates.length)
      expect(ranked.first).to include(:index, :score, :text)
      expect(ranked.map { |row| row[:score] }).to eq(ranked.map { |row| row[:score] }.sort.reverse)
    end
  end
end
