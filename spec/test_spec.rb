require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    context 'with a valid name' do
      let(:name) do
        'Alice'
      end

      it 'initializes with the given name' do
        user = described_class.new(name)
        expect(user.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'with nil name' do
      it 'sets @name to nil without raising' do
        user = nil
        expect do
          user = described_class.new(nil)
        end.not_to raise_error
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end

    context 'without arguments' do
      it 'raises ArgumentError' do
        expect do
          described_class.new
        end.to raise_error(ArgumentError)
      end
    end

    context 'with too many arguments' do
      it 'raises ArgumentError' do
        expect do
          described_class.new('Alice', 'Extra')
        end.to raise_error(ArgumentError)
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

    context 'with numeric id' do
      let(:id) do
        42
      end

      let(:query) do
        'SELECT * FROM users WHERE id = ' + id.to_s
      end

      it 'calls DB.execute with the constructed SQL and returns the result' do
        expected_result = ['row1', 'row2']
        expect(DB).to receive(:execute).with(query).and_return(expected_result)
        result = user.find_user(id)
        expect(result).to eq(expected_result)
      end
    end

    context 'with string id containing special characters' do
      let(:id) do
        '1 OR 1=1'
      end

      let(:query) do
        'SELECT * FROM users WHERE id = ' + id
      end

      it 'passes the id directly into the SQL string' do
        expect(DB).to receive(:execute).with(query).and_return('ok')
        result = user.find_user(id)
        expect(result).to eq('ok')
      end
    end

    context 'with nil id' do
      let(:id) do
        nil
      end

      let(:query) do
        'SELECT * FROM users WHERE id = '
      end

      it 'constructs a query with a blank id and returns the DB result' do
        expect(DB).to receive(:execute).with(query).and_return([])
        result = user.find_user(id)
        expect(result).to eq([])
      end
    end

    context 'when DB.execute raises an error' do
      it 'propagates the error' do
        allow(DB).to receive(:execute).and_raise(StandardError.new('DB error'))
        expect do
          user.find_user(1)
        end.to raise_error(StandardError, 'DB error')
      end
    end
  end

  describe '#bad_method' do
    let(:user) do
      described_class.new('Test')
    end

    it 'returns the sum of internal variables' do
      expect(user.bad_method).to eq(6)
    end

    it 'returns an Integer' do
      expect(user.bad_method).to be_a(Integer)
    end
  end
end
