require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    let(:name) { 'Alice' }

    it 'creates an instance of User' do
      user = described_class.new(name)
      expect(user).to be_a(described_class)
    end

    it 'stores the provided name in an instance variable' do
      user = described_class.new(name)
      expect(user.instance_variable_get(:@name)).to eq('Alice')
    end

    context 'when name is nil' do
      let(:name) { nil }

      it 'allows nil and stores it' do
        user = described_class.new(name)
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end

    context 'when name is an empty string' do
      let(:name) { '' }

      it 'stores the empty string' do
        user = described_class.new(name)
        expect(user.instance_variable_get(:@name)).to eq('')
      end
    end

    context 'when called with the wrong number of arguments' do
      it 'raises ArgumentError when no arguments are provided' do
        expect do
          described_class.new
        end.to raise_error(ArgumentError)
      end

      it 'raises ArgumentError when more than one argument is provided' do
        expect do
          described_class.new('Alice', 'Extra')
        end.to raise_error(ArgumentError)
      end
    end
  end

  describe '#find_user' do
    let(:user) { described_class.new('Alice') }

    before do
      stub_const('DB', Class.new)
    end

    context 'when DB.execute succeeds' do
      let(:id) { 123 }

      it 'calls DB.execute with the interpolated SQL query' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = 123').and_return([{ 'id' => 123 }])
        user.find_user(id)
      end

      it 'returns the result from DB.execute' do
        allow(DB).to receive(:execute).and_return([{ 'id' => 123, 'name' => 'Alice' }])
        result = user.find_user(id)
        expect(result).to eq([{ 'id' => 123, 'name' => 'Alice' }])
      end
    end

    context 'when id is nil' do
      it 'still sends a query containing an empty interpolation' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = ').and_return([])
        user.find_user(nil)
      end
    end

    context 'when id is a string' do
      it 'interpolates the string directly into the query' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = abc').and_return([])
        user.find_user('abc')
      end
    end

    context 'when id contains SQL-like content' do
      let(:id) { '1; DROP TABLE users; --' }

      it 'passes the interpolated string through to DB.execute' do
        expected_query = 'SELECT * FROM users WHERE id = 1; DROP TABLE users; --'
        expect(DB).to receive(:execute).with(expected_query).and_return([])
        user.find_user(id)
      end
    end

    context 'when DB is not defined' do
      before do
        Object.send(:remove_const, :DB) if Object.const_defined?(:DB)
      end

      it 'raises NameError' do
        expect do
          user.find_user(1)
        end.to raise_error(NameError)
      end
    end

    context 'when DB.execute raises an error' do
      it 'propagates the exception' do
        allow(DB).to receive(:execute).and_raise(StandardError, 'db failure')

        expect do
          user.find_user(1)
        end.to raise_error(StandardError, 'db failure')
      end
    end
  end

  describe '#bad_method' do
    let(:user) { described_class.new('Alice') }

    it 'returns the sum of 1, 2, and 3' do
      expect(user.bad_method).to eq(6)
    end

    it 'is deterministic across calls' do
      first = user.bad_method
      second = user.bad_method
      expect(second).to eq(first)
    end

    it 'does not depend on @name' do
      user_with_other_name = described_class.new('Bob')
      expect(user_with_other_name.bad_method).to eq(6)
    end
  end
end
