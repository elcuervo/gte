# frozen_string_literal: true

require "spec_helper"

RSpec.describe "GTE::E5" do
  describe "class structure" do
    it "exists as a Ruby class" do
      expect(defined?(GTE::E5)).to eq("constant")
    end

    it "responds to :embed" do
      expect(GTE::E5.instance_methods(false)).to include(:embed)
    end

    it "responds to :embed_query" do
      expect(GTE::E5.instance_methods(false)).to include(:embed_query)
    end

    it "responds to :embed_passage" do
      expect(GTE::E5.instance_methods(false)).to include(:embed_passage)
    end
  end

  context "with real model fixture", if: GTE_FIXTURES_AVAILABLE do
    let(:e5) { GTE::E5.new(model_path: GTE_MODEL_PATH, tokenizer_path: GTE_TOKENIZER_PATH) }
    let(:text) { "test embedding input" }

    describe "#embed" do
      it "returns Array<Array<Float>> for a batch of strings" do
        result = e5.embed(["text one", "text two"])
        expect(result).to be_a(Array)
        expect(result.length).to eq(2)
        result.each { |row| expect(row.first).to be_a(Float) }
      end

      it "accepts a single string wrapped in Array" do
        result = e5.embed([text])
        expect(result).to be_a(Array)
        expect(result.first).to be_a(Array)
      end
    end

    describe "#embed_query (API-04)" do
      it "returns Array<Float> — not Array<Array<Float>>" do
        result = e5.embed_query(text)
        expect(result).to be_a(Array)
        expect(result.first).to be_a(Float)
      end

      it "returns L2-normalized vector (norm ≈ 1.0)" do
        result = e5.embed_query(text)
        norm = Math.sqrt(result.sum { |v| v * v })
        expect(norm).to be_within(1e-3).of(1.0)
      end

      it "produces different embedding than embed without prefix" do
        query_emb = e5.embed_query(text)
        plain_emb = e5.embed([text]).first
        expect(query_emb).not_to eq(plain_emb)
      end
    end

    describe "#embed_passage (API-05)" do
      it "returns Array<Float> — not Array<Array<Float>>" do
        result = e5.embed_passage(text)
        expect(result).to be_a(Array)
        expect(result.first).to be_a(Float)
      end

      it "returns L2-normalized vector (norm ≈ 1.0)" do
        result = e5.embed_passage(text)
        norm = Math.sqrt(result.sum { |v| v * v })
        expect(norm).to be_within(1e-3).of(1.0)
      end

      it "produces different embedding than embed_query for the same text" do
        query_emb   = e5.embed_query(text)
        passage_emb = e5.embed_passage(text)
        expect(query_emb).not_to eq(passage_emb)
      end
    end
  end

  context "without model fixture", unless: GTE_FIXTURES_AVAILABLE do
    it "fixture tests skipped — set GTE_MODEL_PATH and GTE_TOKENIZER_PATH to enable" do
      skip "Set GTE_MODEL_PATH and GTE_TOKENIZER_PATH environment variables to run fixture-dependent tests"
    end
  end
end
