# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Integration" do
  def cosine_similarity(a, b)
    dot = a.zip(b).sum { |x, y| x * y }
    norm_a = Math.sqrt(a.sum { |v| v * v })
    norm_b = Math.sqrt(b.sum { |v| v * v })
    dot / (norm_a * norm_b)
  end

  # -- GTE.new API ---------------------------------------------------------
  context "GTE.new API", if: GTE_E5_AVAILABLE do
    let(:model) { GTE.new(GTE_E5_DIR) }

    it "embed returns Array<Array<Float>>" do
      result = model.embed("Hello world")
      expect(result).to be_a(Array)
      expect(result.first).to be_a(Array)
      expect(result.first.first).to be_a(Float)
    end

    it "[] with string returns single vector" do
      result = model["Hello world"]
      expect(result).to be_a(Array)
      expect(result.first).to be_a(Float)
    end

    it "[] with array returns batch" do
      result = model[["Hello", "World"]]
      expect(result.length).to eq(2)
      result.each { |row| expect(row.first).to be_a(Float) }
    end
  end

  # -- E5 Integration -------------------------------------------------------
  context "E5", if: GTE_E5_AVAILABLE do
    let(:model) { GTE.new(GTE_E5_DIR) }

    it "batch embedding returns correct dimensions" do
      texts = ["Hello world", "Goodbye world", "Machine learning"]
      result = model.embed(texts)
      expect(result.length).to eq(3)
      result.each { |row| expect(row.length).to eq(GTE_EMBEDDING_DIM) }
    end

    it "cosine similarity: related texts score higher than unrelated" do
      q = model["query: How to train a neural network?"]
      related = model["passage: Training neural networks requires backpropagation and gradient descent."]
      unrelated = model["passage: The recipe calls for two cups of flour and one egg."]

      sim_related = cosine_similarity(q, related)
      sim_unrelated = cosine_similarity(q, unrelated)
      expect(sim_related).to be > sim_unrelated
    end

    it "long text truncation works silently" do
      long_text = "word " * 1000
      result = model.embed(long_text)
      expect(result.length).to eq(1)
      expect(result.first.length).to eq(GTE_EMBEDDING_DIM)
    end

    it "empty string handling" do
      result = model.embed("")
      expect(result.length).to eq(1)
      expect(result.first.length).to eq(GTE_EMBEDDING_DIM)
    end

    it "single text and batch produce consistent embeddings" do
      text = "consistency test"
      single = model.embed(text).first
      batch = model.embed([text, "other text"]).first

      single.zip(batch).each_with_index do |(s, b), i|
        expect(s).to be_within(1e-5).of(b), "element #{i} differs: single=#{s} batch=#{b}"
      end
    end
  end

  # -- CLIP Integration ------------------------------------------------------
  context "CLIP", if: GTE_CLIP_AVAILABLE do
    let(:model) { GTE.new(GTE_CLIP_DIR) }

    it "batch embedding returns correct dimensions" do
      texts = ["a photo of a cat", "a painting of a sunset"]
      result = model.embed(texts)
      expect(result.length).to eq(2)
      result.each { |row| expect(row).to be_a(Array) }
    end

    it "semantic similarity ordering" do
      texts = ["a photo of a cat", "a picture of a kitten", "a blueprint of a skyscraper"]
      embeddings = model.embed(texts)
      sim_related = cosine_similarity(embeddings[0], embeddings[1])
      sim_unrelated = cosine_similarity(embeddings[0], embeddings[2])
      expect(sim_related).to be > sim_unrelated
    end
  end

  # -- Siglip2 Integration ---------------------------------------------------
  context "Siglip2", if: GTE_SIGLIP2_AVAILABLE do
    let(:model) { GTE.new(GTE_SIGLIP2_DIR) }

    it "batch embedding returns correct dimensions" do
      texts = ["a photo of a cat", "a photo of a dog"]
      result = model.embed(texts)
      expect(result.length).to eq(2)
      result.each { |row| expect(row.length).to eq(GTE_SIGLIP2_EMBEDDING_DIM) }
    end

    it "L2 normalization" do
      result = model.embed("test normalization")
      norm = Math.sqrt(result.first.sum { |v| v * v })
      expect(norm).to be_within(1e-3).of(1.0)
    end
  end

  # -- Cross-Model -----------------------------------------------------------
  context "cross-model", if: (GTE_E5_AVAILABLE && GTE_CLIP_AVAILABLE) do
    it "same text embedded by different models produces different dimension vectors" do
      e5 = GTE.new(GTE_E5_DIR)
      clip = GTE.new(GTE_CLIP_DIR)

      e5_result = e5.embed("hello world")
      clip_result = clip.embed("hello world")

      expect(e5_result.first.length).not_to eq(clip_result.first.length)
    end

    it "multiple embedders from different models can coexist" do
      e5 = GTE.new(GTE_E5_DIR)
      clip = GTE.new(GTE_CLIP_DIR)

      e5_result = e5.embed("test")
      clip_result = clip.embed("test")
      expect(e5_result.first).to all(be_a(Float))
      expect(clip_result.first).to all(be_a(Float))
    end
  end

  # -- Unsupported Model Inputs -----------------------------------------------
  context "unsupported multimodal model inputs", if: GTE_CLIP_MULTIMODAL_AVAILABLE do
    it "fails fast with actionable error when model requires pixel_values" do
      expect {
        GTE.new(GTE_CLIP_MULTIMODAL_DIR)
      }.to raise_error(
        GTE::Error,
        /pixel_values.*text_model\.onnx|text_model\.onnx.*pixel_values/i
      )
    end
  end

  # -- Performance Baseline --------------------------------------------------
  context "performance baseline", if: GTE_E5_AVAILABLE do
    let(:model) { GTE.new(GTE_E5_DIR) }

    it "batch embedding amortizes well (batch of 32 < 2x single time)" do
      model.embed("warmup")

      single_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      model.embed("single text benchmark")
      single_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - single_start

      batch_texts = Array.new(32) { |i| "batch text number #{i} for benchmark" }
      batch_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      model.embed(batch_texts)
      batch_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - batch_start

      per_item = batch_time / 32.0
      puts "\n  [perf] single=#{(single_time * 1000).round(2)}ms batch32_per_item=#{(per_item * 1000).round(2)}ms"
      expect(per_item).to be < (single_time * 2)
    end
  end

end
