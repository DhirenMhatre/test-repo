require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    context 'with a valid name' do
      let(:name) { 'Alice' }
      let(:user) { described_class.new(name) }

      it 'sets the @name instance variable' do
        expect(user.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'with nil name' do
      let(:name) { nil }
      let(:user) { described_class.new(name) }

      it 'allows nil and sets @name to nil' do
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end

    context 'with wrong arity' do
      it 'raises ArgumentError when no arguments are provided' do
        expect { described_class.new }.to raise_error(ArgumentError)
      end

      it 'raises ArgumentError when too many arguments are provided' do
        expect { described_class.new('a', 'b') }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#find_user' do
    let(:user) { described_class.new('Bob') }

    before do
      stub_const('DB', double('DB'))
    end

    context 'with integer id' do
      it 'constructs correct SQL and returns DB.execute result' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = 42').and_return([{ 'id' => 42 }])
        result = user.find_user(42)
        expect(result).to eq([{ 'id' => 42 }])
      end
    end

    context 'with string id (possible injection)' do
      it 'interpolates the string id directly into the SQL' do
        malicious_id = '1 OR 1=1'
        expected_query = 'SELECT * FROM users WHERE id = 1 OR 1=1'
        expect(DB).to receive(:execute).with(expected_query).and_return(:rows)
        result = user.find_user(malicious_id)
        expect(result).to eq(:rows)
      end
    end

    context 'with nil id' do
      it 'interpolates nil as empty string in the SQL' do
        expected_query = 'SELECT * FROM users WHERE id = '
        expect(DB).to receive(:execute).with(expected_query).and_return([])
        expect(user.find_user(nil)).to eq([])
      end
    end

    context 'when DB.execute raises an error' do
      it 'propagates the error' do
        allow(DB).to receive(:execute).and_raise(StandardError, 'DB failure')
        expect { user.find_user(5) }.to raise_error(StandardError, 'DB failure')
      end
    end
  end

  describe '#bad_method' do
    let(:user) { described_class.new('Carol') }

    it 'returns the sum of internal variables' do
      expect(user.bad_method).to eq(6)
    end

    context 'when called with unexpected arguments' do
      it 'raises ArgumentError' do
        expect { user.bad_method(1) }.to raise_error(ArgumentError)
      end
    end
  end
end
