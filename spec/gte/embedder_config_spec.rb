# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GTE::Embedder do
  describe '.default_config' do
    it 'returns the shared text embedding defaults' do
      config = described_class.default_config('/tmp/demo-model')

      expect(config.model_dir).to eq('/tmp/demo-model')
      expect(config.optimization_level).to eq(3)
      expect(config.normalize).to be(true)
      expect(config.execution_providers).to be_nil
    end
  end

  describe '.from_config' do
    it 'expands a text config into native embedder constructor arguments' do
      expect(described_class).to receive(:new).with(
        '/tmp/demo-model',
        3,
        '',
        false,
        'sentence_embedding',
        256,
        'fixed',
        'cpu'
      ).and_return(:built)

      config = described_class.default_config('/tmp/demo-model').with(
        normalize: false,
        output_tensor: 'sentence_embedding',
        max_length: 256,
        padding: 'fixed',
        execution_providers: 'cpu'
      )

      expect(described_class.from_config(config)).to eq(:built)
    end
  end

  describe '.config' do
    it 'uses the shared text embedding defaults' do
      expect(described_class).to receive(:from_config) do |config|
        expect(config.normalize).to be(true)
        :embedder
      end

      expect(described_class.config('/tmp/gte-shared-defaults')).to eq(:embedder)
    end
  end
end

RSpec.describe GTE do
  describe '.config' do
    it 'uses the embedder shared text defaults' do
      expect(GTE::Model).to receive(:new) do |config|
        expect(config.normalize).to be(true)
        :model
      end

      expect(described_class.config('/tmp/gte-shared-defaults')).to eq(:model)
    end
  end
end
