require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    let(:name) { 'Alice' }
    let(:user) { described_class.new(name) }

    it 'creates a User instance' do
      expect(user).to be_a(described_class)
    end

    it 'sets the @name instance variable' do
      expect(user.instance_variable_get(:@name)).to eq(name)
    end

    context 'when name is nil' do
      let(:name) { nil }

      it 'allows name to be nil' do
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end

    context 'when name is an empty string' do
      let(:name) { '' }

      it 'sets name to empty string' do
        expect(user.instance_variable_get(:@name)).to eq('')
      end
    end
  end

  describe '#find_user' do
    let(:name) { 'Bob' }
    let(:user) { described_class.new(name) }
    let(:db_double) { class_double('DB') }

    before do
      stub_const('DB', db_double)
    end

    context 'with a valid integer id' do
      let(:id) { 1 }
      let(:result) { [{ id: 1, name: 'Bob' }] }

      it 'executes a SELECT query with the given id' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = 1').and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with a string id' do
      let(:id) { '2' }
      let(:result) { [{ id: 2, name: 'Carol' }] }

      it 'interpolates the string id into the query' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = 2').and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with a nil id' do
      let(:id) { nil }

      it 'interpolates nil into the query' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = ').and_return([])
        expect(user.find_user(id)).to eq([])
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) { 3 }

      it 'propagates the error' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = 3').and_raise(StandardError.new('DB error'))
        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'DB error')
      end
    end
  end

  describe '#bad_method' do
    let(:user) { described_class.new('Dave') }

    it 'returns the sum of 1, 2, and 3' do
      expect(user.bad_method).to eq(6)
    end

    it 'always returns the same value regardless of instance state' do
      other_user = described_class.new('Eve')
      expect(other_user.bad_method).to eq(6)
    end
  end
end
