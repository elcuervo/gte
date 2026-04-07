# frozen_string_literal: true

require "spec_helper"

RSpec.describe "GTE::Embedder" do
  # -- Structural tests — run without any model fixture -------------------------------------------

  describe "class structure" do
    it "exists as a Ruby class" do
      expect(defined?(GTE::Embedder)).to eq("constant")
    end

    it "has a .new class method" do
      expect(GTE::Embedder).to respond_to(:new)
    end

    it "responds to :embed" do
      expect(GTE::Embedder.instance_methods(false)).to include(:embed)
    end
  end

  describe "GTE::Error" do
    it "is a subclass of StandardError (not RuntimeError)" do
      expect(GTE::Error.ancestors).to include(StandardError)
      expect(GTE::Error.superclass).to eq(StandardError)
    end
  end

  describe ".new argument validation" do
    it "raises ArgumentError for unknown config name (no model needed)" do
      # Use paths that will never be reached — config validation is first
      # (Embedder raises ArgumentError before checking file existence)
      expect {
        GTE::Embedder.new("/dev/null", "/dev/null", "unknown_config")
      }.to raise_error(ArgumentError, /unknown config/)
    end
  end

  describe ".new with invalid paths" do
    it "raises GTE::Error when model file does not exist" do
      expect {
        GTE::Embedder.new("/nonexistent/tokenizer.json", "/nonexistent/model.onnx", "e5")
      }.to raise_error(GTE::Error)
    end
  end

  # -- Correctness tests — require real ONNX model fixture ----------------------------------------
  # Set GTE_MODEL_PATH and GTE_TOKENIZER_PATH to run these tests.
  # Per CRITICAL USER REQUIREMENT in planning context.

  context "with real model fixture", if: GTE_FIXTURES_AVAILABLE do
    let(:embedder) do
      GTE::Embedder.new(GTE_TOKENIZER_PATH, GTE_MODEL_PATH, "e5")
    end

    let(:sample_texts) { ["Hello world", "The quick brown fox"] }
    let(:single_text)  { ["Hello world"] }

    describe "return structure" do
      it "returns Array<Array<Float>> for a batch" do
        result = embedder.embed(sample_texts)
        expect(result).to be_a(Array)
        expect(result.length).to eq(sample_texts.length)
        result.each do |row|
          expect(row).to be_a(Array)
          expect(row).not_to be_empty
        end
      end

      it "returns the expected embedding dimension (#{GTE_EMBEDDING_DIM})" do
        result = embedder.embed(single_text)
        expect(result.first.length).to eq(GTE_EMBEDDING_DIM)
      end
    end

    describe "output validity (API-07 — correctness requirement)" do
      it "contains only valid floats — no NaN values" do
        result = embedder.embed(sample_texts)
        result.each do |row|
          row.each do |val|
            expect(val).not_to be_nan, "expected no NaN in embedding, got NaN at #{val.inspect}"
          end
        end
      end

      it "contains only valid floats — no Inf values" do
        result = embedder.embed(sample_texts)
        result.each do |row|
          row.each do |val|
            expect(val.infinite?).to be_nil, "expected no Inf in embedding, got #{val.inspect}"
          end
        end
      end
    end

    describe "L2 normalization (API-07 — critical correctness requirement)" do
      it "returns L2-normalized vectors: norm of each row is approximately 1.0" do
        result = embedder.embed(sample_texts)
        result.each_with_index do |row, i|
          l2_norm = Math.sqrt(row.sum { |v| v * v })
          expect(l2_norm).to be_within(1e-3).of(1.0),
            "row #{i}: expected L2 norm ≈ 1.0, got #{l2_norm}"
        end
      end

      it "dot product of two different normalized embeddings equals cosine similarity" do
        # For L2-normalized vectors: dot_product(a, b) == cosine_similarity(a, b)
        result = embedder.embed(sample_texts)
        vec_a = result[0]
        vec_b = result[1]

        dot_product = vec_a.zip(vec_b).sum { |a, b| a * b }
        norm_a = Math.sqrt(vec_a.sum { |v| v * v })
        norm_b = Math.sqrt(vec_b.sum { |v| v * v })
        cosine_sim = dot_product / (norm_a * norm_b)

        # For normalized vectors, dot_product == cosine_sim (both ≈ same value)
        expect(dot_product).to be_within(1e-5).of(cosine_sim),
          "expected dot_product (#{dot_product}) ≈ cosine_similarity (#{cosine_sim})"
      end

      it "Rust normalization matches Ruby-computed normalization for the same input" do
        result = embedder.embed(single_text)
        rust_normalized = result.first

        # Verify that the already-returned vector IS normalized (norm ≈ 1.0)
        # This is the Ruby verification of Rust's normalize_l2 correctness
        raw_norm = Math.sqrt(rust_normalized.sum { |v| v * v })
        expect(raw_norm).to be_within(1e-4).of(1.0),
          "Rust normalization diverges from expected: norm=#{raw_norm}"

        # Ruby re-normalization of an already-normalized vector should return the same vector
        ruby_renormalized = rust_normalized.map { |v| v / raw_norm }
        rust_normalized.zip(ruby_renormalized).each_with_index do |(r, rb), i|
          expect(r).to be_within(1e-5).of(rb),
            "element #{i}: Rust=#{r}, Ruby=#{rb}"
        end
      end
    end

    describe "prefix semantics via E5 class (API-04, API-05)" do
      let(:e5) { GTE::E5.new(model_path: GTE_MODEL_PATH, tokenizer_path: GTE_TOKENIZER_PATH) }
      let(:text) { "machine learning embeddings" }

      it "embed_query produces different embedding than embed without prefix" do
        query_emb = e5.embed_query(text)
        plain_emb = e5.embed([text]).first

        # Prefixed input produces different token sequence → different embedding
        expect(query_emb).not_to eq(plain_emb),
          "expected embed_query to differ from embed (prefix 'query: ' should change the vector)"
      end

      it "embed_passage produces different embedding than embed_query for same text" do
        query_emb   = e5.embed_query(text)
        passage_emb = e5.embed_passage(text)

        expect(query_emb).not_to eq(passage_emb),
          "expected embed_query and embed_passage to produce different vectors"
      end

      it "embed_query returns Array<Float> (not Array<Array<Float>>)" do
        result = e5.embed_query(text)
        expect(result).to be_a(Array)
        expect(result.first).to be_a(Float)
      end

      it "embed_passage returns Array<Float> (not Array<Array<Float>>)" do
        result = e5.embed_passage(text)
        expect(result).to be_a(Array)
        expect(result.first).to be_a(Float)
      end
    end
  end

  context "without model fixture (fixture guards)", unless: GTE_FIXTURES_AVAILABLE do
    it "fixture tests skipped — set GTE_MODEL_PATH and GTE_TOKENIZER_PATH to enable" do
      skip "Set GTE_MODEL_PATH and GTE_TOKENIZER_PATH environment variables to run fixture-dependent tests"
    end
  end
end
