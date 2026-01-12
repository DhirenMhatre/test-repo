require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  let(:name) { 'Alice' }
  let(:user) do
    described_class.new(name)
  end

  describe '#initialize' do
    it 'creates a User instance with the given name' do
      expect(user).to be_a(described_class)
    end

    context 'when name is nil' do
      let(:name) { nil }

      it 'still creates a User instance' do
        expect(user).to be_a(described_class)
      end
    end

    context 'when name is an empty string' do
      let(:name) { '' }

      it 'still creates a User instance' do
        expect(user).to be_a(described_class)
      end
    end
  end

  describe '#find_user' do
    let(:db_double) do
      double('DB')
    end

    before do
      stub_const('DB', db_double)
    end

    context 'with a valid integer id' do
      let(:id) { 1 }
      let(:result) do
        [{ 'id' => 1, 'name' => 'Alice' }]
      end

      it 'executes a SELECT query with the given id' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = 1').and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with a string id' do
      let(:id) { '2' }
      let(:result) do
        [{ 'id' => 2, 'name' => 'Bob' }]
      end

      it 'interpolates the string id into the query' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = 2').and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with a nil id' do
      let(:id) { nil }

      it 'interpolates nil into the query string' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = ').and_return(nil)
        expect(user.find_user(id)).to be_nil
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
    it 'returns the sum of x, y, and z' do
      expect(user.bad_method).to eq(6)
    end

    it 'always returns 6 regardless of name' do
      other_user = described_class.new('Bob')
      expect(other_user.bad_method).to eq(6)
    end
  end
end
