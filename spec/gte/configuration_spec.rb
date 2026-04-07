# frozen_string_literal: true

require "spec_helper"

RSpec.describe "GTE.configure (API-06)" do
  # Always reset memoized state after each test to prevent cross-test pollution
  after do
    GTE.instance_variable_set(:@config, nil)
    GTE.instance_variable_set(:@default, nil)
  end

  describe "GTE::Configuration" do
    it "exists as a Ruby class" do
      expect(defined?(GTE::Configuration)).to eq("constant")
    end

    it "initializes with :e5 as default model_family" do
      config = GTE::Configuration.new
      expect(config.model_family).to eq(:e5)
    end

    it "has attr_accessor for model_path" do
      config = GTE::Configuration.new
      config.model_path = "/path/to/model.onnx"
      expect(config.model_path).to eq("/path/to/model.onnx")
    end

    it "has attr_accessor for tokenizer_path" do
      config = GTE::Configuration.new
      config.tokenizer_path = "/path/to/tokenizer.json"
      expect(config.tokenizer_path).to eq("/path/to/tokenizer.json")
    end

    it "has attr_accessor for model_family" do
      config = GTE::Configuration.new
      config.model_family = :clip
      expect(config.model_family).to eq(:clip)
    end
  end

  describe "GTE.configure block" do
    it "yields the config object" do
      GTE.configure do |c|
        c.model_path    = "/tmp/model.onnx"
        c.model_family  = :clip
      end
      expect(GTE.config.model_path).to eq("/tmp/model.onnx")
      expect(GTE.config.model_family).to eq(:clip)
    end
  end

  describe "GTE.config" do
    it "returns a GTE::Configuration instance" do
      expect(GTE.config).to be_a(GTE::Configuration)
    end

    it "is memoized — returns the same instance on repeated calls" do
      first  = GTE.config
      second = GTE.config
      expect(first).to be(second)
    end
  end

  describe "GTE.reset_default!" do
    it "clears the memoized default instance" do
      # Build a fake default by setting @default directly
      GTE.instance_variable_set(:@default, "fake_embedder")
      expect(GTE.instance_variable_get(:@default)).to eq("fake_embedder")

      GTE.reset_default!
      expect(GTE.instance_variable_get(:@default)).to be_nil
    end
  end

  describe "GTE.default (API-06)", if: GTE_FIXTURES_AVAILABLE do
    it "returns a memoized embedder built from current config" do
      GTE.configure do |c|
        c.model_path      = GTE_MODEL_PATH
        c.tokenizer_path  = GTE_TOKENIZER_PATH
        c.model_family    = :e5
      end

      first_default  = GTE.default
      second_default = GTE.default
      expect(first_default).to be(second_default), "GTE.default should return the same memoized instance"
    end

    it "returns a GTE::E5 instance when model_family is :e5" do
      GTE.configure do |c|
        c.model_path      = GTE_MODEL_PATH
        c.tokenizer_path  = GTE_TOKENIZER_PATH
        c.model_family    = :e5
      end
      expect(GTE.default).to be_a(GTE::E5)
    end

    it "returns a new instance after GTE.reset_default!" do
      GTE.configure do |c|
        c.model_path      = GTE_MODEL_PATH
        c.tokenizer_path  = GTE_TOKENIZER_PATH
        c.model_family    = :e5
      end
      first = GTE.default
      GTE.reset_default!
      second = GTE.default
      expect(first).not_to be(second)
    end
  end

  context "GTE.default without fixture", unless: GTE_FIXTURES_AVAILABLE do
    it "fixture tests for GTE.default skipped — set GTE_MODEL_PATH to enable" do
      skip "Set GTE_MODEL_PATH and GTE_TOKENIZER_PATH environment variables to run GTE.default tests"
    end
  end
end
