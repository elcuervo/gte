# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Integration' do
  SINGLE_BATCH_MIN_COSINE = 0.995
  SINGLE_BATCH_MAX_ABS_DIFF = 0.03

  def cosine_similarity(a, b)
    dot = a.zip(b).sum { |x, y| x * y }
    norm_a = Math.sqrt(a.sum { |v| v * v })
    norm_b = Math.sqrt(b.sum { |v| v * v })
    dot / (norm_a * norm_b)
  end

  def max_abs_diff(a, b)
    a.zip(b).map { |x, y| (x - y).abs }.max || 0.0
  end

  def matrix(result)
    return result if result.is_a?(Array)
    return result.to_a if result.respond_to?(:to_a)

    result
  end

  context 'GTE.config API', if: GTE_E5_AVAILABLE do
    let(:model) { GTE.config(GTE_E5_DIR) }

    it 'embed returns GTE::Tensor' do
      result = model.embed('Hello world')
      expect(result).to be_a(GTE::Tensor)
      expect(result.rows).to eq(1)
      expect(result.dim).to eq(GTE_EMBEDDING_DIM)
      expect(result.row(0).first).to be_a(Float)
    end

    it '[] with string returns single vector' do
      result = model['Hello world']
      expect(result).to be_a(Array)
      expect(result.first).to be_a(Float)
    end

    it '[] with array returns batch' do
      result = model[%w[Hello World]]
      expect(result).to be_a(GTE::Tensor)
      expect(result.rows).to eq(2)
      matrix(result).each { |row| expect(row.first).to be_a(Float) }
    end
  end

  context 'E5', if: GTE_E5_AVAILABLE do
    let(:model) { GTE.config(GTE_E5_DIR) }

    it 'batch embedding returns correct dimensions' do
      texts = ['Hello world', 'Goodbye world', 'Machine learning']
      result = model.embed(texts)
      expect(result.rows).to eq(3)
      matrix(result).each { |row| expect(row.length).to eq(GTE_EMBEDDING_DIM) }
    end

    it 'cosine similarity: related texts score higher than unrelated' do
      q = model['query: How to train a neural network?']
      related = model['passage: Training neural networks requires backpropagation and gradient descent.']
      unrelated = model['passage: The recipe calls for two cups of flour and one egg.']

      sim_related = cosine_similarity(q, related)
      sim_unrelated = cosine_similarity(q, unrelated)
      expect(sim_related).to be > sim_unrelated
    end

    it 'long text truncation works silently' do
      long_text = 'word ' * 1000
      result = model.embed(long_text)
      expect(result.rows).to eq(1)
      expect(result.dim).to eq(GTE_EMBEDDING_DIM)
    end

    it 'empty string handling' do
      result = model.embed('')
      expect(result.rows).to eq(1)
      expect(result.dim).to eq(GTE_EMBEDDING_DIM)
    end

    it 'single text and batch produce consistent embeddings' do
      text = 'consistency test'
      single = model.embed(text).row(0)
      batch = model.embed([text, 'other text']).row(0)

      cosine = cosine_similarity(single, batch)
      max_abs = max_abs_diff(single, batch)
      expect(cosine).to be >= SINGLE_BATCH_MIN_COSINE
      expect(max_abs).to be <= SINGLE_BATCH_MAX_ABS_DIFF
    end

    it 'supports disabling normalization via initializer' do
      normalized_model = GTE.config(GTE_E5_DIR) { |config| config.with(normalize: true) }
      raw_model = GTE.config(GTE_E5_DIR) { |config| config.with(normalize: false) }
      normalized = normalized_model.embed('normalization flag test').row(0)
      raw = raw_model.embed('normalization flag test').row(0)

      normalized_norm = Math.sqrt(normalized.sum { |v| v * v })
      raw_norm = Math.sqrt(raw.sum { |v| v * v })

      expect(normalized_norm).to be_within(1e-3).of(1.0)
      expect(max_abs_diff(normalized, raw)).to be > 1e-6
      expect((raw_norm - 1.0).abs).to be > 1e-4
    end

    it 'accepts an explicit output_tensor override' do
      overridden = GTE.config(GTE_E5_DIR) { |config| config.with(output_tensor: 'last_hidden_state') }
      result = overridden.embed('explicit output tensor')
      expect(result.rows).to eq(1)
      expect(result.dim).to eq(GTE_EMBEDDING_DIM)
    end

    it 'fails fast when output_tensor override is missing from model outputs' do
      expect do
        GTE.config(GTE_E5_DIR) { |config| config.with(output_tensor: 'pooled_sentence_embeddings_debiased_normalized') }
      end.to raise_error(
        GTE::Error,
        /requested output tensor.*pooled_sentence_embeddings_debiased_normalized.*model outputs/i
      )
    end

    it 'applies max_length truncation override' do
      overridden = GTE.config(GTE_E5_DIR) { |config| config.with(max_length: 8) }
      result = overridden.embed('word ' * 1000)
      expect(result.rows).to eq(1)
      expect(result.dim).to eq(GTE_EMBEDDING_DIM)
    end

    it 'truncates like tokenizer max length: suffix differences past max_length are ignored' do
      overridden = GTE.config(GTE_E5_DIR) { |config| config.with(max_length: 8) }
      prefix = ('sharedprefix ' * 64).strip
      a = overridden.embed("query: #{prefix} alpha_suffix").row(0)
      b = overridden.embed("query: #{prefix} beta_suffix totally different tail").row(0)
      expect(cosine_similarity(a, b)).to be >= 0.99999
      expect(max_abs_diff(a, b)).to be <= 1e-5
    end

  end

  context 'CLIP', if: GTE_CLIP_AVAILABLE do
    let(:model) { GTE.config(GTE_CLIP_DIR) }

    it 'batch embedding returns correct dimensions' do
      texts = ['a photo of a cat', 'a painting of a sunset']
      result = model.embed(texts)
      expect(result.rows).to eq(2)
      matrix(result).each { |row| expect(row).to be_a(Array) }
    end

    it 'semantic similarity ordering' do
      texts = ['a photo of a cat', 'a picture of a kitten', 'a blueprint of a skyscraper']
      embeddings = matrix(model.embed(texts))
      sim_related = cosine_similarity(embeddings[0], embeddings[1])
      sim_unrelated = cosine_similarity(embeddings[0], embeddings[2])
      expect(sim_related).to be > sim_unrelated
    end
  end

  context 'Siglip2', if: GTE_SIGLIP2_AVAILABLE do
    let(:model) { GTE.config(GTE_SIGLIP2_DIR) }

    it 'batch embedding returns correct dimensions' do
      texts = ['a photo of a cat', 'a photo of a dog']
      result = model.embed(texts)
      expect(result.rows).to eq(2)
      matrix(result).each { |row| expect(row.length).to eq(GTE_SIGLIP2_EMBEDDING_DIM) }
    end

    it 'L2 normalization' do
      result = model.embed('test normalization').row(0)
      norm = Math.sqrt(result.sum { |v| v * v })
      expect(norm).to be_within(1e-3).of(1.0)
    end
  end

  context 'cross-model', if: GTE_E5_AVAILABLE && GTE_CLIP_AVAILABLE do
    it 'same text embedded by different models produces different dimension vectors' do
      e5 = GTE.config(GTE_E5_DIR)
      clip = GTE.config(GTE_CLIP_DIR)

      e5_result = e5.embed('hello world')
      clip_result = clip.embed('hello world')

      expect(e5_result.dim).not_to eq(clip_result.dim)
    end

    it 'multiple embedders from different models can coexist' do
      e5 = GTE.config(GTE_E5_DIR)
      clip = GTE.config(GTE_CLIP_DIR)

      e5_result = e5.embed('test')
      clip_result = clip.embed('test')
      expect(e5_result.row(0)).to all(be_a(Float))
      expect(clip_result.row(0)).to all(be_a(Float))
    end
  end

  context 'unsupported multimodal model inputs', if: GTE_CLIP_MULTIMODAL_AVAILABLE do
    it 'fails fast with actionable error when model requires pixel_values' do
      expect do
        GTE.config(GTE_CLIP_MULTIMODAL_DIR)
      end.to raise_error(
        GTE::Error,
        /pixel_values.*text_model\.onnx|text_model\.onnx.*pixel_values/i
      )
    end
  end

  context 'performance baseline', if: GTE_E5_AVAILABLE do
    let(:model) { GTE.config(GTE_E5_DIR) }

    it 'batch embedding amortizes well (batch of 32 < 2x single time)' do
      model.embed('warmup')

      single_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      model.embed('single text benchmark')
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

  context 'concurrent single request path', if: GTE_E5_AVAILABLE do
    let(:model_dir) { GTE_E5_DIR }

    it 'matches single string and single-item batch embeddings for one text' do
      model = GTE.config(model_dir)
      text = 'batch engine probe'

      single_vec = model.embed(text).row(0)
      batch_vec = model.embed([text]).row(0)
      expect(cosine_similarity(single_vec, batch_vec)).to be >= SINGLE_BATCH_MIN_COSINE
      expect(max_abs_diff(single_vec, batch_vec)).to be <= SINGLE_BATCH_MAX_ABS_DIFF
    end

    it 'handles concurrent string requests with one vector per input' do
      model = GTE.config(model_dir)
      texts = Array.new(32) { |i| "concurrent batch request #{i}" }

      results = Array.new(texts.length)
      threads = texts.each_with_index.map do |text, idx|
        Thread.new { results[idx] = model.embed(text).row(0) }
      end
      threads.each(&:join)

      results.each do |row|
        expect(row.length).to eq(GTE_EMBEDDING_DIM)
      end
    end
  end
end
