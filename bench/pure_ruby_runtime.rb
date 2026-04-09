# frozen_string_literal: true

require 'json'
require 'onnxruntime'
require 'tokenizers'

module PureRubyTextEmbedding
  class Error < StandardError; end
  class MissingModelDirectory < Error; end

  class TextEncoder
    MODEL_CANDIDATES = [
      'onnx/text_model.onnx',
      'text_model.onnx',
      'onnx/model.onnx',
      'model.onnx'
    ].freeze

    OUTPUT_PREFERENCES = %w[
      text_embeds
      pooler_output
      sentence_embedding
      last_hidden_state
    ].freeze

    DEFAULT_MAX_LENGTH = 512
    MAX_SUPPORTED_LENGTH = 8192

    def initialize(model_dir:)
      @model_dir = File.expand_path(model_dir)
      raise MissingModelDirectory, "model directory not found: #{@model_dir}" unless Dir.exist?(@model_dir)

      @tokenizer_path = File.join(@model_dir, 'tokenizer.json')
      raise Error, "tokenizer.json not found in #{@model_dir}" unless File.exist?(@tokenizer_path)

      @model_path = resolve_model_path!
      @model = OnnxRuntime::Model.new(@model_path)
      @input_names = @model.inputs.map { |input| input.fetch(:name) }
      validate_supported_inputs!

      @output_name = select_output_name!
      @output_rank = output_rank!(@output_name)
      if @output_rank == 3 && !@input_names.include?('attention_mask')
        raise Error, 'mean pooling requires attention_mask input'
      end

      @max_length = read_max_length
      @tokenizer = Tokenizers.from_file(@tokenizer_path)
      @tokenizer.no_padding
      @tokenizer.no_truncation
    end

    def embed(texts)
      rows = Array(texts).map(&:to_s)
      return [] if rows.empty?

      encodings = @tokenizer.encode_batch(rows)
      feeds = build_feeds(encodings)
      output = @model.predict(feeds, output_names: [@output_name]).fetch(@output_name)

      vectors = case @output_rank
                when 2
                  output
                when 3
                  mean_pool(output, feeds.fetch(:attention_mask))
                else
                  raise Error, "unsupported output rank #{@output_rank}"
                end

      normalize_l2(vectors)
    end

    private

    def resolve_model_path!
      MODEL_CANDIDATES.each do |relative|
        candidate = File.join(@model_dir, relative)
        return candidate if File.exist?(candidate)
      end

      raise Error, "no ONNX model found in #{@model_dir} (checked text_model.onnx and model.onnx)"
    end

    def validate_supported_inputs!
      unsupported = @input_names.reject { |name| %w[input_ids attention_mask token_type_ids].include?(name) }
      return if unsupported.empty?

      message = "unsupported model inputs for text embedding API: #{unsupported.join(', ')}"
      message += if unsupported.include?('pixel_values')
                   '. This looks like a multimodal graph. Provide a text-only export (for example onnx/text_model.onnx).'
                 else
                   '. Supported inputs are: input_ids, attention_mask, token_type_ids.'
                 end
      raise Error, message
    end

    def select_output_name!
      output_names = @model.outputs.map { |output| output.fetch(:name) }
      raise Error, 'model has no outputs' if output_names.empty?

      OUTPUT_PREFERENCES.each do |preferred|
        output_names.each do |name|
          lower = name.downcase
          return name if lower == preferred || lower.end_with?("/#{preferred}")
        end
      end

      output_names.first
    end

    def output_rank!(output_name)
      output = @model.outputs.find { |entry| entry.fetch(:name) == output_name }
      raise Error, "output tensor '#{output_name}' not found" unless output

      output.fetch(:shape).length
    end

    def read_max_length
      config_path = File.join(@model_dir, 'tokenizer_config.json')
      return DEFAULT_MAX_LENGTH unless File.exist?(config_path)

      value = JSON.parse(File.read(config_path))['model_max_length']
      parsed = case value
               when Integer then value
               when Float then value.to_i
               when String then Integer(value, exception: false)
               end

      return DEFAULT_MAX_LENGTH unless parsed&.positive?

      [parsed, MAX_SUPPORTED_LENGTH].min
    rescue JSON::ParserError
      DEFAULT_MAX_LENGTH
    end

    def build_feeds(encodings)
      max_len = [encodings.map { |encoding| encoding.ids.length }.max || 0, @max_length].min
      input_ids = encodings.map { |encoding| pad_to_max(encoding.ids, max_len) }
      feeds = { input_ids: input_ids }

      if @input_names.include?('attention_mask')
        feeds[:attention_mask] = encodings.map { |encoding| pad_to_max(encoding.attention_mask, max_len) }
      end

      if @input_names.include?('token_type_ids')
        feeds[:token_type_ids] = encodings.map { |encoding| pad_to_max(encoding.type_ids, max_len) }
      end

      feeds
    end

    def pad_to_max(values, max_len)
      trimmed = values.first(max_len)
      trimmed + Array.new(max_len - trimmed.length, 0)
    end

    def mean_pool(hidden_states, attention_mask)
      hidden_states.each_with_index.map do |token_rows, batch_idx|
        mask_row = attention_mask[batch_idx]
        dim = token_rows.first.length
        sum = Array.new(dim, 0.0)
        weight_sum = 0.0

        token_rows.each_with_index do |token_vector, token_idx|
          weight = mask_row[token_idx].to_i
          next if weight <= 0

          weight_sum += weight
          token_vector.each_with_index do |value, dim_idx|
            sum[dim_idx] += value * weight
          end
        end

        next sum if weight_sum.zero?

        inverse = 1.0 / weight_sum
        sum.map { |value| value * inverse }
      end
    end

    def normalize_l2(vectors)
      vectors.map do |row|
        norm = Math.sqrt(row.sum { |value| value * value })
        next row.dup if norm.zero?

        inverse = 1.0 / norm
        row.map { |value| value * inverse }
      end
    end
  end
end
