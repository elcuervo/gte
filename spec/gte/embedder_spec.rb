# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'GTE::Embedder' do
  describe 'class structure' do
    it 'exists as a Ruby class' do
      expect(defined?(GTE::Embedder)).to eq('constant')
    end

    it 'has a .new class method' do
      expect(GTE::Embedder).to respond_to(:new)
    end

    it 'has config helpers' do
      expect(GTE::Embedder).to respond_to(:config)
      expect(GTE::Embedder).to respond_to(:from_config)
    end

    it 'responds to :embed' do
      expect(GTE::Embedder.instance_methods(false)).to include(:embed)
    end

    it 'defines GTE::Tensor' do
      expect(defined?(GTE::Tensor)).to eq('constant')
    end
  end

  describe 'GTE::Error' do
    it 'is a subclass of StandardError (not RuntimeError)' do
      expect(GTE::Error.ancestors).to include(StandardError)
      expect(GTE::Error.superclass).to eq(StandardError)
    end
  end

  describe 'config helpers with invalid directory' do
    it 'raises GTE::Error when directory does not contain model' do
      expect do
        GTE::Embedder.config('/nonexistent/dir')
      end.to raise_error(GTE::Error)
    end
  end

  context 'with real model fixture', if: GTE_FIXTURES_AVAILABLE do
    let(:embedder) { GTE::Embedder.config(GTE_E5_DIR) }
    let(:sample_texts) { ['Hello world', 'The quick brown fox'] }
    let(:single_text)  { ['Hello world'] }

    describe 'return structure' do
      it 'returns GTE::Tensor for a batch' do
        result = embedder.embed(sample_texts)
        expect(result).to be_a(GTE::Tensor)
        expect(result.rows).to eq(sample_texts.length)
        expect(result.dim).to eq(GTE_EMBEDDING_DIM)
        result.to_a.each do |row|
          expect(row).to be_a(Array)
          expect(row).not_to be_empty
        end
      end

      it "returns the expected embedding dimension (#{GTE_EMBEDDING_DIM})" do
        result = embedder.embed(single_text)
        expect(result.dim).to eq(GTE_EMBEDDING_DIM)
      end

      it 'supports binary row extraction for fast transfer' do
        result = embedder.embed(single_text)
        bytes = result.row_binary_f32(0)
        expect(bytes).to be_a(String)
        expect(bytes.bytesize).to eq(GTE_EMBEDDING_DIM * 4)
      end
    end

    describe 'output validity' do
      it 'contains only valid floats — no NaN values' do
        result = embedder.embed(sample_texts).to_a
        result.each { |row| row.each { |val| expect(val).not_to be_nan } }
      end

      it 'contains only valid floats — no Inf values' do
        result = embedder.embed(sample_texts).to_a
        result.each { |row| row.each { |val| expect(val.infinite?).to be_nil } }
      end
    end

    describe 'L2 normalization' do
      it 'returns L2-normalized vectors: norm of each row is approximately 1.0' do
        result = embedder.embed(sample_texts).to_a
        result.each_with_index do |row, i|
          l2_norm = Math.sqrt(row.sum { |v| v * v })
          expect(l2_norm).to be_within(1e-3).of(1.0),
                             "row #{i}: expected L2 norm ≈ 1.0, got #{l2_norm}"
        end
      end
    end

    describe 'E5 prefix semantics' do
      it 'query-prefixed text produces different embedding than plain text' do
        query_emb = embedder.embed(['query: machine learning']).row(0)
        plain_emb = embedder.embed(['machine learning']).row(0)
        expect(query_emb).not_to eq(plain_emb)
      end
    end
  end
end
