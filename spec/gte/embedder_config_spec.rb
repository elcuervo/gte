# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GTE::Embedder do
  describe '.default_config' do
    it 'returns the shared text embedding defaults' do
      config = described_class.default_config('/tmp/demo-model')

      expect(config.model_dir).to eq('/tmp/demo-model')
      expect(config.optimization_level).to eq(3)
      expect(config.execution_providers).to be_nil
    end
  end

  describe '.from_config' do
    it 'expands a text config into native embedder constructor arguments' do
      expect(described_class).to receive(:new).with(
        '/tmp/demo-model',
        3,
        '',
        'sentence_embedding',
        256,
        'fixed',
        'cpu'
      ).and_return(:built)

      config = described_class.default_config('/tmp/demo-model').with(
        output_tensor: 'sentence_embedding',
        max_length: 256,
        padding: 'fixed',
        execution_providers: 'cpu'
      )

      expect(described_class.from_config(config)).to eq(:built)
    end
  end
end

RSpec.describe GTE::Pool do
  describe '.new' do
    it 'constructs a pool from a model directory' do
      model_double = instance_double(GTE::Model, embed: nil)
      expect(GTE::Model).to receive(:new).and_return(model_double)
      expect_any_instance_of(GTE::Pool).to receive(:warmup)

      pool = GTE::Pool.new('/tmp/gte-shared-defaults')
      expect(pool).to be_a(GTE::Pool)
    end

    it 'configures pool_size env var during construction' do
      prev = ENV['GTE_SESSION_POOL_SIZE']
      expect_any_instance_of(GTE::Pool).to receive(:warmup)
      model_double = instance_double(GTE::Model, embed: nil)
      expect(GTE::Model).to receive(:new).and_return(model_double)

      GTE::Pool.new('/tmp', pool_size: 4)
      expect(ENV.fetch('GTE_SESSION_POOL_SIZE', '')).to eq(prev || '')
    ensure
      ENV.delete('GTE_SESSION_POOL_SIZE') unless prev
    end

    it 'raises GTE::Error for nonexistent directory' do
      expect { GTE::Pool.new('/nonexistent/path') }.to raise_error(GTE::Error)
    end

    it 'raises GTE::Error for invalid padding mode' do
      expect do
        GTE::Pool.new('/nonexistent') { |c| c.with(padding: 'invalid') }
      end.to raise_error(GTE::Error)
    end

    it 'embed_binary delegates to model' do
      model_double = instance_double(GTE::Model, embed_binary: "\x00\x00\x80?".b, embed: nil)
      expect(GTE::Model).to receive(:new).and_return(model_double)
      expect_any_instance_of(GTE::Pool).to receive(:warmup)

      pool = GTE::Pool.new('/tmp')
      result = pool.embed_binary('test')
      expect(result).to be_a(String)
      expect(result.encoding).to eq(Encoding::ASCII_8BIT)
    end

    it 'model is not a public method' do
      expect(GTE::Pool.public_instance_methods).not_to include(:model)
    end
  end
end
