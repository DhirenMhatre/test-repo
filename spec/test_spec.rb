require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    let(:user) { described_class.new(name) }

    context 'with a normal string name' do
      let(:name) { 'Alice' }

      it 'sets @name to the provided value' do
        expect(user.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'when name is nil' do
      let(:name) { nil }

      it 'sets @name to nil' do
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end

    context 'when name is an empty string' do
      let(:name) { '' }

      it 'sets @name to an empty string' do
        expect(user.instance_variable_get(:@name)).to eq('')
      end
    end

    context 'when name is a non-string object' do
      let(:name) { { first: 'A' } }

      it 'stores the object as-is' do
        expect(user.instance_variable_get(:@name)).to eq({ first: 'A' })
      end
    end
  end

  describe '#find_user' do
    let(:user) { described_class.new('Bob') }
    let(:db_double) { double('DB') }

    before do
      stub_const('DB', db_double)
    end

    context 'with an integer id' do
      let(:id) { 42 }
      let(:expected_query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'calls DB.execute with the interpolated SQL and returns the result' do
        result = [{ 'id' => 42, 'name' => 'Bob' }]
        expect(DB).to receive(:execute).with(expected_query).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with a string id that looks like an injection' do
      let(:id) { '1; DROP TABLE users;' }
      let(:expected_query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'passes the raw id into the SQL string and returns DB response' do
        result = []
        expect(DB).to receive(:execute).with(expected_query).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'when id is nil' do
      let(:id) { nil }
      let(:expected_query) { 'SELECT * FROM users WHERE id = ' }

      it 'includes an empty string for nil in the SQL and returns DB response' do
        result = []
        expect(DB).to receive(:execute).with(expected_query).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) { 99 }
      let(:expected_query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'propagates the error' do
        error = StandardError.new('DB down')
        expect(DB).to receive(:execute).with(expected_query).and_raise(error)
        expect do
          user.find_user(id)
        end.to raise_error(error)
      end
    end

    context 'when DB.execute returns nil' do
      let(:id) { 5 }
      let(:expected_query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'returns nil' do
        expect(DB).to receive(:execute).with(expected_query).and_return(nil)
        expect(user.find_user(id)).to be_nil
      end
    end
  end

  describe '#bad_method' do
    let(:user) { described_class.new('X') }

    it 'returns the sum of 1, 2, and 3' do
      expect(user.bad_method).to eq(6)
    end

    it 'returns an Integer' do
      expect(user.bad_method).to be_a(Integer)
    end

    context 'when called multiple times' do
      it 'is deterministic across calls' do
        first = user.bad_method
        second = user.bad_method
        expect(first).to eq(6)
        expect(second).to eq(6)
        expect(first).to eq(second)
      end
    end
  end
end
