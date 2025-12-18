require 'spec_helper'
RSpec.describe User do
  describe '#initialize' do
    context 'with a non-empty name' do
      let(:name) do
        'Alice'
      end

      it 'sets @name to the provided name' do
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
  end

  describe '#find_user' do
    let(:name) do
      'Alice'
    end

    let(:user) do
      described_class.new(name)
    end

    let(:db) do
      double('DB')
    end

    before do
      stub_const('DB', db)
    end

    context 'with an integer id' do
      let(:id) do
        42
      end

      let(:expected_query) do
        'SELECT * FROM users WHERE id = 42'
      end

      it 'executes the constructed SQL and returns the result' do
        expect(db).to receive(:execute).with(expected_query).and_return('db_result')
        result = user.find_user(id)
        expect(result).to eq('db_result')
      end
    end

    context 'with a numeric string id' do
      let(:id) do
        '7'
      end

      let(:expected_query) do
        'SELECT * FROM users WHERE id = 7'
      end

      it 'interpolates the string id without quotes and returns the result' do
        expect(db).to receive(:execute).with(expected_query).and_return('db_result')
        result = user.find_user(id)
        expect(result).to eq('db_result')
      end
    end

    context 'with a malicious id string' do
      let(:id) do
        '1 OR 1=1'
      end

      let(:expected_query) do
        'SELECT * FROM users WHERE id = 1 OR 1=1'
      end

      it 'passes the raw interpolated query to the DB' do
        expect(db).to receive(:execute).with(expected_query).and_return('db_result')
        result = user.find_user(id)
        expect(result).to eq('db_result')
      end
    end

    context 'with a nil id' do
      let(:id) do
        nil
      end

      let(:expected_query) do
        'SELECT * FROM users WHERE id = '
      end

      it 'interpolates nil to an empty string and calls DB.execute' do
        expect(db).to receive(:execute).with(expected_query).and_return('db_result')
        result = user.find_user(id)
        expect(result).to eq('db_result')
      end
    end

    context 'when DB.execute raises an error' do
      it 'propagates the error' do
        allow(db).to receive(:execute).and_raise(StandardError.new('db down'))
        expect do
          user.find_user(1)
        end.to raise_error(StandardError, 'db down')
      end
    end
  end

  describe '#bad_method' do
    context 'with any name' do
      let(:user) do
        described_class.new('Anything')
      end

      it 'returns the sum of internal values' do
        expect(user.bad_method).to eq(6)
      end
    end

    context 'with nil name' do
      let(:user) do
        described_class.new(nil)
      end

      it 'still returns 6' do
        expect(user.bad_method).to eq(6)
      end
    end
  end
end
