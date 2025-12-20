require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    context 'with a valid name' do
      it 'creates a User instance' do
        user = described_class.new('Alice')
        expect(user).to be_a(described_class)
      end
    end

    context 'with nil name' do
      it 'creates a User instance' do
        user = described_class.new(nil)
        expect(user).to be_a(described_class)
      end
    end

    context 'without arguments' do
      it 'raises ArgumentError' do
        expect do
          described_class.new
        end.to raise_error(ArgumentError)
      end
    end
  end

  describe '#find_user' do
    let(:name) do
      'Alice'
    end

    let(:user) do
      described_class.new(name)
    end

    let(:db_double) do
      double('DB')
    end

    before do
      stub_const('DB', db_double)
    end

    context 'with an integer id' do
      it 'executes the expected SQL and returns the DB result' do
        id = 42
        expected_query = 'SELECT * FROM users WHERE id = 42'
        expected_result = [{ 'id' => 42, 'name' => 'Alice' }]

        expect(db_double).to receive(:execute).with(expected_query).and_return(expected_result)

        result = user.find_user(id)
        expect(result).to eq(expected_result)
      end
    end

    context 'with a negative integer id' do
      it 'executes the expected SQL and returns the DB result' do
        id = -1
        expected_query = 'SELECT * FROM users WHERE id = -1'
        expected_result = []

        expect(db_double).to receive(:execute).with(expected_query).and_return(expected_result)

        result = user.find_user(id)
        expect(result).to eq(expected_result)
      end
    end

    context 'with a string id (possible injection)' do
      it 'interpolates the string directly into the SQL and returns the DB result' do
        id = '1 OR 1=1'
        expected_query = 'SELECT * FROM users WHERE id = 1 OR 1=1'
        expected_result = [{ 'id' => 1, 'name' => 'Admin' }]

        expect(db_double).to receive(:execute).with(expected_query).and_return(expected_result)

        result = user.find_user(id)
        expect(result).to eq(expected_result)
      end
    end

    context 'with nil id' do
      it 'interpolates to an empty string and calls DB.execute with the resulting SQL' do
        id = nil
        expected_query = 'SELECT * FROM users WHERE id = '
        expected_result = []

        expect(db_double).to receive(:execute).with(expected_query).and_return(expected_result)

        result = user.find_user(id)
        expect(result).to eq(expected_result)
      end
    end

    context 'when DB.execute raises an error' do
      it 'propagates the error' do
        id = 5
        expected_query = 'SELECT * FROM users WHERE id = 5'

        expect(db_double).to receive(:execute).with(expected_query).and_raise(StandardError.new('DB error'))

        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'DB error')
      end
    end
  end

  describe '#bad_method' do
    let(:user) do
      described_class.new('Bob')
    end

    it 'returns the sum of internal variables' do
      expect(user.bad_method).to eq(6)
    end

    it 'returns the same result regardless of initialization name' do
      other_user = described_class.new(nil)
      expect(other_user.bad_method).to eq(6)
    end
  end
end
