# frozen_string_literal: true

require 'spec_helper'
require 'onnxruntime'
require 'tokenizers'

RSpec.describe 'Integration' do
  SINGLE_BATCH_MIN_COSINE = 0.995
  SINGLE_BATCH_MAX_ABS_DIFF = 0.03
  REFERENCE_MIN_COSINE = 0.9999

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

  def reference_mean_pool_normalize(hidden_states, attention_mask, normalize: true)
    dim = hidden_states.first.first.length
    result = Array.new(dim, 0.0)
    count = 0
    hidden_states.first.each_with_index do |token_vec, i|
      next if attention_mask[i] == 0

      token_vec.each_with_index { |v, j| result[j] += v }
      count += 1
    end
    result.map! { |v| v / count }
    normalize ? l2_normalize(result) : result
  end

  def reference_raw_normalize(vec, normalize: true)
    normalize ? l2_normalize(vec) : vec
  end

  def l2_normalize(vec)
    norm = Math.sqrt(vec.sum { |v| v * v })
    norm < 1e-12 ? vec : vec.map { |v| v / norm }
  end

  def reference_tokenize(tokenizer_path, text, no_padding: false)
    tok = Tokenizers.from_file(tokenizer_path)
    tok.no_padding if no_padding
    enc = tok.encode_batch([text]).first
    { input_ids: [enc.ids], attention_mask: [enc.attention_mask], type_ids: [enc.type_ids] }
  end

  context 'GTE.config API', if: GTE_E5_AVAILABLE do
    let(:pool) { GTE.config(GTE_E5_DIR) }

    it 'embed returns GTE::Tensor' do
      result = pool.embed('Hello world')
      expect(result).to be_a(GTE::Tensor)
      expect(result.rows).to eq(1)
      expect(result.dim).to eq(GTE_EMBEDDING_DIM)
      expect(result.row(0).first).to be_a(Float)
    end
  end

  context 'E5', if: GTE_E5_AVAILABLE do
    let(:pool) { GTE.config(GTE_E5_DIR) }

    it 'batch embedding returns correct dimensions' do
      texts = ['Hello world', 'Goodbye world', 'Machine learning']
      result = pool.embed(texts)
      expect(result.rows).to eq(3)
      matrix(result).each { |row| expect(row.length).to eq(GTE_EMBEDDING_DIM) }
    end

    it 'cosine similarity: related texts score higher than unrelated' do
      q = pool.embed('query: How to train a neural network?').row(0)
      related = pool.embed('passage: Training neural networks requires backpropagation and gradient descent.').row(0)
      unrelated = pool.embed('passage: The recipe calls for two cups of flour and one egg.').row(0)

      sim_related = cosine_similarity(q, related)
      sim_unrelated = cosine_similarity(q, unrelated)
      expect(sim_related).to be > sim_unrelated
    end

    it 'long text truncation works silently' do
      long_text = 'word ' * 1000
      result = pool.embed(long_text)
      expect(result.rows).to eq(1)
      expect(result.dim).to eq(GTE_EMBEDDING_DIM)
    end

    it 'empty string handling' do
      result = pool.embed('')
      expect(result.rows).to eq(1)
      expect(result.dim).to eq(GTE_EMBEDDING_DIM)
    end

    it 'single text and batch produce consistent embeddings' do
      text = 'consistency test'
      single = pool.embed(text).row(0)
      batch = pool.embed([text, 'other text']).row(0)

      cosine = cosine_similarity(single, batch)
      max_abs = max_abs_diff(single, batch)
      expect(cosine).to be >= SINGLE_BATCH_MIN_COSINE
      expect(max_abs).to be <= SINGLE_BATCH_MAX_ABS_DIFF
    end

    it 'always returns L2-normalized vectors' do
      normalized = pool.embed('normalization test').row(0)
      norm = Math.sqrt(normalized.sum { |v| v * v })
      expect(norm).to be_within(1e-3).of(1.0)
    end

    it 'accepts an explicit output_tensor override' do
      overridden = GTE.config(GTE_E5_DIR) { |config| config.with(output_tensor: 'last_hidden_state') }
      result = overridden.embed('explicit output tensor')
      expect(result.rows).to eq(1)
      expect(result.dim).to eq(GTE_EMBEDDING_DIM)
    end

    it 'fails fast when output_tensor override is missing from model outputs' do
      expect do
        GTE.config(GTE_E5_DIR) { |c| c.with(output_tensor: 'pooled_sentence_embeddings_debiased_normalized') }
      end.to raise_error(
        GTE::Error,
        /requested output tensor.*pooled_sentence_embeddings_debiased_normalized.*model outputs/i
      )
    end

    it 'applies max_length truncation override' do
      overridden = GTE.config(GTE_E5_DIR) { |c| c.with(max_length: 8) }
      result = overridden.embed('word ' * 1000)
      expect(result.rows).to eq(1)
      expect(result.dim).to eq(GTE_EMBEDDING_DIM)
    end

    it 'truncates like tokenizer max length: suffix differences past max_length are ignored' do
      overridden = GTE.config(GTE_E5_DIR) { |c| c.with(max_length: 8) }
      prefix = ('sharedprefix ' * 64).strip
      a = overridden.embed("query: #{prefix} alpha_suffix").row(0)
      b = overridden.embed("query: #{prefix} beta_suffix totally different tail").row(0)
      expect(cosine_similarity(a, b)).to be >= 0.99999
      expect(max_abs_diff(a, b)).to be <= 1e-5
    end

    it 'accepts explicit padding mode overrides' do
      auto = GTE.config(GTE_E5_DIR) { |c| c.with(padding: 'auto') }
      fixed = GTE.config(GTE_E5_DIR) { |c| c.with(padding: 'fixed', max_length: 8) }
      batch_longest = GTE.config(GTE_E5_DIR) { |c| c.with(padding: 'batch_longest') }

      expect(auto.embed('padding mode test').dim).to eq(GTE_EMBEDDING_DIM)
      expect(fixed.embed('padding mode test').dim).to eq(GTE_EMBEDDING_DIM)
      expect(batch_longest.embed('padding mode test').dim).to eq(GTE_EMBEDDING_DIM)
    end

    it 'fails fast on invalid padding mode override' do
      expect do
        GTE.config(GTE_E5_DIR) { |c| c.with(padding: 'unknown') }
      end.to raise_error(GTE::Error, /padding mode.*auto, batch_longest, fixed/i)
    end

    it 'matches reference OnnxRuntime inference (mean pool + L2 normalize)' do
      text = 'query: the quick brown fox'
      gte_vec = pool.embed(text).row(0)

      tokens = reference_tokenize(File.join(GTE_E5_DIR, 'tokenizer.json'), text, no_padding: true)
      ref_model = OnnxRuntime::Model.new(File.join(GTE_E5_DIR, 'onnx', 'model.onnx'))
      outputs = ref_model.predict({
                                    input_ids: tokens[:input_ids],
                                    attention_mask: tokens[:attention_mask],
                                    token_type_ids: tokens[:type_ids]
                                  })
      hidden = outputs['last_hidden_state']
      ref_vec = reference_mean_pool_normalize(hidden, tokens[:attention_mask].first)

      expect(cosine_similarity(gte_vec, ref_vec)).to be >= REFERENCE_MIN_COSINE
    end
  end

  context 'CLIP', if: GTE_CLIP_AVAILABLE do
    let(:pool) { GTE.config(GTE_CLIP_DIR) }

    it 'batch embedding returns correct dimensions' do
      texts = ['a photo of a cat', 'a painting of a sunset']
      result = pool.embed(texts)
      expect(result.rows).to eq(2)
      matrix(result).each { |row| expect(row).to be_a(Array) }
    end

    it 'semantic similarity ordering' do
      texts = ['a photo of a cat', 'a picture of a kitten', 'a blueprint of a skyscraper']
      embeddings = matrix(pool.embed(texts))
      sim_related = cosine_similarity(embeddings[0], embeddings[1])
      sim_unrelated = cosine_similarity(embeddings[0], embeddings[2])
      expect(sim_related).to be > sim_unrelated
    end

    it 'matches reference OnnxRuntime inference (raw text_embeds + L2 normalize)' do
      text = 'a photo of a cat'
      gte_vec = pool.embed(text).row(0)

      tokens = reference_tokenize(File.join(GTE_CLIP_DIR, 'tokenizer.json'), text, no_padding: true)
      ref_model = OnnxRuntime::Model.new(File.join(GTE_CLIP_DIR, 'onnx', 'text_model.onnx'))
      outputs = ref_model.predict({ input_ids: tokens[:input_ids] })
      ref_vec = reference_raw_normalize(outputs['text_embeds'].first)

      expect(cosine_similarity(gte_vec, ref_vec)).to be >= REFERENCE_MIN_COSINE
    end
  end

  context 'Siglip2', if: GTE_SIGLIP2_AVAILABLE do
    let(:pool) { GTE.config(GTE_SIGLIP2_DIR) }
    let(:siglip2_pooler) do
      GTE.config(GTE_SIGLIP2_DIR) { |c| c.with(output_tensor: 'pooler_output') }
    end

    def direct_siglip2_pooler_output(text, fixed_padding:)
      tokenizer = Tokenizers.from_file(File.join(GTE_SIGLIP2_DIR, 'tokenizer.json'))
      tokenizer.no_padding unless fixed_padding

      encoding = tokenizer.encode_batch([text]).first
      input_ids = [encoding.ids]
      model = OnnxRuntime::Model.new(File.join(GTE_SIGLIP2_DIR, 'onnx', 'text_model.onnx'))
      model.predict({ input_ids: input_ids }, output_names: ['pooler_output']).fetch('pooler_output').first
    end

    it 'batch embedding returns correct dimensions' do
      texts = ['a photo of a cat', 'a photo of a dog']
      result = pool.embed(texts)
      expect(result.rows).to eq(2)
      matrix(result).each { |row| expect(row.length).to eq(GTE_SIGLIP2_EMBEDDING_DIM) }
    end

    it 'L2 normalization' do
      result = pool.embed('test normalization').row(0)
      norm = Math.sqrt(result.sum { |v| v * v })
      expect(norm).to be_within(1e-3).of(1.0)
    end

    it 'matches batch-longest pooler preprocessing used by Siglip2 text tokenization' do
      text = 'hello'
      gte = siglip2_pooler.embed(text).row(0)
      fixed = direct_siglip2_pooler_output(text, fixed_padding: true)
      unpadded = direct_siglip2_pooler_output(text, fixed_padding: false)

      expect(cosine_similarity(gte, unpadded)).to be >= 0.999
      expect(cosine_similarity(gte, fixed)).to be < 0.95
    end

    it 'does not fail on long text inputs' do
      text = ('sharedprefix ' * 240).strip
      result = pool.embed(text)
      expect(result.rows).to eq(1)
      expect(result.dim).to eq(GTE_SIGLIP2_EMBEDDING_DIM)
    end

    it 'matches reference OnnxRuntime inference (pooler_output + L2 normalize)' do
      text = 'a photo of a cat'
      gte_vec = pool.embed(text).row(0)

      tokens = reference_tokenize(File.join(GTE_SIGLIP2_DIR, 'tokenizer.json'), text, no_padding: true)
      ref_model = OnnxRuntime::Model.new(File.join(GTE_SIGLIP2_DIR, 'onnx', 'text_model.onnx'))
      outputs = ref_model.predict({ input_ids: tokens[:input_ids] })
      ref_vec = reference_raw_normalize(outputs['pooler_output'].first)

      expect(cosine_similarity(gte_vec, ref_vec)).to be >= REFERENCE_MIN_COSINE
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

    it 'multiple pools from different models can coexist' do
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
    let(:pool) { GTE.config(GTE_E5_DIR) }

    it 'batch embedding amortizes well (batch of 32 < 2x single time)' do
      single_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      pool.embed('single text benchmark')
      single_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - single_start

      batch_texts = Array.new(32) { |i| "batch text number #{i} for benchmark" }
      batch_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      pool.embed(batch_texts)
      batch_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - batch_start

      per_item = batch_time / 32.0
      puts "\n  [perf] single=#{(single_time * 1000).round(2)}ms batch32_per_item=#{(per_item * 1000).round(2)}ms"
      expect(per_item).to be < (single_time * 2)
    end
  end

  context 'concurrent single request path', if: GTE_E5_AVAILABLE do
    let(:pool) { GTE.config(GTE_E5_DIR) }

    it 'matches single string and single-item batch embeddings for one text' do
      text = 'batch engine probe'

      single_vec = pool.embed(text).row(0)
      batch_vec = pool.embed([text]).row(0)
      expect(cosine_similarity(single_vec, batch_vec)).to be >= SINGLE_BATCH_MIN_COSINE
      expect(max_abs_diff(single_vec, batch_vec)).to be <= SINGLE_BATCH_MAX_ABS_DIFF
    end

    it 'handles concurrent string requests with one vector per input' do
      texts = Array.new(32) { |i| "concurrent batch request #{i}" }

      results = Array.new(texts.length)
      threads = texts.each_with_index.map do |text, idx|
        Thread.new { results[idx] = pool.embed(text).row(0) }
      end
      threads.each(&:join)

      results.each do |row|
        expect(row.length).to eq(GTE_EMBEDDING_DIM)
      end
    end
  end
end
