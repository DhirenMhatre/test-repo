require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    let(:name) { 'Alice' }
    let(:user) { described_class.new(name) }

    it 'creates an instance of User' do
      expect(user).to be_a(described_class)
    end

    it 'does not raise an error when initialized with a name' do
      expect do
        described_class.new(name)
      end.not_to raise_error
    end

    context 'when name is nil' do
      let(:name) { nil }

      it 'allows initialization with nil name' do
        expect do
          described_class.new(name)
        end.not_to raise_error
      end
    end

    context 'when name is an empty string' do
      let(:name) { '' }

      it 'allows initialization with empty name' do
        expect do
          described_class.new(name)
        end.not_to raise_error
      end
    end
  end

  describe '#find_user' do
    let(:name) { 'Bob' }
    let(:user) { described_class.new(name) }
    let(:id) { 42 }
    let(:db_double) { class_double('DB') }

    before do
      stub_const('DB', db_double)
    end

    context 'with a valid integer id' do
      it 'executes a SELECT query with the given id' do
        expect(DB).to receive(:execute).with("SELECT * FROM users WHERE id = #{id}")
        user.find_user(id)
      end

      it 'returns the result of DB.execute' do
        result = double('result')
        allow(DB).to receive(:execute).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with a string id' do
      let(:id) { '123' }

      it 'interpolates the string id into the query' do
        expect(DB).to receive(:execute).with("SELECT * FROM users WHERE id = #{id}")
        user.find_user(id)
      end
    end

    context 'with a nil id' do
      let(:id) { nil }

      it 'builds a query with nil interpolated' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = ')
        user.find_user(id)
      end
    end

    context 'when DB.execute raises an error' do
      let(:error) { StandardError.new('DB failure') }

      it 'propagates the error' do
        allow(DB).to receive(:execute).and_raise(error)
        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'DB failure')
      end
    end
  end

  describe '#bad_method' do
    let(:name) { 'Charlie' }
    let(:user) { described_class.new(name) }

    it 'returns the sum of internal variables' do
      expect(user.bad_method).to eq(6)
    end

    it 'always returns an Integer' do
      expect(user.bad_method).to be_a(Integer)
    end

    it 'does not depend on initialization arguments' do
      other_user = described_class.new('Different')
      expect(other_user.bad_method).to eq(6)
    end
  end
end
