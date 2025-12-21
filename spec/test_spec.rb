require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    context 'with a valid name' do
      let(:name) do
        'Alice'
      end

      it 'sets @name to the given value' do
        user = described_class.new(name)
        expect(user.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'with nil name' do
      let(:name) do
        nil
      end

      it 'sets @name to nil' do
        user = described_class.new(name)
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end

    context 'with empty string' do
      let(:name) do
        ''
      end

      it 'sets @name to empty string' do
        user = described_class.new(name)
        expect(user.instance_variable_get(:@name)).to eq('')
      end
    end
  end

  describe '#find_user' do
    let(:name) do
      'Bob'
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

    context 'with integer id' do
      let(:id) do
        1
      end

      let(:expected_query) do
        'SELECT * FROM users WHERE id = 1'
      end

      let(:db_result) do
        [{ 'id' => 1, 'name' => 'Bob' }]
      end

      it 'executes the correct SQL and returns DB result' do
        expect(DB).to receive(:execute).with(expected_query).and_return(db_result)
        result = user.find_user(id)
        expect(result).to eq(db_result)
      end
    end

    context 'with string id containing SQL injection payload' do
      let(:id) do
        "1; DROP TABLE users; --"
      end

      let(:expected_query) do
        "SELECT * FROM users WHERE id = 1; DROP TABLE users; --"
      end

      let(:db_result) do
        []
      end

      it 'interpolates id directly into SQL and forwards to DB' do
        expect(DB).to receive(:execute).with(expected_query).and_return(db_result)
        result = user.find_user(id)
        expect(result).to eq(db_result)
      end
    end

    context 'with id containing quotes' do
      let(:id) do
        "'OR'1'='1"
      end

      let(:expected_query) do
        "SELECT * FROM users WHERE id = 'OR'1'='1"
      end

      let(:db_result) do
        []
      end

      it 'passes the raw id through without escaping' do
        expect(DB).to receive(:execute).with(expected_query).and_return(db_result)
        result = user.find_user(id)
        expect(result).to eq(db_result)
      end
    end

    context 'with nil id' do
      let(:id) do
        nil
      end

      let(:expected_query) do
        "SELECT * FROM users WHERE id = "
      end

      let(:db_result) do
        nil
      end

      it 'interpolates nil as an empty string and returns DB result' do
        expect(DB).to receive(:execute).with(expected_query).and_return(db_result)
        result = user.find_user(id)
        expect(result).to be_nil
      end
    end

    context 'when DB raises an error' do
      let(:id) do
        2
      end

      let(:expected_query) do
        'SELECT * FROM users WHERE id = 2'
      end

      let(:db_error) do
        StandardError.new('db failure')
      end

      it 'propagates the error' do
        expect(DB).to receive(:execute).with(expected_query).and_raise(db_error)
        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'db failure')
      end
    end
  end

  describe '#bad_method' do
    let(:name) do
      'Carol'
    end

    let(:user) do
      described_class.new(name)
    end

    it 'returns the sum of 1, 2, and 3 (6)' do
      expect(user.bad_method).to eq(6)
    end

    it 'does not modify @name' do
      user.bad_method
      expect(user.instance_variable_get(:@name)).to eq('Carol')
    end
  end
end
