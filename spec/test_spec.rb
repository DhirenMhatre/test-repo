require 'spec_helper'

RSpec.describe User do
  let(:name) { 'Alice' }
  let(:user) { described_class.new(name) }

  describe '#initialize' do
    context 'with a valid name string' do
      it 'sets @name to the provided value' do
        expect(user.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'with nil name' do
      let(:name) { nil }

      it 'sets @name to nil' do
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end

    context 'with non-string name' do
      let(:name) { 123 }

      it 'stores the value as-is' do
        expect(user.instance_variable_get(:@name)).to eq(123)
      end
    end
  end

  describe '#find_user' do
    let(:db_double) { double('DB') }

    before do
      stub_const('DB', db_double)
    end

    context 'with an integer id' do
      let(:id) { 42 }
      let(:result) do
        [{ 'id' => 42, 'name' => 'Bob' }]
      end

      it 'executes the correct SQL query and returns DB result' do
        expect(DB).to receive(:execute).with("SELECT * FROM users WHERE id = 42").and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with a string id' do
      let(:id) { '7' }
      let(:result) { ['row'] }

      it 'executes the query with the id interpolated as-is' do
        expect(DB).to receive(:execute).with("SELECT * FROM users WHERE id = 7").and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with a malicious id string' do
      let(:id) { "1; DROP TABLE users; --" }

      it 'passes the unsanitized value directly into the SQL string' do
        expected_query = "SELECT * FROM users WHERE id = 1; DROP TABLE users; --"
        expect(DB).to receive(:execute).with(expected_query).and_return(:ok)
        expect(user.find_user(id)).to eq(:ok)
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) { 1 }

      it 'propagates the error' do
        allow(DB).to receive(:execute).and_raise(StandardError.new('db error'))
        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'db error')
      end
    end
  end

  describe '#bad_method' do
    it 'returns the sum of 1, 2, and 3' do
      expect(user.bad_method).to eq(6)
    end

    context 'when called with unexpected arguments' do
      it 'raises ArgumentError' do
        expect do
          user.bad_method(1)
        end.to raise_error(ArgumentError)
      end
    end
  end
end
