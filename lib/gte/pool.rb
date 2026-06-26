# frozen_string_literal: true

module GTE
  class Pool
    def initialize(model_dir, pool_size: nil)
      config = Embedder.default_config(model_dir)
      config = yield(config) if block_given?

      prev_size = pool_size ? ENV['GTE_SESSION_POOL_SIZE'] : nil
      ENV['GTE_SESSION_POOL_SIZE'] = pool_size.to_s if pool_size
      @model = Model.new(config)
    ensure
      ENV['GTE_SESSION_POOL_SIZE'] = prev_size if pool_size
      @pool_size = pool_size || resolve_pool_size
      warmup if @model
    end

    def embed(texts)
      @model.embed(texts)
    end

    def embed_binary(text)
      @model.embed_binary(text)
    end

    def warmup
      @pool_size.times.map { Thread.new { @model.embed('warmup') } }.each(&:join)
    end

    private

    def resolve_pool_size
      env = ENV.fetch('GTE_SESSION_POOL_SIZE', nil)
      return env.to_i if env && !env.empty?

      puma = ENV.fetch('PUMA_MAX_THREADS', nil)
      return puma.to_i if puma && !puma.empty?

      1
    end
  end
end
