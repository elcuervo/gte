# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Binary tensor path', if: GTE_E5_AVAILABLE do
  let(:model) { GTE.config(GTE_E5_DIR) }
  let(:text) { 'query: cat' }

  it 'returns native f32 bytes matching the Array path' do
    tensor = model.embed(text)
    arr = tensor.row(0)
    bin = tensor.row_binary_f32(0)

    expect(bin).to be_a(String)
    expect(bin.encoding).to eq(Encoding::ASCII_8BIT)
    expect(bin.bytesize).to eq(arr.size * 4)

    unpacked = bin.unpack('e*') # little-endian f32
    expect(unpacked.size).to eq(arr.size)
    unpacked.zip(arr).each do |b, a|
      expect(b).to be_within(1e-6).of(a)
    end
  end

  it 'first_binary_f32 mirrors row_binary_f32(0)' do
    tensor = model.embed(text)
    expect(tensor.first_binary_f32).to eq(tensor.row_binary_f32(0))
  end

  it 'Model#embed_binary returns row 0 as bytes' do
    bytes = model.embed_binary(text)
    arr = model.embed(text).row(0)
    expect(bytes.unpack('e*').size).to eq(arr.size)
  end

  it 'cosine similarity of binary vs Array path is ~1.0' do
    tensor = model.embed(text)
    arr = tensor.row(0)
    unpacked = tensor.row_binary_f32(0).unpack('e*')
    dot = arr.zip(unpacked).sum { |x, y| x * y }
    na = Math.sqrt(arr.sum { |v| v * v })
    nb = Math.sqrt(unpacked.sum { |v| v * v })
    expect(dot / (na * nb)).to be_within(1e-6).of(1.0)
  end

  it 'binary path produces compact buffer matching embedding dim' do
    tensor = model.embed(text)
    bin = tensor.row_binary_f32(0)
    arr = tensor.row(0)
    # f32 bytes: 4 × dim. Ruby Array slot: 8B pointer/flonum each + Array
    # header. Binary path is ~2× denser and skips per-element wrapping.
    expect(bin.bytesize).to eq(arr.size * 4)
  end

  it 'binary path retained-object footprint matches single String, not Array+slots' do
    GC.start
    before = ObjectSpace.count_objects[:T_STRING]
    bins = Array.new(50) { model.embed_binary(text) }
    after = ObjectSpace.count_objects[:T_STRING]
    # Each call produces 1 String for the row. Sanity-check the binary path
    # doesn't sneakily allocate extra strings per element.
    expect(after - before).to be_between(50, 200), "T_STRING delta=#{after - before}"
    expect(bins.size).to eq(50)
  end
end
