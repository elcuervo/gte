# frozen_string_literal: true

require "spec_helper"

RSpec.describe "GTE::CLIP" do
  describe "class structure" do
    it "exists as a Ruby class" do
      expect(defined?(GTE::CLIP)).to eq("constant")
    end

    it "responds to :embed" do
      expect(GTE::CLIP.instance_methods(false)).to include(:embed)
    end

    it "does not respond to :embed_query (CLIP has no prefix semantics)" do
      expect(GTE::CLIP.instance_methods(false)).not_to include(:embed_query)
    end
  end

  context "with real model fixture", if: GTE_FIXTURES_AVAILABLE do
    # CLIP requires a CLIP-compatible ONNX model and tokenizer.
    # Override GTE_MODEL_PATH with a CLIP model path to test this class.
    let(:clip) { GTE::CLIP.new(model_path: GTE_MODEL_PATH, tokenizer_path: GTE_TOKENIZER_PATH) }
    let(:text) { "a photo of a cat" }

    describe "#embed (API-02)" do
      it "returns Array<Array<Float>>" do
        result = clip.embed([text])
        expect(result).to be_a(Array)
        expect(result.first).to be_a(Array)
        expect(result.first.first).to be_a(Float)
      end

      it "returns L2-normalized vectors (norm ≈ 1.0)" do
        result = clip.embed([text])
        norm = Math.sqrt(result.first.sum { |v| v * v })
        expect(norm).to be_within(1e-3).of(1.0)
      end
    end
  end

  context "without model fixture", unless: GTE_FIXTURES_AVAILABLE do
    it "fixture tests skipped — set GTE_MODEL_PATH and GTE_TOKENIZER_PATH to enable" do
      skip "Set GTE_MODEL_PATH and GTE_TOKENIZER_PATH environment variables to run fixture-dependent tests"
    end
  end
end
