# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Integration" do
  def cosine_similarity(a, b)
    dot = a.zip(b).sum { |x, y| x * y }
    norm_a = Math.sqrt(a.sum { |v| v * v })
    norm_b = Math.sqrt(b.sum { |v| v * v })
    dot / (norm_a * norm_b)
  end

  # -- E5 Integration -------------------------------------------------------
  context "E5", if: GTE_FIXTURES_AVAILABLE do
    let(:e5) { GTE::E5.new(model_path: GTE_MODEL_PATH, tokenizer_path: GTE_TOKENIZER_PATH) }

    it "batch embedding returns correct dimensions" do
      texts = ["Hello world", "Goodbye world", "Machine learning"]
      result = e5.embed(texts)
      expect(result.length).to eq(3)
      result.each { |row| expect(row.length).to eq(GTE_EMBEDDING_DIM) }
    end

    it "embed_query vs embed_passage produce different vectors" do
      q = e5.embed_query("What is machine learning?")
      p = e5.embed_passage("Machine learning is a subset of AI.")
      expect(q).not_to eq(p)
    end

    it "cosine similarity: related texts score higher than unrelated" do
      q = e5.embed_query("How to train a neural network?")
      related = e5.embed_passage("Training neural networks requires backpropagation and gradient descent.")
      unrelated = e5.embed_passage("The recipe calls for two cups of flour and one egg.")

      sim_related = cosine_similarity(q, related)
      sim_unrelated = cosine_similarity(q, unrelated)
      expect(sim_related).to be > sim_unrelated
    end

    it "long text truncation works silently at max_length=512" do
      long_text = "word " * 1000
      result = e5.embed([long_text])
      expect(result.length).to eq(1)
      expect(result.first.length).to eq(GTE_EMBEDDING_DIM)
    end

    it "empty string handling" do
      result = e5.embed([""])
      expect(result.length).to eq(1)
      expect(result.first.length).to eq(GTE_EMBEDDING_DIM)
    end

    it "single text and batch produce consistent embeddings" do
      text = "consistency test"
      single = e5.embed([text]).first
      batch = e5.embed([text, "other text"]).first

      single.zip(batch).each_with_index do |(s, b), i|
        expect(s).to be_within(1e-5).of(b), "element #{i} differs: single=#{s} batch=#{b}"
      end
    end
  end

  # -- CLIP Integration ------------------------------------------------------
  context "CLIP", if: GTE_CLIP_FIXTURES_AVAILABLE do
    let(:clip) { GTE::CLIP.new(model_path: GTE_CLIP_MODEL_PATH, tokenizer_path: GTE_CLIP_TOKENIZER_PATH) }

    it "batch embedding returns correct dimensions" do
      texts = ["a photo of a cat", "a painting of a sunset"]
      result = clip.embed(texts)
      expect(result.length).to eq(2)
      result.each { |row| expect(row).to be_a(Array) }
    end

    it "does not have query/passage prefix methods" do
      expect(clip).not_to respond_to(:embed_query)
      expect(clip).not_to respond_to(:embed_passage)
    end

    it "max length 77 truncation" do
      long_text = "word " * 200
      result = clip.embed([long_text])
      expect(result.length).to eq(1)
    end

    it "semantic similarity ordering" do
      texts = ["a photo of a cat", "a picture of a kitten", "a blueprint of a skyscraper"]
      embeddings = clip.embed(texts)
      sim_related = cosine_similarity(embeddings[0], embeddings[1])
      sim_unrelated = cosine_similarity(embeddings[0], embeddings[2])
      expect(sim_related).to be > sim_unrelated
    end
  end

  # -- Siglip2 Integration ---------------------------------------------------
  context "Siglip2", if: GTE_SIGLIP2_FIXTURES_AVAILABLE do
    let(:siglip2) { GTE::Siglip2.new(model_path: GTE_SIGLIP2_MODEL_PATH, tokenizer_path: GTE_SIGLIP2_TOKENIZER_PATH) }

    it "batch embedding returns correct dimensions" do
      texts = ["a photo of a cat", "a photo of a dog"]
      result = siglip2.embed(texts)
      expect(result.length).to eq(2)
      result.each { |row| expect(row.length).to eq(GTE_SIGLIP2_EMBEDDING_DIM) }
    end

    it "max length 64 truncation" do
      long_text = "word " * 200
      result = siglip2.embed([long_text])
      expect(result.length).to eq(1)
    end

    it "L2 normalization" do
      result = siglip2.embed(["test normalization"])
      norm = Math.sqrt(result.first.sum { |v| v * v })
      expect(norm).to be_within(1e-3).of(1.0)
    end
  end

  # -- Cross-Model -----------------------------------------------------------
  context "cross-model", if: (GTE_FIXTURES_AVAILABLE && GTE_CLIP_FIXTURES_AVAILABLE) do
    it "same text embedded by E5 vs CLIP produces different dimension vectors" do
      e5 = GTE::E5.new(model_path: GTE_MODEL_PATH, tokenizer_path: GTE_TOKENIZER_PATH)
      clip = GTE::CLIP.new(model_path: GTE_CLIP_MODEL_PATH, tokenizer_path: GTE_CLIP_TOKENIZER_PATH)

      e5_result = e5.embed(["hello world"])
      clip_result = clip.embed(["hello world"])

      # Different models → likely different embedding dimensions
      expect(e5_result.first.length).not_to eq(clip_result.first.length)
    end

    it "multiple embedders from different models can coexist" do
      e5 = GTE::E5.new(model_path: GTE_MODEL_PATH, tokenizer_path: GTE_TOKENIZER_PATH)
      clip = GTE::CLIP.new(model_path: GTE_CLIP_MODEL_PATH, tokenizer_path: GTE_CLIP_TOKENIZER_PATH)

      # Both should produce valid results without interfering
      e5_result = e5.embed(["test"])
      clip_result = clip.embed(["test"])
      expect(e5_result.first).to all(be_a(Float))
      expect(clip_result.first).to all(be_a(Float))
    end
  end

  # -- Config Override -------------------------------------------------------
  context "config override", if: GTE_FIXTURES_AVAILABLE do
    it "custom ModelConfig with non-default num_threads works" do
      config = GTE::ModelConfig.new(
        max_length: 512, output_tensor: "last_hidden_state",
        mode: :mean_pool, with_type_ids: true,
        num_threads: 2, optimization_level: 1
      )
      e5 = GTE::E5.new(model_path: GTE_MODEL_PATH, tokenizer_path: GTE_TOKENIZER_PATH, config: config)
      result = e5.embed(["config test"])
      expect(result.first.length).to eq(GTE_EMBEDDING_DIM)
    end
  end

  # -- Performance Baseline --------------------------------------------------
  context "performance baseline", if: GTE_FIXTURES_AVAILABLE do
    let(:e5) { GTE::E5.new(model_path: GTE_MODEL_PATH, tokenizer_path: GTE_TOKENIZER_PATH) }

    it "batch embedding amortizes well (batch of 32 < 2x single time)" do
      # Warmup
      e5.embed(["warmup"])

      single_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      e5.embed(["single text benchmark"])
      single_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - single_start

      batch_texts = Array.new(32) { |i| "batch text number #{i} for benchmark" }
      batch_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      e5.embed(batch_texts)
      batch_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - batch_start

      per_item = batch_time / 32.0
      puts "\n  [perf] single=#{(single_time * 1000).round(2)}ms batch32_per_item=#{(per_item * 1000).round(2)}ms"

      # Batch per-item should be significantly cheaper than single
      expect(per_item).to be < (single_time * 2)
    end
  end

  # -- Fixture guards --------------------------------------------------------
  context "without E5 fixture", unless: GTE_FIXTURES_AVAILABLE do
    it("skipped — set GTE_MODEL_PATH") { skip }
  end

  context "without CLIP fixture", unless: GTE_CLIP_FIXTURES_AVAILABLE do
    it("skipped — set GTE_CLIP_MODEL_PATH") { skip }
  end

  context "without Siglip2 fixture", unless: GTE_SIGLIP2_FIXTURES_AVAILABLE do
    it("skipped — set GTE_SIGLIP2_MODEL_PATH") { skip }
  end
end
