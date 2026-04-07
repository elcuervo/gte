# frozen_string_literal: true

require "spec_helper"

RSpec.describe "GTE::Siglip2" do
  describe "class structure" do
    it "exists as a Ruby class" do
      expect(defined?(GTE::Siglip2)).to eq("constant")
    end

    it "responds to :embed" do
      expect(GTE::Siglip2.instance_methods(false)).to include(:embed)
    end
  end

  context "with real Siglip2 model fixture", if: GTE_SIGLIP2_FIXTURES_AVAILABLE do
    let(:siglip2) do
      GTE::Siglip2.new(model_path: GTE_SIGLIP2_MODEL_PATH, tokenizer_path: GTE_SIGLIP2_TOKENIZER_PATH)
    end

    let(:sample_texts) { ["a photo of a cat", "a photo of a dog"] }

    describe "embedding output" do
      it "returns Array<Array<Float>> with correct batch size" do
        result = siglip2.embed(sample_texts)
        expect(result).to be_a(Array)
        expect(result.length).to eq(sample_texts.length)
        result.each do |row|
          expect(row).to be_a(Array)
          expect(row.first).to be_a(Float)
        end
      end

      it "returns the expected embedding dimension (#{GTE_SIGLIP2_EMBEDDING_DIM})" do
        result = siglip2.embed(["test"])
        expect(result.first.length).to eq(GTE_SIGLIP2_EMBEDDING_DIM)
      end

      it "contains no NaN or Inf values" do
        result = siglip2.embed(sample_texts)
        result.each do |row|
          row.each do |val|
            expect(val).not_to be_nan
            expect(val.infinite?).to be_nil
          end
        end
      end

      it "returns L2-normalized vectors" do
        result = siglip2.embed(sample_texts)
        result.each_with_index do |row, i|
          l2_norm = Math.sqrt(row.sum { |v| v * v })
          expect(l2_norm).to be_within(1e-3).of(1.0),
            "row #{i}: expected L2 norm ≈ 1.0, got #{l2_norm}"
        end
      end
    end
  end

  context "without Siglip2 model fixture", unless: GTE_SIGLIP2_FIXTURES_AVAILABLE do
    it "fixture tests skipped — set GTE_SIGLIP2_MODEL_PATH to enable" do
      skip "Set GTE_SIGLIP2_MODEL_PATH environment variable to run Siglip2 fixture-dependent tests"
    end
  end
end
