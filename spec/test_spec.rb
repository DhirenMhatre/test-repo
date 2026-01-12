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

      it 'creates an instance even with nil name' do
        expect(user).to be_a(described_class)
      end
    end

    context 'when name is an empty string' do
      let(:name) { '' }

      it 'creates an instance even with empty name' do
        expect(user).to be_a(described_class)
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
      let(:fake_result) { [{ 'id' => 1, 'name' => 'Bob' }] }

      it 'executes a SELECT query with the given id' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = 1').and_return(fake_result)
        result = user.find_user(id)
        expect(result).to eq(fake_result)
      end
    end

    context 'with a string id' do
      let(:id) { '2' }
      let(:fake_result) { [{ 'id' => 2, 'name' => 'Carol' }] }

      it 'interpolates the string id directly into the query' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = 2').and_return(fake_result)
        result = user.find_user(id)
        expect(result).to eq(fake_result)
      end
    end

    context 'with a potentially unsafe id (SQL injection attempt)' do
      let(:id) { '1; DROP TABLE users;' }

      it 'passes the raw interpolated query to DB.execute' do
        expected_query = 'SELECT * FROM users WHERE id = 1; DROP TABLE users;'
        expect(DB).to receive(:execute).with(expected_query)
        user.find_user(id)
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) { 3 }

      it 'propagates the error' do
        expect(DB).to receive(:execute).and_raise(StandardError.new('DB failure'))
        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'DB failure')
      end
    end

    context 'with nil id' do
      let(:id) { nil }

      it 'builds a query with nil interpolated' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = ').and_return([])
        result = user.find_user(id)
        expect(result).to eq([])
      end
    end
  end

  describe '#bad_method' do
    let(:user) { described_class.new('Dave') }

    it 'returns the sum of 1, 2, and 3' do
      expect(user.bad_method).to eq(6)
    end

    it 'always returns the same value regardless of instance state' do
      another_user = described_class.new('Eve')
      expect(user.bad_method).to eq(another_user.bad_method)
    end

    it 'does not raise an error when called' do
      expect do
        user.bad_method
      end.not_to raise_error
    end
  end
end
