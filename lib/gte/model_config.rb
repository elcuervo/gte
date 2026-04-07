# frozen_string_literal: true

module GTE
  # User-facing model configuration. Preset factories for known model families,
  # or construct with arbitrary parameters for any ONNX text model.
  class ModelConfig
    attr_reader :max_length, :output_tensor, :mode, :with_type_ids, :with_attention_mask,
                :num_threads, :optimization_level

    def initialize(max_length:, output_tensor:, mode: :raw, with_type_ids: false,
                   with_attention_mask: true, num_threads: 0, optimization_level: 3)
      @max_length = max_length
      @output_tensor = output_tensor
      @mode = mode
      @with_type_ids = with_type_ids
      @with_attention_mask = with_attention_mask
      @num_threads = num_threads
      @optimization_level = optimization_level
    end

    def self.e5 = new(max_length: 512, output_tensor: "last_hidden_state", mode: :mean_pool, with_type_ids: true)
    def self.clip = new(max_length: 77, output_tensor: "text_embeds", mode: :raw, with_attention_mask: false)
    def self.siglip2 = new(max_length: 64, output_tensor: "pooler_output", mode: :raw, with_attention_mask: false)
  end
end
