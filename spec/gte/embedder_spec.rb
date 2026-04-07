# frozen_string_literal: true

require "spec_helper"

RSpec.describe GTE::Embedder do
  describe "class structure" do
    it "exists as a Ruby class" do
      expect(GTE::Embedder).to be_a(Class)
    end

    it "has a new singleton method" do
      expect(GTE::Embedder).to respond_to(:new)
    end

    it "has an embed instance method" do
      expect(GTE::Embedder.instance_methods(false)).to include(:embed)
    end
  end

  describe "GTE::Error" do
    it "is a subclass of StandardError" do
      expect(GTE::Error.ancestors).to include(StandardError)
    end

    it "can be raised and rescued as StandardError" do
      expect {
        raise GTE::Error, "test error"
      }.to raise_error(StandardError, "test error")
    end

    it "can be raised and rescued specifically as GTE::Error" do
      expect {
        raise GTE::Error, "specific error"
      }.to raise_error(GTE::Error)
    end
  end

  describe ".new with invalid config" do
    it "raises ArgumentError for unknown config name" do
      # This test will fail until the extension is compiled with ruby_embedder.rs
      # But it validates the API contract for Phase 3 BIND-01
      skip "requires compiled extension with GTE::Embedder"
      expect {
        GTE::Embedder.new("path/to/tokenizer.json", "path/to/model.onnx", "invalid_config")
      }.to raise_error(ArgumentError, /unknown config/)
    end
  end
end
