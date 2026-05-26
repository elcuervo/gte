# frozen_string_literal: true

# rubocop:disable Style/OneClassPerFile

require 'gte'
require 'onnxruntime'
require 'tokenizers'
require 'numo/narray'

module GteRuntimeWrapper
  def self.build(model_dir)
    model_dir = File.expand_path(model_dir)

    case ENV.fetch('BENCH_MODEL', 'e5')
    when 'siglip2' then Siglip2.new(model_dir)
    when 'clip'    then Clip.new(model_dir)
    else                E5.new(model_dir)
    end
  end

  class Base
    def embed(text)
      @model[text]
    end
  end

  class E5 < Base
    def name = 'gte'

    def initialize(model_dir)
      super()
      @model = GTE.config(model_dir) do |c|
        c.with(model_name: 'model.onnx', output_tensor: 'last_hidden_state',
               max_length: 512, execution_providers: 'cpu')
      end
    end

    def embed(text) = @model["query: #{text}"]
  end

  class Siglip2 < Base
    def name = 'gte'

    def initialize(model_dir)
      super()
      @model = GTE.config(model_dir) do |c|
        c.with(model_name: 'text_model.onnx', output_tensor: 'pooler_output',
               max_length: 64, execution_providers: 'cpu')
      end
    end
  end

  class Clip < Base
    def name = 'gte'

    def initialize(model_dir)
      super()
      @model = GTE.config(model_dir) do |c|
        c.with(output_tensor: 'sentence_embedding',
               max_length: 512, execution_providers: 'cpu')
      end
    end
  end
end

module PureRubyRuntime
  MODEL_CANDIDATES = %w[
    onnx/text_model.onnx text_model.onnx onnx/model.onnx model.onnx
  ].freeze

  def self.build(model_dir)
    model_dir = File.expand_path(model_dir)
    tokenizer_path = File.join(model_dir, 'tokenizer.json')

    model_path = MODEL_CANDIDATES
                 .map { |c| File.join(model_dir, c) }
                 .find { |p| File.exist?(p) }

    raise "no ONNX model found in #{model_dir}" unless model_path

    model = OnnxRuntime::Model.new(model_path)
    tokenizer = Tokenizers.from_file(tokenizer_path)

    case ENV.fetch('BENCH_MODEL', 'e5')
    when 'siglip2'
      output_key = find_output(model, 'pooler_output')
      Siglip2.new(model, tokenizer, output_key)
    when 'clip'
      output_key = find_output(model, 'sentence_embedding')
      Clip.new(model, tokenizer, output_key)
    else
      output_key = find_output(model, 'last_hidden_state')
      E5.new(model, tokenizer, output_key)
    end
  end

  def self.find_output(model, preferred)
    outputs = model.outputs.map { |o| o[:name] }
    outputs.find { |n| n&.downcase == preferred } || outputs.first || 'last_hidden_state'
  end

  class Base
    def name = 'pure_ruby'

    def initialize(model, tokenizer, output_key)
      @model = model
      @tokenizer = tokenizer
      @output_key = output_key
      @model_inputs = model.inputs.map { |i| i[:name] }
    end

    def embed_batch(text, prefix)
      input = prefix ? "#{prefix}#{text}" : text
      @tokenizer.no_padding
      encoded = @tokenizer.encode(input)
      inputs = { input_ids: [encoded.ids] }
      inputs[:attention_mask] = [encoded.attention_mask] if @model_inputs.include?('attention_mask')
      inputs[:token_type_ids] = [encoded.type_ids] if @model_inputs.include?('token_type_ids')
      result = @model.predict(inputs, output_names: [@output_key])
      output = result.fetch(@output_key)
      output = if output.first.first.is_a?(Array)
                 mean_pool(output.first, encoded.attention_mask)
               else
                 output.first
               end
      l2_normalize(output)
    end

    private

    def mean_pool(hidden, mask)
      dim = hidden.first.length
      result = Array.new(dim, 0.0)
      count = 0.0
      hidden.each_with_index do |token_vec, i|
        next if mask[i].zero?

        token_vec.each_with_index { |v, j| result[j] += v }
        count += 1
      end
      result.map! { |v| v / count }
    end

    def l2_normalize(vector)
      sum = Math.sqrt(vector.map { |v| v * v }.sum)
      vector.map { |v| v / sum }
    end
  end

  class E5 < Base
    def embed(text) = embed_batch(text, 'query: ')
  end

  class Siglip2 < Base
    def embed(text) = embed_batch(text.downcase[0, 126], nil)
  end

  class Clip < Base
    def embed(text) = embed_batch(text, nil)
  end
end

RUNTIME = case ENV.fetch('BENCH_RUNTIME', 'gte')
          when 'gte'
            model = GteRuntimeWrapper.build(ENV.fetch('MODEL_DIR'))
            GTE.warmup(model, threads: 5)
            model
          when 'pure_ruby' then PureRubyRuntime.build(ENV.fetch('MODEL_DIR'))
          else raise "Unknown BENCH_RUNTIME=#{ENV.fetch('BENCH_RUNTIME')}"
          end

# rubocop:enable Style/OneClassPerFile
