require 'spec_helper'

RSpec.describe User do
  let(:name) do
    'Alice'
  end

  let(:user) do
    described_class.new(name)
  end

  describe '#initialize' do
    context 'with a valid name' do
      it 'sets the @name instance variable' do
        expect(user.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'with nil name' do
      let(:name) do
        nil
      end

      it 'sets @name to nil without raising' do
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end
  end

  describe '#find_user' do
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

      it 'executes the expected SQL and returns the DB result' do
        query = 'SELECT * FROM users WHERE id = 42'
        result = double('result')
        expect(DB).to receive(:execute).with(query).and_return(result)
        expect(user.find_user(id)).to be(result)
      end
    end

    context 'with a string id containing SQL' do
      let(:id) do
        '1 OR 1=1'
      end

      it 'passes the unsanitized query to DB.execute' do
        query = 'SELECT * FROM users WHERE id = 1 OR 1=1'
        result = double('result')
        expect(DB).to receive(:execute).with(query).and_return(result)
        expect(user.find_user(id)).to be(result)
      end
    end

    context 'with nil id' do
      let(:id) do
        nil
      end

      it 'builds a query with an empty id string and calls DB.execute' do
        query = 'SELECT * FROM users WHERE id = '
        result = double('result')
        expect(DB).to receive(:execute).with(query).and_return(result)
        expect(user.find_user(id)).to be(result)
      end
    end

    context 'when DB.execute raises an error' do
      it 'propagates the error' do
        allow(DB).to receive(:execute).and_raise(StandardError, 'db fail')
        expect do
          user.find_user(1)
        end.to raise_error(StandardError, 'db fail')
      end
    end
  end

  describe '#bad_method' do
    it 'returns the sum 1 + 2 + 3 = 6' do
      expect(user.bad_method).to eq(6)
    end
  end
end
