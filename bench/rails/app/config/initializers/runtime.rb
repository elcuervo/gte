require "gte"
require "onnxruntime"
require "tokenizers"
require "numo/narray"

module GteRuntimeWrapper
  def self.build(model_dir)
    model_dir = File.expand_path(model_dir)

    case ENV.fetch("BENCH_MODEL", "e5")
    when "siglip2" then Siglip2.new(model_dir)
    when "clip"    then Clip.new(model_dir)
    else                E5.new(model_dir)
    end
  end

  class Base
    def embed(text)
      @model[text]
    end
  end

  class E5 < Base
    def name = "gte"
    def initialize(model_dir)
      @model = GTE.config(model_dir) do |c|
        c.with(model_name: "model.onnx", output_tensor: "last_hidden_state",
               max_length: 512, execution_providers: "cpu")
      end
    end
  end

  class Siglip2 < Base
    def name = "gte"
    def initialize(model_dir)
      @model = GTE.config(model_dir) do |c|
        c.with(model_name: "text_model.onnx", output_tensor: "pooler_output",
               max_length: 64, execution_providers: "cpu")
      end
    end
  end

  class Clip < Base
    def name = "gte"
    def initialize(model_dir)
      @model = GTE.config(model_dir) do |c|
        c.with(output_tensor: "sentence_embedding",
               max_length: 512, execution_providers: "cpu")
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
    tokenizer_path = File.join(model_dir, "tokenizer.json")

    model_path = MODEL_CANDIDATES
      .map { |c| File.join(model_dir, c) }
      .find { |p| File.exist?(p) }

    unless model_path
      raise "no ONNX model found in #{model_dir}"
    end

    model = OnnxRuntime::Model.new(model_path)
    tokenizer = Tokenizers.from_file(tokenizer_path)

    case ENV.fetch("BENCH_MODEL", "e5")
    when "siglip2"
      output_key = find_output(model, "pooler_output")
      Siglip2.new(model, tokenizer, output_key)
    when "clip"
      output_key = find_output(model, "sentence_embedding")
      Clip.new(model, tokenizer, output_key)
    else
      output_key = find_output(model, "last_hidden_state")
      E5.new(model, tokenizer, output_key)
    end
  end

  def self.find_output(model, preferred)
    outputs = model.outputs.map { |o| o[:name] }
    outputs.find { |n| n.downcase == preferred } || outputs.first || "last_hidden_state"
  end

  class Base
    def name = "pure_ruby"
    def initialize(model, tokenizer, output_key)
      @model = model
      @tokenizer = tokenizer
      @output_key = output_key
    end

    def embed_batch(text, prefix)
      input = prefix ? "#{prefix}#{text}" : text
      encoded = @tokenizer.encode(input)
      result = @model.predict({ input_ids: [encoded.ids] }, output_names: [@output_key])
      output = result.fetch(@output_key).first
      l2_normalize(output)
    end

    private

    def l2_normalize(vector)
      sum = Math.sqrt(vector.map { |v| v * v }.sum)
      vector.map { |v| v / sum }
    end
  end

  class E5 < Base
    def embed(text) = embed_batch(text, "query: ")
  end

  class Siglip2 < Base
    def embed(text) = embed_batch(text.downcase[0, 126], nil)
  end

  class Clip < Base
    def embed(text) = embed_batch(text, nil)
  end
end

RUNTIME = case ENV.fetch("BENCH_RUNTIME", "gte")
          when "gte"        then GteRuntimeWrapper.build(ENV.fetch("MODEL_DIR"))
          when "pure_ruby"  then PureRubyRuntime.build(ENV.fetch("MODEL_DIR"))
          else raise "Unknown BENCH_RUNTIME=#{ENV.fetch("BENCH_RUNTIME")}"
          end
