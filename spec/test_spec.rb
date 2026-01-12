require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  let(:name) { 'Alice' }
  let(:user) { described_class.new(name) }

  describe '#initialize' do
    it 'creates a User instance with the given name' do
      expect(user).to be_a(described_class)
    end

    context 'when name is nil' do
      let(:name) { nil }

      it 'allows name to be nil' do
        expect(user).to be_a(described_class)
      end
    end

    context 'when name is an empty string' do
      let(:name) { '' }

      it 'creates a user with an empty name' do
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
      let(:id) { 1 }

      it 'executes a SQL query with the given id and returns the result' do
        expected_query = "SELECT * FROM users WHERE id = #{id}"
        expected_result = [{ 'id' => 1, 'name' => 'Alice' }]

        expect(DB).to receive(:execute).with(expected_query).and_return(expected_result)

        result = user.find_user(id)
        expect(result).to eq(expected_result)
      end
    end

    context 'with a string id' do
      let(:id) { '2' }

      it 'interpolates the string id into the SQL query and returns the result' do
        expected_query = "SELECT * FROM users WHERE id = #{id}"
        expected_result = [{ 'id' => 2, 'name' => 'Bob' }]

        expect(DB).to receive(:execute).with(expected_query).and_return(expected_result)

        result = user.find_user(id)
        expect(result).to eq(expected_result)
      end
    end

    context 'with a nil id' do
      let(:id) { nil }

      it 'interpolates nil into the SQL query and returns the result from DB' do
        expected_query = "SELECT * FROM users WHERE id = #{id}"
        expected_result = []

        expect(DB).to receive(:execute).with(expected_query).and_return(expected_result)

        result = user.find_user(id)
        expect(result).to eq(expected_result)
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) { 3 }

      it 'propagates the error' do
        expected_query = "SELECT * FROM users WHERE id = #{id}"
        error = StandardError.new('DB failure')

        expect(DB).to receive(:execute).with(expected_query).and_raise(error)

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
        first_call = user.bad_method
        second_call = user.bad_method
        expect(first_call).to eq(6)
        expect(second_call).to eq(6)
      end
    end
  end
end
