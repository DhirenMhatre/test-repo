require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  let(:name) { 'Alice' }
  let(:user) { described_class.new(name) }

  describe '#initialize' do
    context 'with a valid name' do
      it 'creates a User instance' do
        expect(user).to be_a(described_class)
      end
    end

    context 'with nil name' do
      let(:name) { nil }

      it 'still creates a User instance' do
        expect(user).to be_a(described_class)
      end
    end

    context 'with empty string name' do
      let(:name) { '' }

      it 'still creates a User instance' do
        expect(user).to be_a(described_class)
      end
    end
  end

  describe '#find_user' do
    let(:db_double) { class_double('DB') }

    before do
      stub_const('DB', db_double)
    end

    context 'with a valid integer id' do
      let(:id) { 42 }
      let(:expected_query) { 'SELECT * FROM users WHERE id = 42' }

      it 'executes the query on DB and returns the result' do
        result = double('result')
        expect(DB).to receive(:execute).with(expected_query).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with a string id' do
      let(:id) { '7' }
      let(:expected_query) { 'SELECT * FROM users WHERE id = 7' }

      it 'interpolates the string id into the query and calls DB.execute' do
        result = double('result')
        expect(DB).to receive(:execute).with(expected_query).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with a nil id' do
      let(:id) { nil }
      let(:expected_query) { 'SELECT * FROM users WHERE id = ' }

      it 'builds a query with nil converted to empty string and calls DB.execute' do
        result = double('result')
        expect(DB).to receive(:execute).with(expected_query).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) { 1 }
      let(:expected_query) { 'SELECT * FROM users WHERE id = 1' }

      it 'propagates the error' do
        expect(DB).to receive(:execute).with(expected_query).and_raise(StandardError.new('DB failure'))
        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'DB failure')
      end
    end
  end

  describe '#bad_method' do
    it 'returns the sum of internal variables' do
      expect(user.bad_method).to eq(6)
    end

    context 'when called multiple times' do
      it 'returns the same result each time' do
        first = user.bad_method
        second = user.bad_method
        expect(first).to eq(6)
        expect(second).to eq(6)
      end
    end
  end
end
