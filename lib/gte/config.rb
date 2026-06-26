# frozen_string_literal: true

module GTE
  module Config
    Text = Data.define(
      :model_dir, :optimization_level,
      :model_name, :output_tensor, :max_length, :padding, :execution_providers
    )

    Reranker = Data.define(
      :model_dir, :optimization_level,
      :model_name, :sigmoid, :output_tensor, :max_length, :padding, :execution_providers
    )
  end
end
