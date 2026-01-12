require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    let(:name) { 'Alice' }
    let(:user) { described_class.new(name) }

    it 'creates an instance of User' do
      expect(user).to be_a(described_class)
    end

    it 'does not raise an error with a string name' do
      expect do
        described_class.new('Bob')
      end.not_to raise_error
    end

    context 'when name is nil' do
      let(:name) { nil }

      it 'initializes the user without raising an error' do
        expect do
          user
        end.not_to raise_error
      end
    end

    context 'when name is an empty string' do
      let(:name) { '' }

      it 'initializes the user without raising an error' do
        expect do
          user
        end.not_to raise_error
      end
    end
  end

  describe '#find_user' do
    let(:name) { 'Alice' }
    let(:user) { described_class.new(name) }
    let(:db_double) { class_double('DB') }

    before do
      stub_const('DB', db_double)
    end

    context 'with a valid integer id' do
      let(:id) { 1 }
      let(:expected_query) { 'SELECT * FROM users WHERE id = 1' }
      let(:db_result) { [{ 'id' => 1, 'name' => 'Alice' }] }

      it 'executes the correct SQL query' do
        expect(DB).to receive(:execute).with(expected_query).and_return(db_result)
        result = user.find_user(id)
        expect(result).to eq(db_result)
      end
    end

    context 'with a string id' do
      let(:id) { '2' }
      let(:expected_query) { 'SELECT * FROM users WHERE id = 2' }
      let(:db_result) { [{ 'id' => 2, 'name' => 'Bob' }] }

      it 'interpolates the id into the SQL query as given' do
        expect(DB).to receive(:execute).with(expected_query).and_return(db_result)
        result = user.find_user(id)
        expect(result).to eq(db_result)
      end
    end

    context 'with a non-numeric string id (potential injection)' do
      let(:id) { '1; DROP TABLE users;' }
      let(:expected_query) { 'SELECT * FROM users WHERE id = 1; DROP TABLE users;' }
      let(:db_result) { [] }

      it 'passes the raw interpolated query to DB.execute' do
        expect(DB).to receive(:execute).with(expected_query).and_return(db_result)
        result = user.find_user(id)
        expect(result).to eq(db_result)
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) { 3 }
      let(:expected_query) { 'SELECT * FROM users WHERE id = 3' }

      it 'propagates the error' do
        expect(DB).to receive(:execute).with(expected_query).and_raise(StandardError.new('DB failure'))
        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'DB failure')
      end
    end

    context 'with nil id' do
      let(:id) { nil }
      let(:expected_query) { 'SELECT * FROM users WHERE id = ' }
      let(:db_result) { [] }

      it 'builds a query with an empty id interpolation' do
        expect(DB).to receive(:execute).with(expected_query).and_return(db_result)
        result = user.find_user(id)
        expect(result).to eq(db_result)
      end
    end
  end

  describe '#bad_method' do
    let(:user) { described_class.new('Alice') }

    it 'returns the sum of internal variables' do
      result = user.bad_method
      expect(result).to eq(6)
    end

    it 'always returns an Integer' do
      expect(user.bad_method).to be_a(Integer)
    end

    it 'does not raise an error when called multiple times' do
      expect do
        5.times do
          user.bad_method
        end
      end.not_to raise_error
    end
  end
end
