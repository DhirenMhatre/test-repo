require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    context 'with a valid name' do
      let(:name) do
        'Alice'
      end

      let(:user) do
        described_class.new(name)
      end

      it 'sets the @name instance variable' do
        expect(user.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'with nil name' do
      let(:name) do
        nil
      end

      let(:user) do
        described_class.new(name)
      end

      it 'allows nil and sets @name to nil' do
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end
  end

  describe '#find_user' do
    let(:user) do
      described_class.new('Alice')
    end

    let(:db_double) do
      double('DB')
    end

    before do
      stub_const('DB', db_double)
    end

    context 'when id is an integer' do
      let(:id) do
        1
      end

      let(:result) do
        [{ 'id' => 1, 'name' => 'Alice' }]
      end

      it 'executes the expected SQL and returns the DB result' do
        expect(db_double).to receive(:execute).with('SELECT * FROM users WHERE id = 1').and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'when id is a numeric string' do
      let(:id) do
        '2'
      end

      let(:result) do
        [{ 'id' => 2, 'name' => 'Bob' }]
      end

      it 'interpolates the string as-is and returns the DB result' do
        expect(db_double).to receive(:execute).with('SELECT * FROM users WHERE id = 2').and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'when id is nil' do
      let(:id) do
        nil
      end

      let(:result) do
        []
      end

      it 'builds a SQL with empty id and returns the DB result' do
        expect(db_double).to receive(:execute).with('SELECT * FROM users WHERE id = ').and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'when id contains SQL injection content' do
      let(:id) do
        '1; DROP TABLE users'
      end

      let(:result) do
        'danger'
      end

      it 'passes the concatenated SQL directly to DB.execute' do
        expect(db_double).to receive(:execute).with('SELECT * FROM users WHERE id = 1; DROP TABLE users').and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) do
        3
      end

      it 'propagates the error' do
        expect(db_double).to receive(:execute).with('SELECT * FROM users WHERE id = 3').and_raise(StandardError,
                                                                                                  'db down')
        operation = lambda do
          user.find_user(id)
        end
        expect(operation).to raise_error(StandardError, 'db down')
      end
    end
  end

  describe '#bad_method' do
    let(:user) do
      described_class.new('X')
    end

    it 'returns the sum of internal values' do
      expect(user.bad_method).to eq(6)
    end

    it 'returns the same result across repeated calls' do
      first = user.bad_method
      second = user.bad_method
      expect(first).to eq(6)
      expect(second).to eq(6)
    end
  end
end
