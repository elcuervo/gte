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

  context "with real model fixture (API-03)", if: GTE_FIXTURES_AVAILABLE do
    # NOTE: Siglip2 output_tensor name is LOW CONFIDENCE until actual model is inspected.
    # This spec is structured but will fail until ModelConfig::siglip2() is updated
    # with the correct output_tensor name from model inspection.
    # See STATE.md blocker: "Siglip2 ONNX output tensor name is LOW confidence"
    let(:siglip2) { GTE::Siglip2.new(model_path: GTE_MODEL_PATH, tokenizer_path: GTE_TOKENIZER_PATH) }

    it "raises GTE::Error with informative message if output_tensor is wrong (TODO placeholder)" do
      pending "Requires inspecting actual Siglip2 ONNX export for output tensor name"
      result = siglip2.embed(["test"])
      expect(result).to be_a(Array)
    end
  end

  context "without model fixture", unless: GTE_FIXTURES_AVAILABLE do
    it "fixture tests skipped — set GTE_MODEL_PATH and GTE_TOKENIZER_PATH to enable" do
      skip "Set GTE_MODEL_PATH and GTE_TOKENIZER_PATH environment variables to run fixture-dependent tests"
    end
  end
end
